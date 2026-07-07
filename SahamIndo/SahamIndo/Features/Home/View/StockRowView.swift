////
////  StockRowView.swift
////  StockAppTryNew
////
////  Created by Surya on 16/06/26.
////
//

import SwiftUI
import Combine

// MARK: - StockRowView

struct StockRowView: View {
    let stock: PortfolioItem

    // Share the same VM so sparkline and price badge both use live candle data —
    // identical source to what StockDetailView shows.
    @StateObject private var sparklineVM = MiniSparklineViewModel(
        chartRepository: DIContainer.shared.chartRepository
    )

    var body: some View {
        HStack(spacing: 8) {
            StockAvatarView(symbol: stock.symbol)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(stock.symbol).font(.system(size: 15, weight: .bold))
                    SentimentPillView(sentiment: stock.sentiment, size: .small)
                }
                Text(stock.name ?? "-").font(.caption).foregroundColor(.secondary).lineLimit(1)
                SentimentBarView(sentiment: stock.sentiment).frame(width: DesignSize.sentimentBarMaxWidth)
            }
            .layoutPriority(1)
            Spacer(minLength: 0)
            MiniSparklineView(vm: sparklineVM)
                .frame(width: DesignSize.sparklineWidth, height: DesignSize.sparklineHeight).padding(.trailing, 8)
            // Use live candle price when available; fall back to API snapshot while loading.
            let liveReady = sparklineVM.livePrice > 0
            PriceBadgeView(
                price:         liveReady ? sparklineVM.livePrice    : stock.price,
                change:        liveReady ? sparklineVM.liveChange   : stock.change,
                percentChange: liveReady ? sparklineVM.livePctChange : stock.percentChange
            )
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.vertical, 6)
        .task(id: stock.symbol) { await sparklineVM.fetch(symbol: stock.symbol) }
        .onReceive(Timer.publish(every: 5 * 60, on: .main, in: .common).autoconnect()) { _ in
            Task { await sparklineVM.fetch(symbol: stock.symbol) }
        }
    }
}

// MARK: - PriceBadgeView

struct PriceBadgeView: View {
    let price: Double
    let change: Double
    let percentChange: Double
    private var isPositive: Bool { change >= 0 }
    private var color: Color { isPositive ? Color.ProfitGreen : Color.LossRed }
    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(formatIDR(price))
                .font(.system(size: 16, weight: .semibold)).lineLimit(1).fixedSize(horizontal: true, vertical: false)
            HStack(spacing: 2) {
                Image(systemName: isPositive ? "arrow.up.right" : "arrow.down.forward")
                    .font(.system(size: 8, weight: .bold))
                Text(String(format: "%.2f%%", abs(percentChange)))
                    .font(.system(size: 10, weight: .medium)).lineLimit(1).fixedSize(horizontal: true, vertical: false)
            }
            .foregroundColor(color)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(color.opacity(0.1)).clipShape(Capsule())
        }
    }
}
