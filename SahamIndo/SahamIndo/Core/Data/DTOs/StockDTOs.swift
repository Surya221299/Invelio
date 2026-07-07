//
//  StockDTOs.swift
//  StockAppTryNew
//
//  Created by Surya on 16/06/26.
//

import Foundation
// Data Transfer Objects — only for API decoding. Never used beyond Data layer.

struct StockSummaryDTO: Decodable {
    let symbol:     String
    let name:       String?
    let price:      Double
    let change:     Double
    let pct_change: Double
}

struct CandleDTO: Decodable {
    let ts:     Date
    let open:   Double?
    let high:   Double?
    let low:    Double?
    let close:  Double
    let volume: Int
}

struct StockDetailDTO: Decodable {
    let symbol:               String
    let name:                 String?
    let sector:               String?
    let sentiment:            String
    let emitent_ai_summarize: String
    let price:                Double
    let change:               Double
    let pct_change:           Double
    let score:                Double?
    let updatedAt:            Date?

    enum CodingKeys: String, CodingKey {
        case symbol               = "kode_saham"
        case name                 = "nama_perusahaan"
        case sector               = "sektor"
        case sentiment            = "rekomendasi"
        case emitent_ai_summarize = "alasan"
        case price, change, pct_change
        case score                = "skor_total"
        case updatedAt            = "updated_at"
    }
}

struct AlertDTO: Decodable {
    let id:          Int
    let kode_saham:  String
    let pesan:       String
    let delta:       Double
    let tanggal:     String
    let jenis:       String?   // "sentimen" | "earnings" | "rally_streak" (optional utk backward-compat)
}

struct EarningsInfoDTO: Decodable {
    let kode_saham:          String
    let next_earnings_date:  String?
    let eps_estimate:        Double?
    let eps_estimate_low:    Double?
    let eps_estimate_high:   Double?
    let revenue_estimate:    Double?
    let is_estimate:         Bool
    let sumber:              String?
}

struct RallyStreakDTO: Decodable {
    let kode_saham:      String
    let streak_hari:     Int
    let is_rally_streak: Bool
}

struct MakroIndicatorDTO: Decodable {
    let nilai:    Double
    let satuan:   String
    let tanggal:  String
    let sumber:   String?
}

struct MakroResponseDTO: Decodable {
    let tanggal_fetch: String
    let indikator:     [String: MakroIndicatorDTO]
}

struct RekomendasiItemDTO: Decodable {
    let rank:              Int
    let kode_saham:        String
    let nama_perusahaan:   String?
    let sektor:            String?
    let rekomendasi:       String
    let alasan:            String?
}

struct RekomendasiResponseDTO: Decodable {
    let tanggal:     String?
    let rekomendasi: [RekomendasiItemDTO]
}

struct AIMarketInsightDTO: Decodable {
    let text:      String
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case text
        case updatedAt = "updated_at"
    }
}
