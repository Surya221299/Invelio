//
//  SearchEntities.swift
//  SahamIndo
//
//  Domain entities untuk fitur Search universe (NASDAQ/ETF/IDX)
//  dan hasil Analyze on-demand.
//

import Foundation

// MARK: - Market

/// Market tempat saham diperdagangkan.
/// Dipakai untuk label badge, suffix ticker yfinance, dan filter di backend.
enum Market: String, Hashable, CaseIterable {
    case idx    = "IDX"
    case nasdaq = "NASDAQ"
    case nyse   = "NYSE"
    case etf    = "ETF"

    var label: String { rawValue }

    /// Badge color identifier (dipakai di SearchResultRow.badgeColor)
    var colorName: String {
        switch self {
        case .idx:    return "BadgeIDX"
        case .nasdaq: return "BadgeNASDAQ"
        case .nyse:   return "BadgeNYSE"
        case .etf:    return "BadgeETF"
        }
    }

    static func from(_ raw: String) -> Market {
        Market(rawValue: raw.uppercased()) ?? .idx
    }
}

// MARK: - SymbolSearchResult

/// Satu baris hasil search dari universe simbol_referensi.
/// Dipakai di SearchViewModel dan SearchResultsView.
struct SymbolSearchResult: Identifiable, Hashable {
    let id:          String        // = kode
    let kode:        String
    let nama:        String
    let market:      Market
    let tipe:        String        // "STOCK" | "ETF"
    let exchange:    String?
    let isWatchlist: Bool          // sudah ada di watchlist aktif?
}

// MARK: - AnalyzeResult

/// Hasil analisis AI on-demand untuk 1 saham (POST /api/saham/{kode}/analyze).
/// Setelah berhasil dianalisis, viewmodel menampilkan ini di AnalyzeSheet.
struct AnalyzeResult: Identifiable {
    let id             = UUID()
    let kode:          String
    let market:        Market
    let isWatchlist:   Bool
    let skorTotal:     Double?
    let rekomendasi:   String?
    let alasan:        String?
    let skorFundamental: Double?
    let skorSentimen:  Double?
    let skorTeknikal:  Double?
    let skorRisiko:    Double?

    /// Label singkat rekomendasi (RECOMMENDED / NEUTRAL / CAUTION)
    var sentimentType: SentimentType {
        SentimentType.from(rawValue: rekomendasi ?? "")
    }

    /// Skor total dalam 0–100, netral 50 kalau kosong
    var skorDisplay: Double { skorTotal ?? 50.0 }
}
