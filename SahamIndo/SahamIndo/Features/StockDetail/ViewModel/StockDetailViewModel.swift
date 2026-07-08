//
//  StockDetailViewModel.swift
//  StockAppTryNew
//
//  Created by Surya on 16/06/26.
//

import SwiftUI
import Combine

@MainActor
final class StockDetailViewModel: ObservableObject, ChartViewModelProtocol {

    // MARK: - Published State

    @Published private(set) var dataPoints:   [StockDataPoint] = []
    @Published private(set) var detail:       StockDetail?
    @Published private(set) var isLoading:    Bool             = false
    @Published private(set) var errorMessage: String?
    @Published var selectedRange: TimeRange = .oneDay

    // MARK: - Live price streaming (single source of truth, shared dengan HomeView)

    let livePriceStore = LivePriceStore.shared

    // MARK: - Earnings & Rally Streak

    @Published private(set) var earningsInfo: EarningsInfo?
    @Published private(set) var rallyStreak:  RallyStreakInfo?

    let item: PortfolioItem

    // MARK: - Computed price properties

    var minPrice:    Double { dataPoints.map(\.close).min() ?? 0 }
    var maxPrice:    Double { dataPoints.map(\.close).max() ?? 0 }
    var startPrice:  Double { dataPoints.first?.close ?? 0 }
    var latestPrice: Double { dataPoints.last?.close  ?? 0 }
    var changeAmount:  Double { latestPrice - startPrice }
    var changePercent: Double { startPrice != 0 ? (changeAmount / startPrice) * 100 : 0 }
    var isPositive:    Bool   { latestPrice >= startPrice }

    // MARK: - ChartViewModelProtocol: 1D slot config (instance — dynamic per market)
    //
    // These are instance vars so the chart renders correctly for both:
    //   IDX stocks  → 87 slots (5-min candles 09:00–16:10 WIB), open = 09:00
    //   US  stocks  → 79 slots (5-min candles ~20:30–23:30 WIB), open = market open time
    //
    // Values are set inside normalizeToSlots() once the actual candle data arrives.
    // Until then they default to IDX values.

    @Published private(set) var oneDayTotalSlots:  Int = 87
    @Published private(set) var oneDayOpenMinutes: Int = 9 * 60   // 09:00 WIB (IDX default)

    private var oneDayOpenDate: Date?

    // MARK: - Dependencies

