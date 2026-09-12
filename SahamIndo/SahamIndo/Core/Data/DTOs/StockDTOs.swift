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
    let market:     String?   // optional: endpoint lama yang belum kirim field ini tetap aman
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
    let sector:                String?
    let sentiment:            String
    let emitent_ai_summarize: String
    let price:                Double
    let change:               Double
    let pct_change:           Double
    let score:                Double?
    let updatedAt:            Date?
    let market:               String?   // optional: sama alasannya dengan StockSummaryDTO

    enum CodingKeys: String, CodingKey {
        case symbol               = "kode_saham"
        case name                 = "nama_perusahaan"
        case sector               = "sektor"
        case sentiment            = "rekomendasi"
        case emitent_ai_summarize = "alasan"
        case price, change, pct_change, market
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

struct AnalystRatingsDTO: Decodable {
    let kode_saham:   String
    let consensus:    ConsensusDTO?
    let distribution: DistributionDTO?
    let history:      [RowDTO]
    let sumber:       String?

    struct ConsensusDTO: Decodable {
        let current: Double?
        let low:     Double?
        let high:    Double?
        let mean:    Double?
        let median:  Double?
    }

    struct DistributionDTO: Decodable {
        let strong_buy:  Int
        let buy:         Int
        let hold:        Int
        let sell:        Int
        let strong_sell: Int
    }

    struct RowDTO: Decodable {
        let date:                String?
        let firm:                String
        let to_grade:            String
        let from_grade:          String
        let action:              String
        let price_target_action: String
        let current_pt:          Double?
        let prior_pt:            Double?
    }
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

struct FundamentalDTO: Decodable {
    let kode_saham:          String
    // Valuasi
    let trailing_pe:         Double?
    let forward_pe:          Double?
    let pbv:                 Double?
    let dividend_yield:      Double?
    let market_cap:          Double?
    // Profitabilitas
    let roe:                 Double?
    let profit_margin:       Double?
    let gross_margin:        Double?
    let operating_margin:    Double?
    // Kesehatan keuangan
    let der:                 Double?
    let free_cash_flow:      Double?
    let operating_cash_flow: Double?
    let total_cash:          Double?
    let total_debt:          Double?
    // Pertumbuhan terkini
    let revenue_growth:      Double?
    let earnings_growth:     Double?
    // Pertumbuhan deret tahunan + CAGR revenue
    let annual_growth:       [GrowthRowDTO]?
    let revenue_cagr:        Double?
    // Meta
    let sector:              String?
    let industry:            String?
    let currency:            String?

    struct GrowthRowDTO: Decodable {
        let year:       Int
        let revenue:    Double?
        let net_income: Double?
    }
}

struct MoatDTO: Decodable {
    let kode_saham: String
    let moat_text:  String?
    let sumber:     String?
}

struct DividendEventsDTO: Decodable {
    let kode_saham:            String
    let ex_dividend_date:      String?   // "yyyy-MM-dd" — di-parse di mapper (bukan Date)
    let dividend_payment_date: String?
    let dividend_amount:       Double?   // nominal per lembar (cash dividend terakhir)
    let dividend_rate:         Double?   // dividen tahunan per lembar
    let dividend_yield:        Double?   // SUDAH dalam persen (mis. 5.5 = 5,5%)
    let currency:              String?
}

struct AIMarketInsightDTO: Decodable {
    let text:      String
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case text
        case updatedAt = "updated_at"
    }
}
