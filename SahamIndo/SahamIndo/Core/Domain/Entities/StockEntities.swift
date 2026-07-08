//
//  StockEntities.swift
//  StockAppTryNew
//
//  Created by Surya on 16/06/26.
//

import Foundation
// Domain layer — pure Swift, zero framework imports.
// These are the canonical models the rest of the app depends on.

// MARK: - Stock

struct Stock: Identifiable, Hashable {
    let id: String
    let symbol: String
    let name: String?
    let price: Double
    let change: Double
    let percentChange: Double
    /// "IDX" | "NASDAQ" | "NYSE" | "ETF" — dipakai untuk format harga yang benar
    /// (IDX tanpa desimal, non-IDX 2 desimal). Default "IDX" untuk backward-compat.
    let market: String
}

// MARK: - StockDetail

struct StockDetail: Identifiable {
    let id: String
    let symbol: String
    let name: String?
    let sector: String?
    let sentiment: SentimentType
    let sentimentScore: Double
    let aiSummary: String
    let price: Double
    let change: Double
    let percentChange: Double
    let updatedAt: Date?
    /// "IDX" | "NASDAQ" | "NYSE" | "ETF" — lihat catatan di Stock.market.
    let market: String
}

// MARK: - SentimentType

enum SentimentType: String, Hashable {
    case recommended = "Recommended"
    case neutral     = "Neutral"
    case caution     = "Caution"

    static func from(rawValue: String) -> SentimentType {
        switch rawValue.uppercased() {
        case "RECOMMENDED", "BUY":              return .recommended
        case "NEGATIVE", "CAUTION", "SELL":     return .caution
        default:                                return .neutral
        }
    }

    var sfSymbol: String {
        switch self {
            case .recommended: return "checkmark.circle.fill"
            case .neutral:     return "exclamationmark.triangle.fill"
            case .caution:     return "xmark.circle.fill"
        }
    }
}

// MARK: - Sentiment (analytics breakdown)

struct Sentiment: Hashable {
    let buy: Double
    let hold: Double
    let sell: Double
    let score: Double

    var label: String {
        if score >= 70.0 { return "Recommended" }
        if score <= 40.0 { return "Caution" }
        return "Neutral"
    }

    var type: SentimentType { SentimentType.from(rawValue: label) }

    static func from(type: SentimentType, score: Double) -> Sentiment {
        switch type {
        case .recommended: return Sentiment(buy: 0.65, hold: 0.25, sell: 0.10, score: score)
        case .caution:     return Sentiment(buy: 0.15, hold: 0.25, sell: 0.60, score: score)
        case .neutral:     return Sentiment(buy: 0.35, hold: 0.40, sell: 0.25, score: score)
        }
    }

    /// Fallback when only percentChange is known
    static func estimated(percentChange: Double) -> Sentiment {
        if percentChange > 1 {
            return Sentiment(
                buy: .random(in: 0.55...0.75),
                hold: .random(in: 0.15...0.25),
                sell: .random(in: 0.05...0.15),
                score: .random(in: 75.0...95.0)
            )
        } else if percentChange < -1 {
            return Sentiment(
                buy: .random(in: 0.10...0.25),
                hold: .random(in: 0.20...0.30),
                sell: .random(in: 0.45...0.65),
                score: .random(in: 15.0...40.0)
            )
        }
        return Sentiment(
            buy: .random(in: 0.30...0.50),
            hold: .random(in: 0.30...0.40),
            sell: .random(in: 0.15...0.30),
            score: .random(in: 45.0...70.0)
        )
    }
}

// MARK: - StockDataPoint (chart candle)

struct StockDataPoint: Identifiable, Equatable {
    let id = UUID()
    let date: Date
    let close: Double
    let open: Double
    let high: Double
    let low: Double
    let volume: Double
}

// MARK: - TimeRange

enum TimeRange: String, CaseIterable, Identifiable {
    case oneDay     = "1D"
    case oneWeek    = "1W"
    case oneMonth   = "1M"
    case threeMonth = "3M"
    case ytd        = "YTD"
    case oneYear    = "1Y"
    case fiveYear   = "5Y"
    case all        = "All"

    var id: String { rawValue }

    var isIntraday: Bool { self == .oneDay || self == .oneWeek }

    var xSpacingExponent: CGFloat {
        switch self {
        case .oneDay:     return 1.0
        case .oneWeek:    return 1.0
        case .oneMonth:   return 0.88
        case .threeMonth: return 0.78
        case .ytd:        return 0.72
        case .oneYear:    return 0.65
        case .fiveYear:   return 0.55
        case .all:        return 0.50
        }
    }
}

// MARK: - AIInsight

struct AIInsight {
    let label: String
    let text: String
    let updatedAt: Date?
}

// MARK: - MacroIndicator

struct MacroIndicator {
    let key: String
    let value: Double
    let unit: String
    let date: String
    let source: String?
}

// MARK: - EarningsInfo (jadwal rilis laporan keuangan per emiten)

struct EarningsInfo {
    let symbol:            String
    let nextEarningsDate:  Date?
    let epsEstimate:       Double?
    let epsEstimateLow:    Double?
    let epsEstimateHigh:   Double?
    let revenueEstimate:   Double?
    let isEstimate:        Bool

    /// Jumlah hari kalender sampai tanggal earnings berikutnya (nil kalau tidak diketahui).
    var daysUntil: Int? {
        guard let date = nextEarningsDate else { return nil }
        let cal = Calendar(identifier: .gregorian)
        let start = cal.startOfDay(for: Date())
        let end   = cal.startOfDay(for: date)
        return cal.dateComponents([.day], from: start, to: end).day
    }
}

// MARK: - RallyStreakInfo (harga hijau berturut-turut)

struct RallyStreakInfo {
    let symbol:      String
    let streakDays:  Int
    let isRallying:  Bool
}
