//
//  LivePriceStore.swift
//  SahamIndo
//
//  SINGLE SOURCE OF TRUTH untuk harga live seluruh saham watchlist.
//
//  Sebelumnya ada 2 mekanisme terpisah: StockPriceStreamer (1 WebSocket per
//  simbol, dipakai StockDetailView) dan WatchlistPriceStreamer (1 WebSocket
//  untuk semua simbol, dipakai HomeView). Dua koneksi/state terpisah ini
//  gampang tidak sinkron satu sama lain (salah satunya kepasang bug, yang
//  lain tidak) — itu salah satu penyebab StockDetailView sempat tidak
//  ter-update walau HomeView sudah benar.
//
//  LivePriceStore menggantikan KEDUANYA: satu koneksi WebSocket ke
//  `/ws/stocks` (endpoint yang sama, broadcast harga SELURUH watchlist tiap
//  ~5 detik), satu singleton yang dipakai bersama oleh HomeViewModel maupun
//  StockDetailViewModel. Tidak ada lagi kemungkinan "yang satu update, yang
//  lain tidak" karena keduanya baca dari tempat yang sama persis.
//
//  Referensi-hitung (acquire/release) dipakai supaya koneksi tetap hidup
//  selama MINIMAL SATU layar masih butuh (Home ATAU StockDetail), dan baru
//  benar-benar disconnect kalau semuanya sudah .onDisappear.
//

import Foundation
import Combine

struct ExtendedHoursUpdate: Decodable {
    let marketState:          String?   // "PRE" | "POST" | "REGULAR" | "CLOSED" | dll (dari Yahoo)
    let preMarketPrice:       Double?
    let preMarketChange:      Double?
    let preMarketChangePercent:  Double?
    let postMarketPrice:      Double?
    let postMarketChange:     Double?
    let postMarketChangePercent: Double?
    /// Kapan Yahoo sebenarnya mencatat harga ini (ISO string dari backend).
    /// Dipakai untuk verifikasi kalau harga yang tampil bukan data basi dari
    /// sesi sebelumnya — lihat ExtendedHoursBadgeView untuk tampilannya.
    let preMarketTime:        String?
    let postMarketTime:       String?

    enum CodingKeys: String, CodingKey {
        case marketState             = "market_state"
        case preMarketPrice          = "pre_market_price"
        case preMarketChange         = "pre_market_change"
        case preMarketChangePercent  = "pre_market_change_percent"
        case postMarketPrice         = "post_market_price"
        case postMarketChange        = "post_market_change"
        case postMarketChangePercent = "post_market_change_percent"
        case preMarketTime           = "pre_market_time"
        case postMarketTime          = "post_market_time"
    }

    /// True kalau ada harga pre-market ATAU post-market yang benar-benar
    /// terisi (Yahoo cuma isi salah satu, tergantung sesi yang lagi jalan).
    var hasData: Bool { preMarketPrice != nil || postMarketPrice != nil }

    /// True kalau sesi yang aktif adalah pre-market (dipakai untuk pilih
    /// label & nilai mana yang ditampilkan di badge).
    var isPreMarket: Bool { preMarketPrice != nil }

    /// Label sesi yang ditampilkan di badge. Yahoo TIDAK punya field harga
    /// terpisah untuk sesi "Overnight" (Blue Ocean ATS, 20:00-04:00 ET) —
    /// mereka menandainya lewat `market_state = "POSTPOST"` sementara
    /// harganya tetap di field `postMarketPrice` yang sama dipakai untuk
    /// after-hours biasa ("POST", 16:00-20:00 ET). Jadi label di-derive dari
    /// `marketState`, bukan cuma dari field mana yang terisi.
    var sessionLabel: String {
        switch marketState?.uppercased() {
        case "PRE":      return "Pre-Market"
        case "POST":     return "After Hours"
        case "POSTPOST": return "Overnight"
        default:         return isPreMarket ? "Pre-Market" : "After Hours"
        }
    }

