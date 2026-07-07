//
//  HomeViewModel.swift
//  StockAppTryNew
//
//  Created by Surya on 16/06/26.
//

import SwiftUI
import Combine

@MainActor
final class HomeViewModel: ObservableObject {

    // MARK: - Published State

    @Published private(set) var stocks: [PortfolioItem]  = []
    @Published private(set) var cacheState: CacheState   = .live
    @Published private(set) var isLoading: Bool          = false
    @Published private(set) var insightChips: [InsightChip] = HomeViewModel.defaultChips()

    // MARK: - Dependencies (injected via DI)

    private let fetchStocksUseCase: FetchStocksUseCase
    private let insightRepository:  InsightRepositoryProtocol
    let chartRepository: ChartRepositoryProtocol     // accessed by MiniSparklineViewModel

    // MARK: - Init

    init(
        fetchStocksUseCase: FetchStocksUseCase,
        insightRepository:  InsightRepositoryProtocol,
        chartRepository:    ChartRepositoryProtocol
    ) {
        self.fetchStocksUseCase = fetchStocksUseCase
        self.insightRepository  = insightRepository
        self.chartRepository    = chartRepository
    }

    // MARK: - Public Actions

    func loadStocks(holdings: [Holding]) async {
        isLoading = true
        let (items, state) = await fetchStocksUseCase.execute(holdings: holdings, isWatchlist: true)
        stocks     = items
        cacheState = state
        isLoading  = false
    }

    func loadInsights() async {
        async let sentimenFetch = try? insightRepository.fetchSentimentInsight()
        async let makroFetch    = try? insightRepository.fetchMacroInsight()
        async let rekFetch      = try? insightRepository.fetchWeeklyRecommendations()

        let sentimen = await sentimenFetch
        let makro    = await makroFetch
        let rek      = await rekFetch

        let teknikal: String
        if let top = rek?.first {
            let alasan = (top.reason ?? "")
                .components(separatedBy: "⚠️").first?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            teknikal = "Rekomendasi utama minggu ini: **\(top.symbol)** (\(top.recommendation)). \(alasan)"
        } else {
            teknikal = "Data rekomendasi teknikal sedang diperbarui."
        }

        let chips = [
            InsightChip(label: "Analisis Teknikal", text: teknikal),
            InsightChip(label: "Sentimen Berita",   text: sentimen?.text ?? "Data sentimen berita sedang diperbarui."),
            InsightChip(label: "Makro IDR",         text: makro?.text    ?? "Data makro sedang diperbarui.")
        ]
        insightChips = chips
    }

    // MARK: - Helpers

    private static func defaultChips() -> [InsightChip] {[
        InsightChip(label: "Analisis Teknikal",
                    text: "Sektor **perbankan** menunjukkan momentum positif. **BBCA & BBRI** berpotensi retest resistance."),
        InsightChip(label: "Sentimen Berita",
                    text: "Sentimen terhadap **GGRM** meningkat signifikan. Buzz positif naik **34%** dalam 48 jam terakhir."),
        InsightChip(label: "Makro IDR",
                    text: "Rupiah menguat ke **Rp 15.820/USD** didukung surplus neraca dagang.")
    ]}
}


