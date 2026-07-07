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

    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "id_ID")
        df.dateFormat = "d MMMM yyyy"
        return df
    }()

    var body: some View {
        // Kalau kedua data belum ada (masih loading / gagal fetch), sembunyikan
        // kartu sepenuhnya daripada menampilkan placeholder kosong.
        if earnings == nil && rally == nil {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: DesignSpacing.l) {
                if let earnings {
                    earningsSection(earnings)
                }

                if earnings != nil && rally?.isRallying == true {
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
