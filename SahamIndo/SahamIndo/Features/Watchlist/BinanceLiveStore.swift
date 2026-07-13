//
//  BinanceLiveStore.swift
//  SahamIndo
//
//  Koneksi LANGSUNG dari app ke WebSocket publik Binance (tidak lewat
//  backend kita sama sekali) — sesuai keputusan arsitektur: crypto trading
//  24/7 jadi tidak ada kerumitan jam bursa/extended-hours seperti saham, dan
//  Binance menyediakan data real-time gratis tanpa API key untuk data pasar.
//
//  Pakai "combined stream" Binance supaya BANYAK simbol bisa di-subscribe
//  dalam SATU koneksi WebSocket (bukan 1 koneksi per koin):
//  wss://stream.binance.com:9443/stream?streams=btcusdt@ticker/ethusdt@ticker
//
//  Search pakai REST exchangeInfo (di-cache in-memory selama app berjalan,
//  data ini jarang berubah).
//

import Foundation
import Combine

private struct BinanceCombinedMessage: Decodable {
    let stream: String
    let data:   CryptoTicker
}

private struct BinanceExchangeInfo: Decodable {
    let symbols: [BinanceSymbolInfo]
}

private struct BinanceSymbolInfo: Decodable {
    let symbol:     String
    let baseAsset:  String
    let quoteAsset: String
    let status:     String
}

@MainActor
final class BinanceLiveStore: ObservableObject {

    static let shared = BinanceLiveStore()
    private init() {}

    // MARK: - Realtime ticker state

    @Published private(set) var tickers:     [String: CryptoTicker] = [:]
    @Published private(set) var isConnected: Bool = false

    private var task:            URLSessionWebSocketTask?
    private var currentSymbols:  Set<String> = []
    private var shouldReconnect: Bool = false

    func ticker(for symbol: String) -> CryptoTicker? {
        tickers[symbol.uppercased()]
    }

    /// Reconnect (kalau perlu) dengan daftar simbol watchlist terbaru.
    /// No-op kalau daftar simbolnya sama persis dengan yang sudah aktif —
    /// aman dipanggil berkali-kali dari `.onAppear`/`.onChange`.
    func updateSubscriptions(_ symbols: [String]) {
        let newSet = Set(symbols.map { $0.uppercased() })
        guard newSet != currentSymbols else { return }
        currentSymbols = newSet

        guard !newSet.isEmpty else {
            disconnect()
            return
        }
        connect(symbols: Array(newSet))
    }

    private func connect(symbols: [String]) {
        task?.cancel(with: .goingAway, reason: nil)
        shouldReconnect = true

        let streams = symbols.map { "\($0.lowercased())@ticker" }.joined(separator: "/")
        guard let url = URL(string: "wss://stream.binance.com:9443/stream?streams=\(streams)") else { return }

        let newTask = URLSession.shared.webSocketTask(with: url)
        task = newTask
        newTask.resume()
        isConnected = true
        listen()
    }

    func disconnect() {
        shouldReconnect = false
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        isConnected = false
        currentSymbols = []
    }

    private func listen() {
        task?.receive { [weak self] result in
            guard let self else { return }
            Task { @MainActor in
                switch result {
                case .success(let message):
                    if case .string(let text) = message,
                       let data = text.data(using: .utf8),
                       let combined = try? JSONDecoder().decode(BinanceCombinedMessage.self, from: data) {
                        self.tickers[combined.data.symbol] = combined.data
                    }
                    self.listen()
                case .failure:
                    self.isConnected = false
                    if self.shouldReconnect {
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        if self.shouldReconnect, !self.currentSymbols.isEmpty {
                            self.connect(symbols: Array(self.currentSymbols))
                        }
                    }
                }
            }
        }
    }

    // MARK: - Search (REST exchangeInfo, cached in-memory)

    private var cachedAssets: [CryptoAsset]?

    /// Cari pasangan trading berdasarkan ticker (mis. "BTC") atau nama
    /// (mis. "bitcoin"). Dibatasi ke pair *-USDT saja supaya hasil relevan
    /// buat kebanyakan user (paling umum dipakai).
    func searchAssets(query: String) async -> [CryptoAsset] {
        let all = await allAssets()
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !q.isEmpty else { return [] }
        return Array(
            all.filter {
                $0.baseAsset.contains(q) || $0.displayName.uppercased().contains(q) || $0.symbol.contains(q)
            }
            .sorted { $0.baseAsset < $1.baseAsset }
            .prefix(30)
        )
    }

    /// Nama tampilan untuk simbol yang sudah ada di watchlist (sinkron, tidak
    /// perlu network) — dipakai row watchlist yang belum tentu hasil search.
    func displayName(forSymbol symbol: String) -> String {
        let base = symbol.uppercased().hasSuffix("USDT") ? String(symbol.dropLast(4)) : symbol
        return Self.popularNames[base] ?? base
    }

    private func allAssets() async -> [CryptoAsset] {
        if let cached = cachedAssets { return cached }
        guard let url = URL(string: "https://api.binance.com/api/v3/exchangeInfo") else { return [] }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode(BinanceExchangeInfo.self, from: data)
            let assets = decoded.symbols
                .filter { $0.quoteAsset == "USDT" && $0.status == "TRADING" }
                .map { sym in
                    CryptoAsset(
                        symbol:      sym.symbol,
                        baseAsset:   sym.baseAsset,
                        quoteAsset:  sym.quoteAsset,
                        displayName: Self.popularNames[sym.baseAsset] ?? sym.baseAsset
                    )
                }
            cachedAssets = assets
            return assets
        } catch {
            return []
        }
    }

    /// Kamus nama populer supaya hasil pencarian lebih ramah ("Bitcoin"
    /// alih-alih cuma "BTC"). Daftar tidak lengkap dengan sengaja — cukup
    /// cover coin-coin besar; yang lain tetap bisa dicari & ditambah, cuma
    /// nama tampilannya fallback ke ticker mentahnya.
    private static let popularNames: [String: String] = [
        "BTC": "Bitcoin", "ETH": "Ethereum", "SOL": "Solana", "BNB": "BNB",
        "XRP": "XRP", "ADA": "Cardano", "DOGE": "Dogecoin", "AVAX": "Avalanche",
        "DOT": "Polkadot", "MATIC": "Polygon", "LINK": "Chainlink", "LTC": "Litecoin",
        "SHIB": "Shiba Inu", "TRX": "TRON", "UNI": "Uniswap", "ATOM": "Cosmos",
        "XLM": "Stellar", "NEAR": "NEAR Protocol", "APT": "Aptos", "ARB": "Arbitrum",
        "OP": "Optimism", "FIL": "Filecoin", "ICP": "Internet Computer", "SUI": "Sui",
        "PEPE": "Pepe", "TON": "Toncoin", "BCH": "Bitcoin Cash", "ETC": "Ethereum Classic",
    ]
}
