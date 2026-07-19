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

// MARK: - CompanyFundamentals (ringkasan fundamental emiten)

/// Penilaian kualitatif satu metrik fundamental. Warna dipetakan di View
/// (domain layer tetap bebas framework).
enum FundamentalVerdict {
    case good      // sehat / murah / kuat
    case fair      // wajar / cukup
    case weak      // mahal / lemah / berisiko
    case unknown   // data tidak tersedia

    var label: String {
        switch self {
        case .good:    return "Bagus"
        case .fair:    return "Cukup"
        case .weak:    return "Lemah"
        case .unknown: return "-"
        }
    }
}

/// Satu titik pertumbuhan tahunan (revenue & laba bersih) untuk satu tahun buku.
struct GrowthPoint: Identifiable {
    var id: Int { year }
    let year:      Int
    let revenue:   Double?
    let netIncome: Double?
}

/// Ringkasan fundamental emiten dari yfinance. Semua rasio dalam bentuk desimal
/// mentah persis yfinance (mis. roe 0.18 = 18%, der 1.2 = 1.2x). Field yang
/// tidak tersedia = nil (umum untuk emiten IDX di yfinance).
struct CompanyFundamentals {
    let symbol: String
    // Valuasi
    let trailingPE:    Double?
    let forwardPE:     Double?
    let pbv:           Double?
    let dividendYield: Double?
    let marketCap:     Double?
    // Profitabilitas
    let roe:             Double?
    let profitMargin:    Double?
    let grossMargin:     Double?
    let operatingMargin: Double?
    // Kesehatan keuangan
    let der:               Double?
    let freeCashFlow:      Double?
    let operatingCashFlow: Double?
    let totalCash:         Double?
    let totalDebt:         Double?
    // Pertumbuhan terkini
    let revenueGrowth:  Double?
    let earningsGrowth: Double?
    // Pertumbuhan deret tahunan + CAGR revenue
    let annualGrowth: [GrowthPoint]
    let revenueCAGR:  Double?
    // Meta
    let sector:   String?
    let industry: String?
    let currency: String?

    /// Semua bagian kosong → kartu disembunyikan.
    var isEmpty: Bool {
        trailingPE == nil && forwardPE == nil && pbv == nil && roe == nil &&
        profitMargin == nil && der == nil && freeCashFlow == nil &&
        revenueGrowth == nil && annualGrowth.isEmpty
    }

    var hasValuation:     Bool { trailingPE != nil || forwardPE != nil || pbv != nil }
    var hasProfitability: Bool { roe != nil || profitMargin != nil || grossMargin != nil }
    var hasHealth:        Bool { der != nil || freeCashFlow != nil }
    var hasGrowth:        Bool { revenueGrowth != nil || earningsGrowth != nil || annualGrowth.count >= 2 }

    // MARK: - Verdicts (interpretasi ambang)

    /// Valuasi dari PER: <=15 murah, <=25 wajar, >25 mahal. PER <=0 (rugi) → unknown.
    var valuationVerdict: FundamentalVerdict {
        guard let pe = trailingPE ?? forwardPE, pe > 0 else { return .unknown }
        if pe <= 15 { return .good }
        if pe <= 25 { return .fair }
        return .weak
    }

    var valuationLabel: String {
        switch valuationVerdict {
        case .good:    return "Relatif murah"
        case .fair:    return "Wajar"
        case .weak:    return "Relatif mahal"
        case .unknown: return "-"
        }
    }

    /// ROE: >=15% bagus, >=10% cukup, sisanya lemah (patokan umum kualitas).
    var roeVerdict: FundamentalVerdict {
        guard let r = roe else { return .unknown }
        if r >= 0.15 { return .good }
        if r >= 0.10 { return .fair }
        return .weak
    }

    /// Net margin: ambang umum lintas industri (konteks industri diberi di teks).
    var netMarginVerdict: FundamentalVerdict {
        guard let m = profitMargin else { return .unknown }
        if m >= 0.15 { return .good }
        if m >= 0.05 { return .fair }
        if m <= 0    { return .weak }
        return .fair
    }

    /// Kesehatan keuangan gabungan DER + FCF (aturan: utang besar + FCF positif
    /// masih oke; utang besar + FCF negatif = berbahaya).
    var financialHealthVerdict: FundamentalVerdict {
        guard der != nil || freeCashFlow != nil else { return .unknown }
        let fcf = freeCashFlow
        let d   = der
        if let fcf {
            if fcf >= 0 {
                if let d, d > 2 { return .fair }   // utang besar tapi arus kas positif
                return .good
            } else {
                if let d, d > 1 { return .weak }   // utang besar + arus kas negatif
                return .fair
            }
        }
        // Hanya DER yang diketahui.
        if let d { return d <= 1 ? .good : (d <= 2 ? .fair : .weak) }
        return .unknown
    }

    /// Pertumbuhan dari CAGR revenue (fallback ke revenueGrowth terkini).
    var growthVerdict: FundamentalVerdict {
        guard let g = revenueCAGR ?? revenueGrowth else { return .unknown }
        if g >= 0.15 { return .good }
        if g >= 0.05 { return .fair }
        if g <  0    { return .weak }
        return .fair
    }
}

// MARK: - MoatInsight (narasi kualitatif business moat via LLM)

struct MoatInsight {
    let symbol:   String
    let moatText: String?
    let source:   String?

    var hasText: Bool { !(moatText ?? "").isEmpty }
}

// MARK: - RallyStreakInfo (harga hijau berturut-turut)

struct RallyStreakInfo {
    let symbol:      String
    let streakDays:  Int
    let isRallying:  Bool
}
