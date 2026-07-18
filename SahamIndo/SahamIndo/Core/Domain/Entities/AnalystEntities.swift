//
//  AnalystEntities.swift
//  SahamIndo
//
//  Domain model untuk data perkiraan analis (dari yfinance): konsensus price
//  target, distribusi rekomendasi, dan riwayat rating action per firma.
//  Ditampilkan di StockDetailView. Semua bersifat PERKIRAAN.
//

import Foundation

// MARK: - AnalystRatings

struct AnalystRatings {
    let symbol: String
    let consensus: AnalystConsensus?
    let distribution: RatingDistribution?
    let history: [AnalystRatingRow]

    var isEmpty: Bool {
        consensus == nil && distribution == nil && history.isEmpty
    }
}

// MARK: - Consensus Price Target

struct AnalystConsensus {
    let current: Double?   // harga acuan saat data diambil
    let low:     Double?
    let high:    Double?
    let mean:    Double?
    let median:  Double?

    /// Potensi kenaikan (%) target rata-rata dibanding harga acuan.
    var meanUpsidePercent: Double? {
        guard let mean, let current, current > 0 else { return nil }
        return (mean - current) / current * 100
    }
}

// MARK: - Recommendation Distribution

struct RatingDistribution {
    let strongBuy:  Int
    let buy:        Int
    let hold:       Int
    let sell:       Int
    let strongSell: Int

    var total: Int { strongBuy + buy + hold + sell + strongSell }

    /// Total sisi beli & jual (buy + strongBuy, sell + strongSell).
    var buyTotal:  Int { strongBuy + buy }
    var sellTotal: Int { sell + strongSell }
}

// MARK: - Rating History Row

struct AnalystRatingRow: Identifiable {
    let id = UUID()
    let date:              Date?
    let firm:             String
    let toGrade:          String
    let fromGrade:        String
    let action:           String   // "up" | "down" | "main" | "init" | "reit"
    let priceTargetAction: String  // "Raises" | "Lowers" | "Maintains" | ""
    let currentPT:        Double?
    let priorPT:          Double?

    /// Apakah price target naik/turun/tetap — dari priceTargetAction atau
    /// perbandingan current vs prior.
    enum PTDirection { case up, down, flat, unknown }

    var ptDirection: PTDirection {
        switch priceTargetAction.lowercased() {
        case "raises":    return .up
        case "lowers":    return .down
        case "maintains": return .flat
        default:
            guard let c = currentPT, let p = priorPT else { return .unknown }
            if c > p { return .up }
            if c < p { return .down }
            return .flat
        }
    }
}
