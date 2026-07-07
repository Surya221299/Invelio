//
//  ChartViewModelProtocol.swift
//  StockAppTryNew
//
//  Abstraction so the reusable chart components (ChartCanvasView,
//  XAxisAnimatedLabels, TimeRangeSelectorView) can be driven by any
//  view model that exposes a price/value series — not just
//  StockDetailViewModel. PortfolioChartViewModel conforms to this too,
//  so the same chart UI can power the Portfolio summary chart.
//
//  NOTE: oneDayTotalSlots and oneDayOpenMinutes are INSTANCE vars (not static)
//  so US-market stocks (79 slots, open ~20:30 WIB) render correctly vs IDX
//  stocks (87 slots, open 09:00 WIB). The chart line reaches the right edge
//  only when these values match the actual data from normalizeToSlots.
//

import Foundation

@MainActor
protocol ChartViewModelProtocol: ObservableObject {

    var dataPoints:    [StockDataPoint] { get }
    var selectedRange: TimeRange        { get set }
    var isLoading:     Bool             { get }

    var minPrice:    Double { get }
    var maxPrice:    Double { get }
    var startPrice:  Double { get }
    var latestPrice: Double { get }

    var oneDayTotalSlots:  Int { get }
    var oneDayOpenMinutes: Int { get }

    func oneDaySlotIndex(for date: Date) -> Int
    func fetchChartData() async
}
