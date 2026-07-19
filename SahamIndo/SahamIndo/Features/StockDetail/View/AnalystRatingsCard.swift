//
//  AnalystRatingsCard.swift
//  SahamIndo
//
//  Kartu "Perkiraan Analis" di halaman detail saham:
//  1. Konsensus price target (mean + rentang low–high + potensi upside).
//  2. Distribusi rekomendasi (strongBuy…strongSell).
//  3. Riwayat rating action per firma (upgrade/downgrade + perubahan target).
//
//  Data dari StockDetailViewModel.analystRatings (di-fetch sekali saat muncul).
//  Semua bersifat PERKIRAAN — cakupan paling lengkap untuk saham AS.
//

import SwiftUI

struct AnalystRatingsCard: View {

    let ratings: AnalystRatings?

    var body: some View {
        if let ratings, !ratings.isEmpty {
            VStack(alignment: .leading, spacing: DesignSpacing.l) {
                header

                if let consensus = ratings.consensus {
                    consensusSection(consensus, analystCount: ratings.distribution?.total)
                }

                if let dist = ratings.distribution, dist.total > 0 {
                    distributionSection(dist)
                }

                if !ratings.history.isEmpty {
                    Divider().background(Color.primary.opacity(0.08))
                    historySection(ratings.history)
                }
            }
            .padding(DesignSpacing.xl)
            .background(
                RoundedRectangle(cornerRadius: DesignRadius.l)
                    .fill(Color.SurfaceWhite.opacity(0.04))
            )
        } else {
            EmptyView()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: DesignSpacing.s) {
            Image(systemName: "chart.bar.doc.horizontal")
                .foregroundColor(Color.PrimaryYellow)
            Text("Perkiraan Analis")
                .font(.headline)
                .foregroundColor(.primary)
            Spacer()
            Text("perkiraan")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Consensus

    @ViewBuilder
    private func consensusSection(_ c: AnalystConsensus, analystCount: Int?) -> some View {
        VStack(alignment: .leading, spacing: DesignSpacing.m) {
            HStack(alignment: .firstTextBaseline, spacing: DesignSpacing.s) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Target Konsensus")
                        .font(.caption).foregroundColor(.secondary)
                    Text(Self.price(c.mean))
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                }
                Spacer()
                if let upside = c.meanUpsidePercent {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(upside >= 0 ? "Potensi Naik" : "Potensi Turun")
                            .font(.caption2).foregroundColor(.secondary)
                        Text(String(format: "%+.1f%%", upside))
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(upside >= 0 ? Color.ProfitGreen : Color.LossRed)
                    }
                }
            }

            rangeBar(c)

            if let count = analystCount, count > 0 {
                Text("Berdasarkan \(count) analis")
                    .font(.caption2).foregroundColor(.secondary)
            }
        }
    }

    /// Bar rentang low–high dengan penanda harga acuan (current) & target rata-rata.
    @ViewBuilder
    private func rangeBar(_ c: AnalystConsensus) -> some View {
        if let low = c.low, let high = c.high, high > low {
            VStack(spacing: 4) {
                GeometryReader { geo in
                    let w = geo.size.width
                    let span = high - low
                    let curX = c.current.map { CGFloat(($0 - low) / span) * w }
                    let meanX = c.mean.map { CGFloat(($0 - low) / span) * w }
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.12)).frame(height: 6)
                        if let cur = c.current, cur >= low, cur <= high, let cx = curX {
                            marker(color: .secondary).offset(x: cx - 5)
                        }
                        if let mean = c.mean, mean >= low, mean <= high, let mx = meanX {
                            marker(color: Color.PrimaryYellow).offset(x: mx - 5)
                        }
                    }
                    .frame(height: 12)
                }
                .frame(height: 12)

                HStack {
                    Text(Self.price(low)).font(.caption2).foregroundColor(.secondary)
                    Spacer()
                    Text(Self.price(high)).font(.caption2).foregroundColor(.secondary)
                }
            }
        }
    }

    private func marker(color: Color) -> some View {
        Circle().fill(color)
            .frame(width: 10, height: 10)
            .overlay(Circle().stroke(Color.DarkPurpleAppBackground, lineWidth: 1.5))
    }

    // MARK: - Distribution

    @ViewBuilder
    private func distributionSection(_ d: RatingDistribution) -> some View {
        VStack(alignment: .leading, spacing: DesignSpacing.s) {
            Text("Distribusi Rekomendasi")
                .font(.caption).foregroundColor(.secondary)

            GeometryReader { geo in
                let w = geo.size.width
                let total = max(1, d.total)
                HStack(spacing: 1) {
                    segment(d.strongBuy, total, w, Color.ProfitGreen)
                    segment(d.buy,        total, w, Color.ProfitGreen.opacity(0.55))
                    segment(d.hold,       total, w, Color.secondary.opacity(0.5))
                    segment(d.sell,       total, w, Color.LossRed.opacity(0.55))
                    segment(d.strongSell, total, w, Color.LossRed)
                }
            }
            .frame(height: 10)
            .clipShape(Capsule())

            HStack(spacing: DesignSpacing.l) {
                legend("Beli", d.buyTotal, Color.ProfitGreen)
                legend("Tahan", d.hold, Color.secondary)
                legend("Jual", d.sellTotal, Color.LossRed)
            }
        }
    }

    private func segment(_ count: Int, _ total: Int, _ width: CGFloat, _ color: Color) -> some View {
        color.frame(width: count > 0 ? max(2, width * CGFloat(count) / CGFloat(total)) : 0)
    }

    private func legend(_ label: String, _ count: Int, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text("\(label) \(count)")
                .font(.caption2).foregroundColor(.secondary)
        }
    }

    // MARK: - History

    @ViewBuilder
    private func historySection(_ rows: [AnalystRatingRow]) -> some View {
        VStack(alignment: .leading, spacing: DesignSpacing.s) {
            Text("Riwayat Rating")
                .font(.caption).foregroundColor(.secondary)

            ForEach(rows) { row in
                historyRow(row)
                if row.id != rows.last?.id {
                    Divider().background(Color.primary.opacity(0.05))
                }
            }
        }
    }

    private func historyRow(_ row: AnalystRatingRow) -> some View {
        HStack(alignment: .top, spacing: DesignSpacing.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.firm.isEmpty ? "—" : row.firm)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(Self.actionLabel(row.action))
                        .font(.caption2).fontWeight(.semibold)
                        .foregroundColor(Self.actionColor(row.action))
                    if !row.toGrade.isEmpty {
                        Text(row.toGrade)
                            .font(.caption2).foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 2) {
                priceTargetChange(row)
                if let date = row.date {
                    Text(Self.dateFormatter.string(from: date))
                        .font(.caption2).foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func priceTargetChange(_ row: AnalystRatingRow) -> some View {
        if let current = row.currentPT {
            HStack(spacing: 4) {
                if let prior = row.priorPT, prior != current {
                    Text(Self.price(prior))
                        .font(.caption2).foregroundColor(.secondary).strikethrough()
                    Image(systemName: row.ptDirection == .up ? "arrow.up.right"
                                       : row.ptDirection == .down ? "arrow.down.right" : "arrow.right")
                        .font(.system(size: 9))
                        .foregroundColor(Self.ptColor(row.ptDirection))
                }
                Text(Self.price(current))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(Self.ptColor(row.ptDirection))
            }
        }
    }

    // MARK: - Formatting Helpers

    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "id_ID")
        df.dateFormat = "d MMM yyyy"
        return df
    }()

    private static let priceFormatter: NumberFormatter = {
        let nf = NumberFormatter()
        nf.numberStyle = .decimal
        nf.maximumFractionDigits = 2
        nf.minimumFractionDigits = 0
        return nf
    }()

    static func price(_ v: Double?) -> String {
        guard let v else { return "—" }
        return priceFormatter.string(from: NSNumber(value: v)) ?? "—"
    }

    static func actionLabel(_ action: String) -> String {
        switch action.lowercased() {
        case "up":   return "Upgrade"
        case "down": return "Downgrade"
        case "main": return "Maintain"
        case "init": return "Initiate"
        case "reit": return "Reiterate"
        default:     return action.isEmpty ? "Update" : action.capitalized
        }
    }

    static func actionColor(_ action: String) -> Color {
        switch action.lowercased() {
        case "up":   return Color.ProfitGreen
        case "down": return Color.LossRed
        case "init": return Color.PrimaryYellow
        default:     return .secondary
        }
    }

    static func ptColor(_ dir: AnalystRatingRow.PTDirection) -> Color {
        switch dir {
        case .up:   return Color.ProfitGreen
        case .down: return Color.LossRed
        default:    return .primary
        }
    }
}
