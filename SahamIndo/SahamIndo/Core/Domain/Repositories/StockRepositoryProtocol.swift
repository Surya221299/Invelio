//
//  StockRepositoryProtocol.swift
//  StockAppTryNew
//
//  Created by Surya on 16/06/26.
//

import Foundation
// Interface Segregation Principle — each protocol covers one responsibility.

// MARK: - Stock Fetching

protocol StockRepositoryProtocol {
    /// Fetch all monitored stocks (with transparent cache fallback).
    func fetchAllStocks() async -> (stocks: [Stock], cacheState: CacheState)

    /// Fetch a single stock by symbol.
    func fetchStock(symbol: String) async throws -> Stock
}

// MARK: - Stock Detail

protocol StockDetailRepositoryProtocol {
    func fetchDetail(symbol: String) async throws -> StockDetail
    func fetchEarningsInfo(symbol: String) async throws -> EarningsInfo
    func fetchRallyStreak(symbol: String) async throws -> RallyStreakInfo
}

// MARK: - Chart / Candle Data

protocol ChartRepositoryProtocol {
    func fetchCandles(symbol: String, range: TimeRange) async -> (dataPoints: [StockDataPoint], cacheState: CacheState)
}

// MARK: - AI Market Insights

protocol InsightRepositoryProtocol {
    func fetchSentimentInsight() async throws -> AIInsight
    func fetchForeignFlowInsight() async throws -> AIInsight
    func fetchMacroInsight() async throws -> AIInsight
    func fetchMacroIndicators() async throws -> [MacroIndicator]
    func fetchWeeklyRecommendations() async throws -> [StockRecommendation]
}

// MARK: - StockRecommendation (domain model for recommendations)

struct StockRecommendation {
    let rank: Int
    let symbol: String
    let companyName: String?
    let sector: String?
    let recommendation: String
    let reason: String?
}

// MARK: - Chat / Streaming

protocol ChatRepositoryProtocol {
    func sendMessage(question: String, history: [ChatHistoryItem]) async throws -> AsyncThrowingStream<String, Error>
}

// MARK: - Alert (Notification)

protocol AlertRepositoryProtocol {
    func fetchRemoteAlerts() async throws -> [RemoteAlert]
}

struct RemoteAlert {
    let id: Int
    let symbol: String
    let message: String
    let delta: Double
    let date: String
    let jenis: String   // "sentimen" | "earnings" | "rally_streak"
}
