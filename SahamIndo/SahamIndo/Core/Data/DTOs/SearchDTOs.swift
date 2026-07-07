//
//  SearchDTOs.swift
//  SahamIndo
//
//  DTOs untuk endpoint /api/saham/search dan /api/saham/{kode}/analyze
//  yang ditambahkan di refactor backend multi-market.
//

import Foundation

// MARK: - SimbolReferensiDTO
// Response dari GET /api/saham/search?q=...
// Backend: tabel simbol_referensi (universe 4000+ simbol NASDAQ/ETF/IDX)

struct SimbolReferensiDTO: Decodable, Identifiable {
    let kode:         String
    let nama:         String
    let market:       String    // "IDX" | "NASDAQ" | "NYSE" | "ETF"
    let tipe:         String    // "STOCK" | "ETF"
    let exchange:     String?
    let is_watchlist: Bool

    var id: String { kode }
}

// MARK: - AnalyzeResultDTO
// Response dari POST /api/saham/{kode}/analyze
// Backend: pipeline on-demand (scrape fundamental + AI scoring 1 saham)

struct AnalyzeResultDTO: Decodable {
    let kode:         String
    let market:       String
    let is_watchlist: Bool
    let hasil:        AnalyzeHasilDTO?
}

struct AnalyzeHasilDTO: Decodable {
    let kode_saham:         String
    let tanggal_scoring:    String?
    let skor_total:         Double?
    let rekomendasi:        String?
    let alasan:             String?
    let skor_fundamental:   Double?
    let skor_sentimen:      Double?
    let skor_teknikal:      Double?
    let skor_risiko:        Double?
}

// MARK: - WatchlistStatusDTO
// Response dari POST/DELETE /api/saham/{kode}/watchlist

struct WatchlistStatusDTO: Decodable {
    let kode:         String
    let is_watchlist: Bool
    let market:       String?
}

// MARK: - StockSummaryDTO (extend with market field)
// Tambah `market` ke DTO yang sudah ada — field opsional (default IDX)
// supaya /stocks yang sudah jalan tidak break saat field ini belum ada.

extension StockSummaryDTO {
    enum MarketCodingKeys: String, CodingKey { case market }
}
