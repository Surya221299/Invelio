//
//  Formatters.swift
//  StockAppTryNew
//
//  Created by Surya on 16/06/26.
//

import Foundation

// MARK: - IDR Formatting

func formatIDR(_ value: Double, decimals: Int = 0) -> String {
    let f = NumberFormatter()
    f.numberStyle           = .decimal
    f.groupingSeparator     = "."
    f.decimalSeparator      = ","
    f.minimumFractionDigits = decimals
    f.maximumFractionDigits = decimals
    return f.string(from: NSNumber(value: value)) ?? "\(Int(value))"
}

func formatIDRShort(_ value: Double) -> String {
    if value >= 1_000_000_000 { return String(format: "%.1fM",  value / 1_000_000_000) }
    if value >= 1_000_000     { return String(format: "%.1fJt", value / 1_000_000) }
    if value >= 1_000         { return String(format: "%.0fRb", value / 1_000) }
    return String(format: "%.0f", value)
}

// MARK: - Relative Time
func timeAgoString(from date: Date, now: Date = Date()) -> String {
    let diff = Int(now.timeIntervalSince(date))
    if diff < 60       { return "baru saja" }
    let mins = diff / 60
    if mins < 60       { return "\(mins) mnt lalu" }
    return "\(mins / 60) jam lalu"
}

// MARK: - BEI Trading Hours
// Delegasi ke IDXTradingCalendar (single source of truth).
// Alias ini dipertahankan agar kode lama tidak perlu diubah sekaligus.
typealias BEITradingHours = IDXTradingCalendar
