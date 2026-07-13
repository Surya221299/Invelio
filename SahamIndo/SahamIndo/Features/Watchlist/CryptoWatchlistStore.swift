//
//  CryptoWatchlistStore.swift
//  SahamIndo
//
//  Watchlist crypto user, persisted ke UserDefaults — mirip WatchlistStore
//  punya saham, tapi jauh lebih simpel (cuma daftar simbol, tidak ada
//  konsep tab/kategori seperti IDX/US karena semua crypto sama "jenisnya").
//

import Foundation
import Combine

@MainActor
final class CryptoWatchlistStore: ObservableObject {

    @Published private(set) var symbols: [String] = []

    private let key = "crypto_watchlist_v1"

    init() {
        // Default awal: top 10 crypto berdasarkan market cap (snapshot kurasi
        // manual per saat kode ini ditulis — stablecoin seperti USDT/USDC
        // sengaja dikecualikan karena harganya selalu ~$1, tidak menarik
        // dipantau). Rangking market cap crypto berubah-ubah, jadi ini
        // perkiraan wajar, bukan live ranking. User bebas ubah lewat search.
        symbols = UserDefaults.standard.stringArray(forKey: key) ?? [
            "BTCUSDT", "ETHUSDT", "BNBUSDT", "SOLUSDT", "XRPUSDT",
            "DOGEUSDT", "ADAUSDT", "TRXUSDT", "AVAXUSDT", "LINKUSDT",
        ]
    }

    func add(_ symbol: String) {
        let symbolUpper = symbol.uppercased()
        guard !symbols.contains(symbolUpper) else { return }
        symbols.append(symbolUpper)
        persist()
    }

    func remove(_ symbol: String) {
        symbols.removeAll { $0 == symbol.uppercased() }
        persist()
    }

    func contains(_ symbol: String) -> Bool {
        symbols.contains(symbol.uppercased())
    }

    private func persist() {
        UserDefaults.standard.set(symbols, forKey: key)
    }
}
