//
//  FetchStocksUseCase.swift
//  StockAppTryNew
//
//  Created by Surya on 16/06/26.
//

import Foundation
// Single-responsibility: orchestrate fetching + mapping into PortfolioItems.

final class FetchStocksUseCase {

    private let stockRepo:  StockRepositoryProtocol
    private let detailRepo: StockDetailRepositoryProtocol

    init(stockRepo: StockRepositoryProtocol, detailRepo: StockDetailRepositoryProtocol) {
        self.stockRepo  = stockRepo
        self.detailRepo = detailRepo
    }

    func execute(holdings: [Holding], isWatchlist: Bool = false) async -> (items: [PortfolioItem], cacheState: CacheState) {
        let (allStocks, cacheState) = await stockRepo.fetchAllStocks()

        guard !allStocks.isEmpty else { return ([], cacheState) }

        let stockMap = Dictionary(uniqueKeysWithValues: allStocks.map { ($0.symbol, $0) })
        let holdingMap = Dictionary(uniqueKeysWithValues: holdings.map { ($0.symbol, $0) })
        
        let targetSymbols = isWatchlist ? allStocks.map { $0.symbol } : holdings.map { $0.symbol }

        // Parallel fetch of details for held/watched symbols
        let details: [String: StockDetail] = await withTaskGroup(of: (String, StockDetail?).self) { group in
            for symbol in targetSymbols {
                group.addTask { [weak self] in
                    let detail = try? await self?.detailRepo.fetchDetail(symbol: symbol)
                    return (symbol, detail)
                }
            }
            var result: [String: StockDetail] = [:]
            for await (symbol, detail) in group {
                if let d = detail { result[symbol] = d }
            }
            return result
        }

        let items: [PortfolioItem] = targetSymbols.compactMap { symbol in
            guard let stock = stockMap[symbol] else { return nil }
            // Prioritaskan harga dari StockDetail (endpoint /stockDetail/:symbol)
            // karena konsisten dengan yang ditampilkan di StockDetailView.
            // Fallback ke harga allStocks jika detail belum tersedia.
            let detail = details[symbol]
            let price         = detail?.price         ?? stock.price
            let change        = detail?.change        ?? stock.change
            let percentChange = detail?.percentChange ?? stock.percentChange
            let sentiment: Sentiment
            if let detail {
                sentiment = .from(type: detail.sentiment, score: detail.sentimentScore)
            } else {
                sentiment = .estimated(percentChange: stock.percentChange)
            }
            return PortfolioItem(
                symbol:        stock.symbol,
                name:          stock.name ?? detail?.name,
                price:         price,
                change:        change,
                percentChange: percentChange,
                quantity:      holdingMap[symbol]?.quantity ?? 0,
                sentiment:     sentiment,
                market:        detail?.market ?? stock.market
            )
        }

        return (items, cacheState)
    }
}

// MARK: - FetchChartDataUseCase

final class FetchChartDataUseCase {
    private let repo: ChartRepositoryProtocol
    init(repo: ChartRepositoryProtocol) { self.repo = repo }

    func execute(symbol: String, range: TimeRange) async -> (dataPoints: [StockDataPoint], cacheState: CacheState) {
        await repo.fetchCandles(symbol: symbol, range: range)
    }
}