    private let fetchChartUseCase: FetchChartDataUseCase
    private let detailRepository:  StockDetailRepositoryProtocol
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    init(item: PortfolioItem,
         fetchChartUseCase: FetchChartDataUseCase,
         detailRepository:  StockDetailRepositoryProtocol) {
        self.item              = item
        self.fetchChartUseCase = fetchChartUseCase
        self.detailRepository  = detailRepository

        // Forward perubahan dari LivePriceStore (nested ObservableObject) ke
        // objectWillChange milik ViewModel ini. Tanpa ini, update harga
        // internal LivePriceStore TIDAK akan memicu re-render otomatis pada
        // View yang cuma observe StockDetailViewModel — nested @Published
        // object tidak cascade objectWillChange-nya secara otomatis di
        // Combine/SwiftUI.
        livePriceStore.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    // MARK: - Public Actions

    func fetchChartData() async {
        isLoading    = true
        errorMessage = nil
        let (points, _) = await fetchChartUseCase.execute(symbol: item.symbol,
                                                           range: selectedRange)
        dataPoints = selectedRange == .oneDay ? normalizeToSlots(points) : points
        if dataPoints.isEmpty {
            errorMessage = "Tidak ada data untuk \(item.symbol) (\(selectedRange.rawValue))"
        }
        isLoading = false
    }

    func fetchDetail() async {
        detail = try? await detailRepository.fetchDetail(symbol: item.symbol)
    }

    // MARK: - Live price streaming

    /// Harga terkini: prioritaskan update dari LivePriceStore (near-real-time,
    /// sumber yang SAMA persis dengan yang dipakai HomeView), fallback ke
    /// candle terakhir kalau belum ada update masuk untuk simbol ini.
    var streamedOrLatestPrice: Double {
        if let live = livePriceStore.price(for: item.symbol), live.price > 0 {
            return live.price
        }
        return latestPrice
    }

    /// Change amount/persen yang sesuai dengan `streamedOrLatestPrice` — dari
    /// harga regular market (BUKAN extended hours; harga utama sengaja tetap
    /// closing regular market, data pre/post/overnight cuma tampil di badge
    /// terpisah — lihat ExtendedHoursBadgeView). `nil` kalau belum ada update
    /// sama sekali dari LivePriceStore (View fallback ke snapshot awal).
    var streamedChange: Double? {
        livePriceStore.price(for: item.symbol)?.change
    }

    var streamedPctChange: Double? {
        livePriceStore.price(for: item.symbol)?.pctChange
    }

    func startPriceStream() {
        livePriceStore.acquire()
    }

    func stopPriceStream() {
        livePriceStore.release()
    }

    /// Ambil jadwal earnings & rally streak. Dipanggil sekali saat halaman
    /// detail muncul — datanya sengaja tidak di-refresh sesering harga
    /// (cache backend sendiri sudah 6 jam untuk earnings).
    func fetchEarningsAndRallyInfo() async {
        async let earnings = try? detailRepository.fetchEarningsInfo(symbol: item.symbol)
        async let rally    = try? detailRepository.fetchRallyStreak(symbol: item.symbol)
        earningsInfo = await earnings
        rallyStreak  = await rally
    }

    func oneDaySlotIndex(for date: Date) -> Int {
        guard let openDate = oneDayOpenDate else { return 0 }
        let minutes = date.timeIntervalSince(openDate) / 60.0
        return max(0, min(Int(minutes / 5.0), oneDayTotalSlots - 1))
    }

    // MARK: - Private

    private func normalizeToSlots(_ candles: [StockDataPoint]) -> [StockDataPoint] {
        guard !candles.isEmpty else { return [] }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Jakarta")!
        let now = Date()

        let openDate = candles[0].date
        let openHour = cal.component(.hour, from: openDate)

        // Detect US Market: typically opens 20:30 or 21:30 WIB (hour >= 19 or early morning)
        let isUS       = openHour >= 19 || openHour < 5
        let totalSlots = isUS ? 79 : 87

        // Derive open-of-session in minutes since midnight (WIB) for axis labels
        let openHourWIB   = cal.component(.hour,   from: openDate)
        let openMinuteWIB = cal.component(.minute, from: openDate)
        let openMins      = openHourWIB * 60 + openMinuteWIB

        self.oneDayTotalSlots  = totalSlots
        self.oneDayOpenMinutes = openMins
        self.oneDayOpenDate    = openDate

        var slots: [StockDataPoint?] = Array(repeating: nil, count: totalSlots)

        for candle in candles {
            let idx = oneDaySlotIndex(for: candle.date)
            guard idx >= 0, idx < totalSlots else { continue }
            slots[idx] = candle
        }

        let currentSlotIdx: Int
        if isUS {
            let hoursSinceOpen = now.timeIntervalSince(openDate) / 3600.0
            if hoursSinceOpen >= 0 && hoursSinceOpen < 16 {
                let minutes = now.timeIntervalSince(openDate) / 60.0
                currentSlotIdx = max(0, min(Int(minutes / 5.0), totalSlots - 1))
            } else {
                currentSlotIdx = totalSlots - 1
            }
        } else {
            if cal.isDate(openDate, inSameDayAs: now) {
                let minutes = now.timeIntervalSince(openDate) / 60.0
                currentSlotIdx = max(0, min(Int(minutes / 5.0), totalSlots - 1))
            } else {
                currentSlotIdx = totalSlots - 1
            }
        }

        for i in stride(from: 1, through: currentSlotIdx, by: 1) {
            if slots[i] == nil, let prev = slots[i - 1] {
                let slotDate = openDate.addingTimeInterval(TimeInterval(i * 5 * 60))
                slots[i] = StockDataPoint(date: slotDate, close: prev.close, open: prev.close,
                                           high: prev.close, low: prev.close, volume: 0)
            }
        }
        return slots[0...currentSlotIdx].compactMap { $0 }
    }
}
