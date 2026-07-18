//
//  CryptoWatchlistSectionView.swift
//  SahamIndo
//
//  Section crypto yang di-embed di HomeView, muncul saat tab "Crypto" aktif
//  di WatchlistTabSelectorView (bukan layar/tab terpisah). Harga real-time
//  langsung dari Binance WebSocket (lihat BinanceLiveStore) — tidak lewat
//  backend kita sama sekali.
//

import SwiftUI
import Combine

struct CryptoWatchlistSectionView: View {

    @StateObject private var watchlistStore = CryptoWatchlistStore()
    @ObservedObject private var liveStore    = BinanceLiveStore.shared

    @State private var searchText:    String = ""
    @State private var searchResults: [CryptoAsset] = []
    @State private var isSearching:   Bool = false
    @State private var searchTask:    Task<Void, Never>? = nil

    var body: some View {
        VStack(spacing: 0) {
            searchBar
                .padding(.horizontal)
                .padding(.top, 12)

            if !searchText.isEmpty {
                searchResultsList
            } else if watchlistStore.symbols.isEmpty {
                emptyWatchlistState
            } else {
                watchlistList
            }
        }
        .onAppear {
            liveStore.updateSubscriptions(watchlistStore.symbols)
        }
        .onChange(of: watchlistStore.symbols) { _, newValue in
            liveStore.updateSubscriptions(newValue)
        }
        .onDisappear {
            liveStore.disconnect()
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundColor(.secondary)
            TextField("Cari koin (BTC, Ethereum, Solana, ...)", text: $searchText)
                .autocorrectionDisabled()
                .onChange(of: searchText) { _, newValue in
                    searchTask?.cancel()
                    guard !newValue.trimmingCharacters(in: .whitespaces).isEmpty else {
                        searchResults = []
                        isSearching = false
                        return
                    }
                    isSearching = true
                    searchTask = Task {
                        // Debounce kecil supaya tidak nembak network tiap ketikan.
                        try? await Task.sleep(nanoseconds: 300_000_000)
                        guard !Task.isCancelled else { return }
                        let results = await liveStore.searchAssets(query: newValue)
                        guard !Task.isCancelled else { return }
                        searchResults = results
                        isSearching  = false
                    }
                }
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    searchResults = []
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                }
            }
        }
        .padding(10)
        .background(Color.appCardBackground)
        .cornerRadius(10)
    }

    // MARK: - Watchlist

    private var watchlistList: some View {
        LazyVStack(spacing: 0) {
            ForEach(watchlistStore.symbols, id: \.self) { symbol in
                CryptoRowView(symbol: symbol, ticker: liveStore.ticker(for: symbol))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .contextMenu {
                        Button(role: .destructive) {
                            watchlistStore.remove(symbol)
                        } label: {
                            Label("Hapus dari watchlist", systemImage: "trash")
                        }
                    }
                Divider().padding(.horizontal, 16)
            }
        }
        .padding(.top, 12)
    }

    private var emptyWatchlistState: some View {
        VStack(spacing: 10) {
            Image(systemName: "bitcoinsign.circle")
                .font(.system(size: 36))
                .foregroundColor(.secondary.opacity(0.5))
            Text("Watchlist crypto masih kosong.")
                .font(.system(size: 14, weight: .medium))
            Text("Cari koin di atas untuk mulai memantau harganya.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    // MARK: - Search Results

    private var searchResultsList: some View {
        LazyVStack(spacing: 0) {
            if isSearching {
                ProgressView().padding(.top, 40)
            } else if searchResults.isEmpty {
                Text("Tidak ditemukan.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .padding(.top, 40)
            } else {
                ForEach(searchResults) { asset in
                    searchResultRow(asset)
                    Divider().padding(.horizontal, 16)
                }
            }
        }
        .padding(.top, 12)
    }

    private func searchResultRow(_ asset: CryptoAsset) -> some View {
        let inWatchlist = watchlistStore.contains(asset.symbol)
        return HStack(spacing: 10) {
            CryptoAvatarView(baseAsset: asset.baseAsset)
            VStack(alignment: .leading, spacing: 2) {
                Text(asset.displayName).font(.system(size: 15, weight: .semibold))
                Text(asset.symbol).font(.system(size: 11)).foregroundColor(.secondary)
            }
            Spacer()
            Button {
                if inWatchlist { watchlistStore.remove(asset.symbol) }
                else           { watchlistStore.add(asset.symbol) }
            } label: {
                Image(systemName: inWatchlist ? "checkmark.circle.fill" : "plus.circle")
                    .font(.system(size: 22))
                    .foregroundColor(inWatchlist ? Color.ProfitGreen : Color.PrimaryYellow)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

// MARK: - CryptoRowView

struct CryptoRowView: View {
    let symbol: String
    let ticker: CryptoTicker?

    /// Data historis 24 jam untuk mini-sparkline (klines Binance) — sumbernya
    /// beda dari saham (yang lewat backend/candles kita), tapi tampilannya
    /// dibikin sama persis lewat CryptoSparklineView.
    @StateObject private var sparklineVM = CryptoSparklineViewModel()

    /// State untuk animasi flash warna (hijau naik / merah turun) di angka
    /// harga. Efek "rolling digit" (kayak odometer/speedometer) ditangani
    /// oleh RollingCryptoPriceView + RollingPriceDigit (dipakai bareng
    /// dengan StockDetailView — didefinisikan di StockDetailView.swift,
    /// generik, tidak spesifik saham).
    @State private var flashColor: Color? = nil

    private var displayName: String {
        BinanceLiveStore.shared.displayName(forSymbol: symbol)
    }

    var body: some View {
        HStack(spacing: 10) {
            CryptoAvatarView(baseAsset: String(displayName.prefix(1)))
            VStack(alignment: .leading, spacing: 2) {
                Text(displayName).font(.system(size: 15, weight: .bold))
                Text(symbol).font(.system(size: 11)).foregroundColor(.secondary)
            }
            Spacer(minLength: 0)
            CryptoSparklineView(vm: sparklineVM)
                .frame(width: DesignSize.sparklineWidth, height: DesignSize.sparklineHeight)
                .padding(.trailing, 8)
            VStack(alignment: .trailing, spacing: 2) {
                if let ticker {
                    // Cuma teks angkanya yang nge-flash & "roll" per-digit —
                    // bukan background/kotak row-nya.
                    RollingCryptoPriceView(price: ticker.lastPrice, fontSize: 16)
                        .foregroundColor(flashColor ?? .primary)
                    let isPositive = ticker.priceChangePercent >= 0
                    HStack(spacing: 3) {
                        Image(systemName: isPositive ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 9, weight: .bold))
                        Text(String(format: "%+.2f%%", ticker.priceChangePercent))
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(isPositive ? Color.ProfitGreen : Color.LossRed)
                } else {
                    ProgressView().frame(width: 60, height: 20)
                }
            }
        }
        .task(id: symbol) { await sparklineVM.fetch(symbol: symbol) }
        .onReceive(Timer.publish(every: 2 * 60, on: .main, in: .common).autoconnect()) { _ in
            Task { await sparklineVM.fetch(symbol: symbol) }
        }
        .onChange(of: ticker?.lastPrice) { oldValue, newValue in
            triggerFlash(old: oldValue, new: newValue)
        }
    }

    /// Nyalakan flash warna (hijau naik / merah turun) di teks angka —
    /// gerakan "roll" per-digit-nya sendiri sudah otomatis ditangani oleh
    /// RollingPriceDigit tiap value-nya berubah, jadi di sini cuma perlu
    /// urus warnanya, fade balik normal setelah sesaat.
    private func triggerFlash(old: Double?, new: Double?) {
        guard let old, let new, new != old else { return }
        flashColor = new > old ? Color.ProfitGreen : Color.LossRed
        Task {
            try? await Task.sleep(nanoseconds: 700_000_000)
            withAnimation(.easeOut(duration: 0.5)) {
                flashColor = nil
            }
        }
    }
}

// MARK: - RollingCryptoPriceView
//
// Efek "speedometer"/odometer: tiap digit di angka harga berputar vertikal
// independen saat nilainya berubah — sama persis teknik yang dipakai
// RollingPriceView di StockDetailView, cuma sumber formatnya beda
// (formatCryptoPrice, desimal adaptif, bukan formatPrice per-market).
// RollingPriceDigit reused langsung dari StockDetailView.swift (generik,
// satu target/module yang sama, tidak perlu didefinisikan ulang).

struct RollingCryptoPriceView: View {
    let price:    Double
    let fontSize: CGFloat

    private var formatted: String { formatCryptoPrice(price) }
    private var tokens: [(id: Int, char: Character)] { Array(formatted.enumerated()).map { ($0.offset, $0.element) } }

    var body: some View {
        HStack(spacing: 1) {
            ForEach(tokens, id: \.id) { token in
                if let digit = token.char.wholeNumberValue {
                    RollingPriceDigit(digit: digit, delay: Double(token.id) * 0.04, fontSize: fontSize)
                } else {
                    Text(String(token.char)).font(.system(size: fontSize, weight: .semibold, design: .rounded))
                }
            }
        }
    }
}

// MARK: - CryptoSparklineViewModel
//
// Mengambil klines 24 jam terakhir langsung dari REST Binance (interval 15m,
// 96 candle = 24 jam) untuk digambar sebagai mini-sparkline di row watchlist.
// Sengaja TIDAK lewat backend kita — konsisten dengan BinanceLiveStore yang
// juga langsung ke Binance. Response klines Binance bertipe campuran
// (angka + string dalam satu array), jadi di-parse via JSONSerialization.

@MainActor
final class CryptoSparklineViewModel: ObservableObject {
    @Published private(set) var closes: [Double] = []

    func fetch(symbol: String) async {
        let sym = symbol.uppercased()
        guard let url = URL(string:
            "https://api.binance.com/api/v3/klines?symbol=\(sym)&interval=15m&limit=96")
        else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let rows = try JSONSerialization.jsonObject(with: data) as? [[Any]] else { return }
            // index 4 = harga close (Binance kirim sebagai String).
            let parsed: [Double] = rows.compactMap { row in
                guard row.count > 4 else { return nil }
                if let s = row[4] as? String  { return Double(s) }
                if let n = row[4] as? NSNumber { return n.doubleValue }
                return nil
            }
            guard !parsed.isEmpty else { return }
            self.closes = parsed
        } catch {
            // Diamkan — sparkline sekadar kosong kalau gagal, tidak fabrikasi data.
        }
    }
}

// MARK: - CryptoSparklineView
//
// Versi ringkas dari MiniSparklineView (saham): karena crypto 24/7 tidak ada
// konsep jam bursa / slot, titik cukup di-spasikan rata. Warna dibelah di
// baseline = harga 24 jam lalu (closes[0]) — hijau di atas, merah di bawah —
// biar konsisten dengan % change 24 jam yang ditampilkan di sebelahnya.

struct CryptoSparklineView: View {

    @ObservedObject var vm: CryptoSparklineViewModel

    private let green = Color.ProfitGreen
    private let red   = Color.LossRed

    var body: some View {
        Canvas { ctx, size in
            let closes = vm.closes
            guard closes.count > 1 else { return }

            let startVal = closes[0]
            let minVal   = closes.min()!
            let maxVal   = closes.max()!
            let range    = max(maxVal - minVal, 1e-9)
            let w = size.width; let h = size.height; let padV: CGFloat = 4
            let usableH  = h - padV * 2

            func xFor(_ i: Int) -> CGFloat { CGFloat(i) / CGFloat(closes.count - 1) * w }
            func yFor(_ v: Double) -> CGFloat { padV + usableH * (1 - CGFloat((v - minVal) / range)) }

            let startY = yFor(startVal)

            func buildArea(closeY: CGFloat) -> Path {
                var p = Path()
                p.move(to: CGPoint(x: xFor(0), y: closeY))
                for i in 0..<closes.count {
                    let x = xFor(i); let y = yFor(closes[i])
                    if i == 0 { p.addLine(to: CGPoint(x: x, y: y)) }
                    else {
                        let px = xFor(i - 1); let py = yFor(closes[i - 1])
                        p.addCurve(to: CGPoint(x: x, y: y),
                                   control1: CGPoint(x: px + (x - px) * 0.5, y: py),
                                   control2: CGPoint(x: px + (x - px) * 0.5, y: y))
                    }
                }
                p.addLine(to: CGPoint(x: xFor(closes.count - 1), y: closeY))
                p.closeSubpath(); return p
            }

            func buildLine() -> Path {
                var p = Path()
                for i in 0..<closes.count {
                    let x = xFor(i); let y = yFor(closes[i])
                    if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
                    else {
                        let px = xFor(i - 1); let py = yFor(closes[i - 1])
                        p.addCurve(to: CGPoint(x: x, y: y),
                                   control1: CGPoint(x: px + (x - px) * 0.5, y: py),
                                   control2: CGPoint(x: px + (x - px) * 0.5, y: y))
                    }
                }
                return p
            }

            let lineStyle = StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round)
            let line = buildLine()

            ctx.drawLayer { layer in
                layer.clip(to: Path(CGRect(x: 0, y: 0, width: w, height: startY)))
                layer.fill(buildArea(closeY: startY), with: .linearGradient(
                    Gradient(stops: [.init(color: green.opacity(0.18), location: 0),
                                     .init(color: green.opacity(0.06), location: 1)]),
                    startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: startY)))
                layer.stroke(line, with: .color(green), style: lineStyle)
            }
            ctx.drawLayer { layer in
                layer.clip(to: Path(CGRect(x: 0, y: startY, width: w, height: h - startY)))
                layer.fill(buildArea(closeY: h), with: .linearGradient(
                    Gradient(stops: [.init(color: red.opacity(0.18), location: 0),
                                     .init(color: red.opacity(0.04), location: 1)]),
                    startPoint: CGPoint(x: 0, y: startY), endPoint: CGPoint(x: 0, y: h)))
                layer.stroke(line, with: .color(red), style: lineStyle)
            }

            let lastY     = yFor(closes.last!)
            let lastColor = closes.last! >= startVal ? green : red
            var dash = Path()
            dash.move(to: CGPoint(x: 0, y: lastY)); dash.addLine(to: CGPoint(x: w, y: lastY))
            ctx.stroke(dash, with: .color(lastColor.opacity(0.5)),
                       style: StrokeStyle(lineWidth: 0.75, dash: [3, 3]))
            let dotX = xFor(closes.count - 1); let dotR: CGFloat = 2.5
            ctx.fill(Path(ellipseIn: CGRect(x: dotX - dotR, y: lastY - dotR, width: dotR * 2, height: dotR * 2)),
                     with: .color(lastColor))
        }
    }
}

// MARK: - CryptoAvatarView

struct CryptoAvatarView: View {
    let baseAsset: String
    var body: some View {
        Circle()
            .fill(Color.PrimaryYellow.opacity(0.15))
            .frame(width: 36, height: 36)
            .overlay(
                Text(String(baseAsset.prefix(1)))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color.PrimaryYellow)
            )
    }
}
