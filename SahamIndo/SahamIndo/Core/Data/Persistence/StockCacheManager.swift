//
//  StockCacheManager.swift
//  StockAppTryNew
//
//  Created by Surya on 16/06/26.
//

import Foundation
// Core/Data/Persistence/StockCacheManager.swift
// Liskov: can swap UserDefaults for any key-value store without changing callers.

// MARK: - StockCacheManager

final class StockCacheManager {

    static let shared = StockCacheManager()
    private init() {}

    private let defaults            = UserDefaults.standard
    private let freshnessInterval:  TimeInterval = 5 * 60

    // MARK: - Keys

    private enum Key {
        static let allStocks          = "cache_all_stocks_v1"
        static let allStocksTimestamp = "cache_all_stocks_ts_v1"

        static func candles(symbol: String, range: String) -> String {
            "cache_candles_\(symbol)_\(range)_v1"
        }
        static func candlesTimestamp(symbol: String, range: String) -> String {
            "cache_candles_\(symbol)_\(range)_ts_v1"
        }
    }

    // MARK: - Codable wrappers (private to this file)

    private struct StockCache: Codable {
        let symbol: String; let name: String?
        let price: Double; let change: Double; let pctChange: Double
        /// "IDX" | "NASDAQ" | "NYSE" | "ETF". Optional decode supaya cache LAMA
        /// (yang disimpan sebelum field ini ada) tidak gagal decode — cuma
        /// fallback ke "IDX" kalau tidak ada di data yang tersimpan.
        let market: String?
    }

    private struct CandleCache: Codable {
        let ts: Date; let open: Double; let high: Double
        let low: Double; let close: Double; let volume: Double
    }

    // MARK: - All Stocks

    func save(stocks: [Stock]) {
        let list = stocks.map { StockCache(symbol: $0.symbol, name: $0.name,
                                           price: $0.price, change: $0.change, pctChange: $0.percentChange,
                                           market: $0.market) }
        guard let data = try? JSONEncoder().encode(list) else { return }
        defaults.set(data, forKey: Key.allStocks)
        defaults.set(Date().timeIntervalSince1970, forKey: Key.allStocksTimestamp)
    }

    func loadStocks() -> (stocks: [Stock], isStale: Bool)? {
        guard let data = defaults.data(forKey: Key.allStocks),
              let list = try? JSONDecoder().decode([StockCache].self, from: data) else { return nil }

        let age   = Date().timeIntervalSince1970 - defaults.double(forKey: Key.allStocksTimestamp)
        let result = list.map { Stock(id: $0.symbol, symbol: $0.symbol, name: $0.name,
                                      price: $0.price, change: $0.change, percentChange: $0.pctChange,
                                      market: $0.market ?? "IDX") }
        return (result, age > freshnessInterval)
    }

    // MARK: - Candles

    func save(candles: [StockDataPoint], symbol: String, range: TimeRange) {
        let list = candles.map { CandleCache(ts: $0.date, open: $0.open, high: $0.high,
                                              low: $0.low, close: $0.close, volume: $0.volume) }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(list) else { return }
        defaults.set(data, forKey: Key.candles(symbol: symbol, range: range.rawValue))
        defaults.set(Date().timeIntervalSince1970, forKey: Key.candlesTimestamp(symbol: symbol, range: range.rawValue))
    }

    func loadCandles(symbol: String, range: TimeRange) -> (candles: [StockDataPoint], isStale: Bool)? {
        let key = Key.candles(symbol: symbol, range: range.rawValue)
        guard let data = defaults.data(forKey: key) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let list = try? decoder.decode([CandleCache].self, from: data) else { return nil }
        let age    = Date().timeIntervalSince1970 - defaults.double(forKey: Key.candlesTimestamp(symbol: symbol, range: range.rawValue))
        let result = list.map { StockDataPoint(date: $0.ts, close: $0.close, open: $0.open,
                                                high: $0.high, low: $0.low, volume: $0.volume) }
        return (result, age > freshnessInterval)
    }

    // MARK: - Age String

    func cacheAgeString(symbol: String? = nil, range: TimeRange? = nil) -> String? {
        let ts: Double
        if let sym = symbol, let rng = range {
            ts = defaults.double(forKey: Key.candlesTimestamp(symbol: sym, range: rng.rawValue))
        } else {
            ts = defaults.double(forKey: Key.allStocksTimestamp)
        }
        guard ts > 0 else { return nil }
        let age = Int(Date().timeIntervalSince1970 - ts)
        if age < 60    { return "\(age) detik lalu" }
        if age < 3600  { return "\(age / 60) menit lalu" }
        if age < 86400 { return "\(age / 3600) jam lalu" }
        return "\(age / 86400) hari lalu"
    }

    // MARK: - Clear

    func clearAll() {
        defaults.dictionaryRepresentation().keys
            .filter { $0.hasPrefix("cache_") }
            .forEach { defaults.removeObject(forKey: $0) }
    }
}
