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

/// Simbol mata uang sesuai market: "Rp" untuk IDX, "$" untuk saham AS
/// (NASDAQ/NYSE/ETF).
func currencySymbol(for market: String) -> String {
    market.uppercased() == "IDX" ? "Rp" : "$"
}

/// Format harga lengkap dengan prefix mata uang — mis. "Rp9.850" (IDX) atau
/// "$197,53" (AS).
func formatPriceWithSymbol(_ value: Double, market: String) -> String {
    currencySymbol(for: market) + formatPrice(value, market: market)
}

/// Format harga crypto dengan desimal adaptif — harga crypto rentangnya
/// ekstrem (BTC puluhan ribu dolar, sebagian coin di bawah $0.0001), jadi
/// jumlah desimal tetap (kayak formatPrice untuk saham) tidak cocok: kalau
/// dipatok 2 desimal, coin murah akan selalu tampil "0,00".
func formatCryptoPrice(_ value: Double) -> String {
    let absValue = abs(value)
    if absValue >= 1        { return formatIDR(value, decimals: 2) }
    if absValue >= 0.01     { return formatIDR(value, decimals: 4) }
    return formatIDR(value, decimals: 8)
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
