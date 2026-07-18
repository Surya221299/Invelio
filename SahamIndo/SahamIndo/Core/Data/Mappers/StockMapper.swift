//
//  StockMapper.swift
//  StockAppTryNew
//
//  Core/Data/Mappers/StockMapper.swift
//  Tanggung jawab tunggal: mapping DTO → Domain Entity untuk semua Stock concern.
//  Tidak boleh import SwiftUI. Tidak boleh menyentuh network atau persistence.
//

import Foundation

enum StockMapper {

    // MARK: - StockSummaryDTO → Stock

    static func toStock(_ dto: StockSummaryDTO) -> Stock {
        Stock(
            id:            dto.symbol,
            symbol:        dto.symbol,
            name:          dto.name,
            price:         dto.price,
            change:        dto.change,
            percentChange: dto.pct_change,
            market:        dto.market ?? "IDX"
        )
    }

    static func toStocks(_ dtos: [StockSummaryDTO]) -> [Stock] {
        dtos.map { toStock($0) }
    }

    // MARK: - StockDetailDTO → StockDetail

    static func toStockDetail(_ dto: StockDetailDTO) -> StockDetail {
        let sentiment = SentimentType.from(rawValue: dto.sentiment)
        return StockDetail(
            id:             dto.symbol,
            symbol:         dto.symbol,
            name:           dto.name,
            sector:         dto.sector,
            sentiment:      sentiment,
            sentimentScore: dto.score ?? 50.0,
            aiSummary:      dto.emitent_ai_summarize,
            price:          dto.price,
            change:         dto.change,
            percentChange:  dto.pct_change,
            updatedAt:      dto.updatedAt,
            market:         dto.market ?? "IDX"
        )
    }

    // MARK: - CandleDTO → StockDataPoint

    static func toDataPoint(_ dto: CandleDTO) -> StockDataPoint {
        StockDataPoint(
            date:   dto.ts,
            close:  dto.close,
            open:   dto.open   ?? dto.close,
            high:   dto.high   ?? dto.close,
            low:    dto.low    ?? dto.close,
            volume: Double(dto.volume)
        )
    }

    static func toDataPoints(_ dtos: [CandleDTO]) -> [StockDataPoint] {
        dtos.map { toDataPoint($0) }
    }

    // MARK: - AlertDTO → RemoteAlert

    static func toRemoteAlert(_ dto: AlertDTO) -> RemoteAlert {
        RemoteAlert(
            id:      dto.id,
            symbol:  dto.kode_saham,
            message: dto.pesan,
            delta:   dto.delta,
            date:    dto.tanggal,
            jenis:   dto.jenis ?? "sentimen"
        )
    }

    static func toRemoteAlerts(_ dtos: [AlertDTO]) -> [RemoteAlert] {
        dtos.map { toRemoteAlert($0) }
    }

    // MARK: - Earnings & Rally Streak

    /// Parsing tanggal earnings secara fleksibel: yfinance bisa mengirim
    /// beberapa format string berbeda tergantung sumbernya (get_earnings_dates
    /// vs ticker.calendar), jadi dicoba beberapa formatter sebelum menyerah.
    static func parseFlexibleDate(_ str: String) -> Date? {
        let isoFrac = ISO8601DateFormatter()
        isoFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = isoFrac.date(from: str) { return d }

        let isoPlain = ISO8601DateFormatter()
        isoPlain.formatOptions = [.withInternetDateTime]
        if let d = isoPlain.date(from: str) { return d }

        let dateOnly = DateFormatter()
        dateOnly.locale = Locale(identifier: "en_US_POSIX")
        dateOnly.dateFormat = "yyyy-MM-dd"
        if let d = dateOnly.date(from: String(str.prefix(10))) { return d }

        return nil
    }

    static func toEarningsInfo(_ dto: EarningsInfoDTO) -> EarningsInfo {
        EarningsInfo(
            symbol:           dto.kode_saham,
            nextEarningsDate: dto.next_earnings_date.flatMap { parseFlexibleDate($0) },
            epsEstimate:      dto.eps_estimate,
            epsEstimateLow:   dto.eps_estimate_low,
            epsEstimateHigh:  dto.eps_estimate_high,
            revenueEstimate:  dto.revenue_estimate,
            isEstimate:       dto.is_estimate
        )
    }

    static func toRallyStreakInfo(_ dto: RallyStreakDTO) -> RallyStreakInfo {
        RallyStreakInfo(
            symbol:     dto.kode_saham,
            streakDays: dto.streak_hari,
            isRallying: dto.is_rally_streak
        )
    }

    static func toAnalystRatings(_ dto: AnalystRatingsDTO) -> AnalystRatings {
        AnalystRatings(
            symbol: dto.kode_saham,
            consensus: dto.consensus.map {
                AnalystConsensus(current: $0.current, low: $0.low, high: $0.high,
                                 mean: $0.mean, median: $0.median)
            },
            distribution: dto.distribution.map {
                RatingDistribution(strongBuy: $0.strong_buy, buy: $0.buy, hold: $0.hold,
                                   sell: $0.sell, strongSell: $0.strong_sell)
            },
            history: dto.history.map { row in
                AnalystRatingRow(
                    date:              row.date.flatMap { parseFlexibleDate($0) },
                    firm:              row.firm,
                    toGrade:           row.to_grade,
                    fromGrade:         row.from_grade,
                    action:            row.action,
                    priceTargetAction: row.price_target_action,
                    currentPT:         row.current_pt,
                    priorPT:           row.prior_pt
                )
            }
        )
    }
}
