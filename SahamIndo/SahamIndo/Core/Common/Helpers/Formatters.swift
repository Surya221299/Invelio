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

// MARK: - Market-Aware Price Formatting

/// Format harga sesuai konvensi market asalnya:
/// - IDX: tanpa desimal (mis. "9.850") — harga saham IDX memang bulat (kelipatan tick size).
/// - NASDAQ/NYSE/ETF: 2 desimal (mis. "197,53") — harga saham AS umumnya pakai sen.
///
/// Dipakai di mana pun harga ditampilkan (list saham, detail saham) supaya
/// konsisten — sebelumnya saham AS ikut format IDX (dibulatkan ke integer,
/// mis. "197" padahal harga aslinya "197.53").
func formatPrice(_ value: Double, market: String) -> String {
    let decimals = market.uppercased() == "IDX" ? 0 : 2
    return formatIDR(value, decimals: decimals)
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
