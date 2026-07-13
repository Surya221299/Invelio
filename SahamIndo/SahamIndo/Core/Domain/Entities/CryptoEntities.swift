//
//  CryptoEntities.swift
//  SahamIndo
//
//  Model data untuk fitur crypto — terpisah dari model saham (Stock/
//  PortfolioItem) karena sumber datanya beda total (Binance langsung,
//  bukan lewat backend kita) dan semantiknya juga beda (tidak ada sentiment,
//  quantity holding, dsb — murni watchlist harga).
//

import Foundation

/// Satu pasangan trading di Binance (mis. "BTCUSDT"). Dipakai untuk hasil
/// pencarian maupun item watchlist crypto user.
struct CryptoAsset: Identifiable, Hashable {
    let symbol:      String   // "BTCUSDT" — dipakai sebagai stream/subscription key
    let baseAsset:   String   // "BTC"
    let quoteAsset:  String   // "USDT"
    let displayName: String   // "Bitcoin" (dari kamus lokal) atau fallback ke baseAsset

    var id: String { symbol }
}

/// Update harga real-time dari Binance combined WebSocket stream
/// (`<symbol>@ticker` — 24hr rolling ticker statistics).
///
/// CATATAN: Binance mengirim angka numerik sebagai STRING di JSON-nya
/// (mis. `"c": "43521.50"`, bukan `"c": 43521.50`), jadi perlu decode manual
/// alih-alih Decodable otomatis.
struct CryptoTicker {
    let symbol:             String
    let lastPrice:           Double
    let priceChange:         Double
    let priceChangePercent:  Double
}

extension CryptoTicker: Decodable {
    private enum CodingKeys: String, CodingKey {
        case symbol            = "s"
        case lastPrice          = "c"
        case priceChange        = "p"
        case priceChangePercent = "P"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        symbol = try c.decode(String.self, forKey: .symbol)
        let lastPriceStr  = try c.decode(String.self, forKey: .lastPrice)
        let changeStr     = try c.decode(String.self, forKey: .priceChange)
        let changePctStr  = try c.decode(String.self, forKey: .priceChangePercent)
        lastPrice          = Double(lastPriceStr) ?? 0
        priceChange        = Double(changeStr) ?? 0
        priceChangePercent = Double(changePctStr) ?? 0
    }
}
