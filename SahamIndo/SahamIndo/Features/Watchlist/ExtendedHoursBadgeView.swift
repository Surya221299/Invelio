//
//  ExtendedHoursBadgeView.swift
//  SahamIndo
//
//  Badge kecil menampilkan harga pre-market/after-market untuk saham
//  NASDAQ/NYSE/ETF. Dipakai bareng di StockRowView (Home list) dan
//  StockDetailView. Render kosong (EmptyView) kalau tidak ada data —
//  IDX tidak akan pernah menampilkan apa pun karena backend memang
//  tidak mengirim `extended_hours` untuk market itu (lihat
//  fetch_extended_hours_info di backend).
//

import SwiftUI

struct ExtendedHoursBadgeView: View {
    let data:   ExtendedHoursUpdate?
    /// "compact" untuk row di list Home, "full" untuk StockDetailView.
    var style:  Style = .full

    enum Style { case compact, full }

    var body: some View {
        if let data, data.hasData {
            let price      = data.isPreMarket ? data.preMarketPrice  : data.postMarketPrice
            let changePct  = data.isPreMarket ? data.preMarketChangePercent  : data.postMarketChangePercent
            let isPositive = (changePct ?? 0) >= 0

            HStack(spacing: 4) {
                Image(systemName: data.sessionIcon)
                    .font(.system(size: style == .compact ? 8 : 10))
                Text(data.sessionLabel)
                    .font(.system(size: style == .compact ? 9 : 11, weight: .medium))
                if let price {
                    Text(formatPrice(price, market: "NASDAQ"))
                        .font(.system(size: style == .compact ? 9 : 11, weight: .semibold))
                }
                if let changePct {
                    Text(String(format: "%+.2f%%", changePct))
                        .font(.system(size: style == .compact ? 8 : 10, weight: .medium))
                }
                if style == .full, let ts = data.sessionTimestamp {
                    Text("· \(timeAgoString(from: ts))")
                        .font(.system(size: 9, weight: .regular))
                        .opacity(0.75)
                }
            }
            .foregroundColor(isPositive ? Color.ProfitGreen : Color.LossRed)
            .padding(.horizontal, style == .compact ? 5 : 7)
            .padding(.vertical, style == .compact ? 2 : 3)
            .background(
                (isPositive ? Color.ProfitGreen : Color.LossRed).opacity(0.12)
            )
            .clipShape(Capsule())
        } else {
            EmptyView()
        }
    }
}
