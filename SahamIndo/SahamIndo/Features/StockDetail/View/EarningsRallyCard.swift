//
//  EarningsRallyCard.swift
//  SahamIndo
//
//  Kartu di halaman detail saham yang menampilkan:
//  1. Perkiraan jadwal rilis laporan keuangan (earnings) berikutnya + estimasi EPS.
//  2. Rally streak — status harga hijau berturut-turut.
//
//  Data diambil dari StockDetailViewModel.earningsInfo / .rallyStreak, yang
//  di-fetch sekali saat halaman muncul (lihat StockDetailView .task).
//

import SwiftUI

struct EarningsRallyCard: View {

    let earnings: EarningsInfo?
    let rally:    RallyStreakInfo?
    var dividend: DividendEvents? = nil

    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "id_ID")
        df.dateFormat = "d MMMM yyyy"
        return df
    }()

    /// Ada agenda dividen yang layak ditampilkan (minimal tanggal ex-dividen).
    private var hasDividend: Bool { dividend?.hasData == true }

    var body: some View {
        // Kalau semua data belum ada (masih loading / gagal fetch), sembunyikan
        // kartu sepenuhnya daripada menampilkan placeholder kosong.
        if earnings == nil && rally == nil && !hasDividend {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: DesignSpacing.l) {
                if let earnings {
                    earningsSection(earnings)
                }

                if hasDividend, let dividend {
                    if earnings != nil {
                        Divider().background(Color.primary.opacity(0.08))
                    }
                    dividendSection(dividend)
                }

                if (earnings != nil || hasDividend) && rally?.isRallying == true {
                    Divider().background(Color.primary.opacity(0.08))
                }

                if let rally, rally.isRallying {
                    rallySection(rally)
                }
            }
            .padding(DesignSpacing.xl)
            .background(
                RoundedRectangle(cornerRadius: DesignRadius.l)
                    .fill(Color.SurfaceWhite.opacity(0.04))
            )
        }
    }

    // MARK: - Earnings Section

    @ViewBuilder
    private func earningsSection(_ info: EarningsInfo) -> some View {
        VStack(alignment: .leading, spacing: DesignSpacing.m) {
            HStack(spacing: DesignSpacing.s) {
                Image(systemName: "calendar.badge.clock")
                    .foregroundColor(Color.AccentIndigo)
                Text("Jadwal Rilis Laporan Keuangan")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary.opacity(0.9))
            }

            if let date = info.nextEarningsDate {
                Text(Self.dateFormatter.string(from: date))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.primary)

                if let days = info.daysUntil {
                    Text(daysUntilLabel(days))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(days <= 3 ? Color.PrimaryYellow : .primary.opacity(0.6))
                }

                if info.epsEstimate != nil || info.revenueEstimate != nil {
                    HStack(spacing: DesignSpacing.xl) {
                        if let eps = info.epsEstimate {
                            estimateStat(label: "Estimasi EPS", value: String(format: "%.2f", eps))
                        }
                        if let rev = info.revenueEstimate {
                            estimateStat(label: "Estimasi Revenue", value: formatRupiahShort(rev))
                        }
                    }
                    .padding(.top, DesignSpacing.xs)
                }

                Text("Perkiraan dari konsensus analis — tanggal & angka aktual bisa berbeda.")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .padding(.top, DesignSpacing.xxs)
            } else {
                Text("Jadwal rilis laporan keuangan berikutnya belum tersedia.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
        }
    }

    private func daysUntilLabel(_ days: Int) -> String {
        if days < 0 { return "Sudah lewat" }
        if days == 0 { return "Hari ini" }
        if days == 1 { return "Besok (H-1)" }
        return "\(days) hari lagi (H-\(days))"
    }

    private func estimateStat(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primary)
        }
    }

    private func formatRupiahShort(_ value: Double) -> String {
        let abs = Swift.abs(value)
        if abs >= 1_000_000_000_000 { return String(format: "%.1fT", value / 1_000_000_000_000) }
        if abs >= 1_000_000_000     { return String(format: "%.1fM", value / 1_000_000_000) }
        if abs >= 1_000_000         { return String(format: "%.1fJt", value / 1_000_000) }
        return String(format: "%.0f", value)
    }

    // MARK: - Dividend / Corporate Events Section

    @ViewBuilder
    private func dividendSection(_ info: DividendEvents) -> some View {
        VStack(alignment: .leading, spacing: DesignSpacing.m) {
            HStack(spacing: DesignSpacing.s) {
                Image(systemName: "dollarsign.circle.fill")
                    .foregroundColor(Color.ProfitGreen)
                Text("Agenda Dividen")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary.opacity(0.9))
            }

            if let ex = info.exDividendDate {
                Text("Ex-Dividen")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                Text(Self.dateFormatter.string(from: ex))
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.primary)
                if let days = info.exDaysUntil {
                    Text(exDaysLabel(days))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(days >= 0 && days <= 5 ? Color.PrimaryYellow : .primary.opacity(0.6))
                }
            }

            HStack(spacing: DesignSpacing.xl) {
                if let amount = info.amount {
                    estimateStat(label: "Dividen/lembar",
                                 value: formatDividend(amount, currency: info.currency))
                }
                if let y = info.yieldPercent {
                    estimateStat(label: "Dividend Yield",
                                 value: String(format: "%.2f%%", y))
                }
                if let pay = info.paymentDate {
                    estimateStat(label: "Pembayaran",
                                 value: Self.dateFormatter.string(from: pay))
                }
            }
            .padding(.top, DesignSpacing.xxs)

            Text("Mulai tanggal ex-dividen, pembeli baru tidak berhak atas dividen — harga saham cenderung turun kira-kira sebesar dividen. Perkiraan dari yfinance, bisa berbeda dari jadwal resmi emiten.")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .padding(.top, DesignSpacing.xxs)
        }
    }

    private func exDaysLabel(_ days: Int) -> String {
        if days < 0  { return "Sudah lewat \(-days) hari lalu" }
        if days == 0 { return "Hari ini" }
        if days == 1 { return "Besok (H-1)" }
        return "\(days) hari lagi (H-\(days))"
    }

    /// Nominal dividen per lembar. IDR tanpa desimal (mis. Rp356), lainnya 2 desimal.
    private func formatDividend(_ value: Double, currency: String?) -> String {
        switch (currency ?? "").uppercased() {
        case "IDR": return "Rp" + String(format: "%.0f", value)
        case "USD": return "$" + String(format: "%.2f", value)
        case "":    return String(format: "%.2f", value)
        default:    return (currency ?? "") + " " + String(format: "%.2f", value)
        }
    }

    // MARK: - Rally Streak Section

    @ViewBuilder
    private func rallySection(_ streak: RallyStreakInfo) -> some View {
        HStack(spacing: DesignSpacing.m) {
            Image(systemName: "flame.fill")
                .foregroundColor(Color.ProfitGreen)
                .font(.system(size: 18))

            VStack(alignment: .leading, spacing: 2) {
                Text("Rally Streak 🔥")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color.ProfitGreen)
                Text("Hijau \(streak.streakDays) hari perdagangan berturut-turut")
                    .font(.system(size: 12))
                    .foregroundColor(.primary.opacity(0.8))
            }

            Spacer()
        }
        .padding(DesignSpacing.m)
        .background(
            RoundedRectangle(cornerRadius: DesignRadius.m)
                .fill(Color.ProfitGreen.opacity(0.12))
        )
    }
}
