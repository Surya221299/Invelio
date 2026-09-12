////
////  StockRepository.swift
////  StockAppTryNew
////
////  Created by Surya on 16/06/26.
////

import Foundation

// MARK: - StockRepository

final class StockRepository: StockRepositoryProtocol {

    private let cache = StockCacheManager.shared

    func fetchAllStocks() async -> (stocks: [Stock], cacheState: CacheState) {
        do {
            let dtos  = try await APIClient.get(.allStocks, as: [StockSummaryDTO].self)
            let stocks = StockMapper.toStocks(dtos)
            cache.save(stocks: stocks)
            return (stocks, .live)
        } catch {
            print("[StockRepository] offline:", error.localizedDescription)
            if let cached = cache.loadStocks() {
                let age = cache.cacheAgeString() ?? "?"
                return (cached.stocks, .cached(age: age))
            }
            return ([], .noData)
        }
    }

    func fetchStock(symbol: String) async throws -> Stock {
        let dto = try await APIClient.get(.stock(symbol: symbol), as: StockSummaryDTO.self)
        return StockMapper.toStock(dto)
    }
}

// MARK: - StockDetailRepository

final class StockDetailRepository: StockDetailRepositoryProtocol {

    func fetchDetail(symbol: String) async throws -> StockDetail {
        let dto      = try await APIClient.get(.stockDetail(symbol: symbol), as: StockDetailDTO.self)
        return StockMapper.toStockDetail(dto)
    }

    func fetchEarningsInfo(symbol: String) async throws -> EarningsInfo {
        let dto = try await APIClient.get(.earnings(symbol: symbol), as: EarningsInfoDTO.self)
        return StockMapper.toEarningsInfo(dto)
    }

    func fetchRallyStreak(symbol: String) async throws -> RallyStreakInfo {
        let dto = try await APIClient.get(.rallyStreak(symbol: symbol), as: RallyStreakDTO.self)
        return StockMapper.toRallyStreakInfo(dto)
    }

    func fetchAnalystRatings(symbol: String, market: String?) async throws -> AnalystRatings {
        let dto = try await APIClient.get(.analystRatings(symbol: symbol, market: market), as: AnalystRatingsDTO.self)
        return StockMapper.toAnalystRatings(dto)
    }

    func fetchFundamentals(symbol: String, market: String?) async throws -> CompanyFundamentals {
        let dto = try await APIClient.get(.fundamental(symbol: symbol, market: market), as: FundamentalDTO.self)
        return StockMapper.toFundamentals(dto)
    }

    func fetchMoat(symbol: String, market: String?) async throws -> MoatInsight {
        let dto = try await APIClient.get(.moat(symbol: symbol, market: market), as: MoatDTO.self)
        return StockMapper.toMoat(dto)
    }

    func fetchDividendEvents(symbol: String, market: String?) async throws -> DividendEvents {
        let dto = try await APIClient.get(.dividendEvents(symbol: symbol, market: market), as: DividendEventsDTO.self)
        return StockMapper.toDividendEvents(dto)
    }
}

// MARK: - ChartRepository

final class ChartRepository: ChartRepositoryProtocol {

    private let cache = StockCacheManager.shared

    func fetchCandles(symbol: String, range: TimeRange, market: String?) async -> (dataPoints: [StockDataPoint], cacheState: CacheState) {
        do {
            let dtos = try await APIClient.get(.candles(symbol: symbol, range: range.rawValue, market: market), as: [CandleDTO].self)
            let points = StockMapper.toDataPoints(dtos)
            cache.save(candles: points, symbol: symbol, range: range)
            return (points, .live)
        } catch {
            print("[ChartRepository] fetch failed (\(symbol)/\(range.rawValue)):", error.localizedDescription)
            if let cached = cache.loadCandles(symbol: symbol, range: range) {
                let age = cache.cacheAgeString(symbol: symbol, range: range) ?? "?"
                return (cached.candles, .cached(age: age))
            }
            // JANGAN fabrikasi harga. IDXDummyPriceGenerator menghasilkan random
            // walk (base dari symbol.hashValue yang di-seed acak tiap run +
            // Double.random per candle), jadi harga saham yang benar-benar tidak
            // punya data di backend (mis. hasil search yang tidak dimonitor) akan
            // tampil sebagai harga palsu yang berbeda-beda tiap buka. Untuk app
            // finansial ini menyesatkan — lebih baik tampilkan "data tidak
            // tersedia" (dataPoints kosong → UI sudah menanganinya).
            return ([], .noData)
        }
    }
}

// MARK: - InsightRepository

final class InsightRepository: InsightRepositoryProtocol {

    func fetchSentimentInsight() async throws -> AIInsight {
        let dto = try await APIClient.get(.insight(type: .sentimentNews), as: AIMarketInsightDTO.self)
        return PortfolioMapper.toInsight(dto, label: "Sentimen Berita")
    }

    func fetchForeignFlowInsight() async throws -> AIInsight {
        let dto = try await APIClient.get(.insight(type: .foreignFlow), as: AIMarketInsightDTO.self)
        return PortfolioMapper.toInsight(dto, label: "Asing Net Buy")
    }

    func fetchMacroInsight() async throws -> AIInsight {
        let dto = try await APIClient.get(.insight(type: .macro), as: AIMarketInsightDTO.self)
        return PortfolioMapper.toInsight(dto, label: "Makro IDR")
    }

    func fetchMacroIndicators() async throws -> [MacroIndicator] {
        let dto = try await APIClient.get(.macroLatest, as: MakroResponseDTO.self)
        return PortfolioMapper.toMacroIndicators(dto.indikator)
    }

    func fetchWeeklyRecommendations() async throws -> [StockRecommendation] {
        let dto = try await APIClient.get(.weeklyRecommendations, as: RekomendasiResponseDTO.self)
        return PortfolioMapper.toRecommendations(dto.rekomendasi)
    }
}

// MARK: - ChatRepository

final class ChatRepository: ChatRepositoryProtocol {
    func sendMessage(question: String, history: [ChatHistoryItem]) async throws -> AsyncThrowingStream<String, Error> {
        try await APIClient.streamChat(question: question, history: history)
    }
}

// MARK: - AlertRepository

final class AlertRepository: AlertRepositoryProtocol {
    func fetchRemoteAlerts() async throws -> [RemoteAlert] {
        let dtos = try await APIClient.get(.alerts, as: [AlertDTO].self)
        return StockMapper.toRemoteAlerts(dtos)
    }
}
