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
            Spacer()
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