    var sessionIcon: String {
        switch marketState?.uppercased() {
        case "PRE":      return "sunrise.fill"
        case "POSTPOST": return "moon.zzz.fill"
        default:         return isPreMarket ? "sunrise.fill" : "moon.stars.fill"
        }
    }

    /// Kapan harga sesi ini sebenarnya dicatat Yahoo (bukan kapan backend kita
    /// fetch). Dipakai untuk menampilkan "· 3 menit lalu" di badge — supaya
    /// kalau ternyata datanya basi (mis. dari sesi kemarin), itu KELIHATAN
    /// jelas di UI, bukan diam-diam ditampilkan seolah-olah live.
    var sessionTimestamp: Date? {
        let raw = isPreMarket ? preMarketTime : postMarketTime
        guard let raw else { return nil }
        return StockMapper.parseFlexibleDate(raw)
    }
}

struct LivePriceUpdate: Decodable {
    let symbol:    String
    let price:     Double
    let change:    Double
    let pctChange: Double
    let extendedHours: ExtendedHoursUpdate?

    enum CodingKeys: String, CodingKey {
        case symbol, price, change
        case pctChange = "pct_change"
        case extendedHours = "extended_hours"
    }
}

private struct WatchlistUpdateMessage: Decodable {
    let type:    String
    let updates: [LivePriceUpdate]
    let ts:      Double
}

@MainActor
final class LivePriceStore: ObservableObject {

    static let shared = LivePriceStore()
    private init() {}

    /// Update terbaru per simbol — key = kode saham (mis. "BBCA", "MU").
    @Published private(set) var prices: [String: LivePriceUpdate] = [:]
    @Published private(set) var isConnected: Bool = false

    private var task: URLSessionWebSocketTask?
    private var shouldReconnect = false
    private var refCount = 0

    /// Ambil harga live untuk 1 simbol. `nil` kalau belum pernah ada update
    /// masuk untuk simbol ini (mis. baru saja connect, atau simbol itu lagi
    /// di-skip backend karena circuit breaker).
    func price(for symbol: String) -> LivePriceUpdate? {
        prices[symbol]
    }

    /// Panggil dari `.onAppear` tiap layar yang butuh harga live (Home,
    /// StockDetail). Aman dipanggil berkali-kali — pakai reference counting.
    func acquire() {
        refCount += 1
        guard task == nil else { return }
        shouldReconnect = true
        connect()
    }

    /// Panggil dari `.onDisappear`. Koneksi baru benar-benar ditutup kalau
    /// TIDAK ADA LAGI layar yang butuh (refCount balik ke 0) — supaya
    /// menutup StockDetailView tidak mematikan streaming yang masih dipakai
    /// HomeView di baliknya, atau sebaliknya.
    func release() {
        refCount = max(0, refCount - 1)
        guard refCount == 0 else { return }
        shouldReconnect = false
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        isConnected = false
    }

    private func connect() {
        Task {
            let base = await APIClient.resolveBaseURL()
            let wsBase = base
                .replacingOccurrences(of: "https://", with: "wss://")
                .replacingOccurrences(of: "http://", with: "ws://")

            guard let url = URL(string: "\(wsBase)/ws/stocks") else { return }

            let newTask = URLSession.shared.webSocketTask(with: url)
            self.task = newTask
            newTask.resume()
            self.isConnected = true
            self.listen()
        }
    }

    private func listen() {
        task?.receive { [weak self] result in
            guard let self else { return }
            Task { @MainActor in
                switch result {
                case .success(let message):
                    if case .string(let text) = message,
                       let data = text.data(using: .utf8),
                       let batch = try? JSONDecoder().decode(WatchlistUpdateMessage.self, from: data) {
                        for update in batch.updates where update.price > 0 {
                            // Jaga-jaga: abaikan harga 0/negatif (sentinel kegagalan
                            // fetch di backend) supaya tidak menimpa harga valid
                            // terakhir dengan 0.
                            self.prices[update.symbol] = update
                        }
                    }
                    self.listen()
                case .failure:
                    self.isConnected = false
                    if self.shouldReconnect {
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        if self.shouldReconnect, self.refCount > 0 { self.connect() }
                    }
                }
            }
        }
    }
}
