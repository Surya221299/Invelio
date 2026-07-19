//
//  FundamentalsCard.swift
//  SahamIndo
//
//  Kartu ringkasan fundamental emiten di halaman detail saham. Menampilkan 5
//  aspek untuk menilai kualitas & valuasi perusahaan:
//    1. Valuasi        — PER/PBV + interpretasi murah/wajar/mahal.
//    2. Profitabilitas — ROE & margin (patokan ROE >15% = kualitas baik).
//    3. Kesehatan      — DER + free cash flow (utang besar + FCF negatif = bahaya).
//    4. Pertumbuhan    — CAGR revenue + deret ~4 tahun.
//    5. Moat           — narasi keunggulan kompetitif (di-generate LLM lokal).
//
//  Data dari StockDetailViewModel.fundamentals / .moat (fetch sekali saat
//  halaman muncul). Angka yang tidak tersedia disembunyikan — banyak field
//  kosong untuk emiten IDX di yfinance.
//

import SwiftUI

struct FundamentalsCard: View {

    let fundamentals: CompanyFundamentals?
    let moat:         MoatInsight?

    var body: some View {
        // Sembunyikan seluruh kartu kalau tidak ada satupun data fundamental.
        if let f = fundamentals, !f.isEmpty {
            VStack(alignment: .leading, spacing: DesignSpacing.l) {
                header

                if f.hasValuation {
                    Divider().background(Color.primary.opacity(0.08))
                    valuationSection(f)
                }
                if f.hasProfitability {
                    Divider().background(Color.primary.opacity(0.08))
                    profitabilitySection(f)
                }
                if f.hasHealth {
                    Divider().background(Color.primary.opacity(0.08))
                    healthSection(f)
                }
                if f.hasGrowth {
                    Divider().background(Color.primary.opacity(0.08))
                    growthSection(f)
                }

                Divider().background(Color.primary.opacity(0.08))
                moatSection()

                Text("Fundamental bersifat indikatif — bandingkan PER/margin dengan rata-rata industrinya, bukan angka absolut.")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .padding(.top, DesignSpacing.xxs)
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
                .foregroundColor(Color.AccentIndigo)
            Text("Fundamental Perusahaan")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.primary)
            Spacer()
            if let sector = fundamentals?.sector, !sector.isEmpty {
                Text(sector)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
    }

    // MARK: - 1. Valuasi

    @ViewBuilder
    private func valuationSection(_ f: CompanyFundamentals) -> some View {
        section(icon: "tag.fill", title: "Valuasi",
                verdict: f.valuationVerdict, verdictLabel: f.valuationLabel) {
            metricRow("PER (trailing)", value: ratio(f.trailingPE), verdict: f.valuationVerdict)
            metricRow("PER (forward)",  value: ratio(f.forwardPE))
            metricRow("PBV",            value: ratio(f.pbv))
            metricRow("Dividend Yield", value: percent(f.dividendYield))
            metricRow("Market Cap",     value: money(f.marketCap, currency: f.currency))
        }
    }

    // MARK: - 2. Profitabilitas

    @ViewBuilder
    private func profitabilitySection(_ f: CompanyFundamentals) -> some View {
        section(icon: "flame.fill", title: "Profitabilitas",
                verdict: f.roeVerdict, verdictLabel: f.roeVerdict.label) {
            metricRow("ROE",              value: percent(f.roe), verdict: f.roeVerdict)
            metricRow("Net Margin",       value: percent(f.profitMargin), verdict: f.netMarginVerdict)
            metricRow("Gross Margin",     value: percent(f.grossMargin))
            metricRow("Operating Margin", value: percent(f.operatingMargin))
            Text("ROE ≥ 15% yang konsisten biasanya tanda perusahaan berkualitas. Margin \"bagus\" berbeda tiap industri.")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
    }

    // MARK: - 3. Kesehatan Keuangan

    @ViewBuilder
    private func healthSection(_ f: CompanyFundamentals) -> some View {
        section(icon: "cross.case.fill", title: "Kesehatan Keuangan",
                verdict: f.financialHealthVerdict, verdictLabel: f.financialHealthVerdict.label) {
            metricRow("DER (utang/ekuitas)", value: ratio(f.der))
            metricRow("Free Cash Flow",      value: money(f.freeCashFlow, currency: f.currency),
                      verdict: fcfVerdict(f.freeCashFlow))
            metricRow("Operating Cash Flow", value: money(f.operatingCashFlow, currency: f.currency))
            Text("Utang besar masih aman selama arus kas positif; utang besar + arus kas negatif = berbahaya.")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
    }

    // MARK: - 4. Pertumbuhan

    @ViewBuilder
    private func growthSection(_ f: CompanyFundamentals) -> some View {
        section(icon: "chart.line.uptrend.xyaxis", title: "Pertumbuhan",
                verdict: f.growthVerdict, verdictLabel: f.growthVerdict.label) {
            if f.revenueCAGR != nil {
                metricRow("Revenue CAGR (\(f.annualGrowth.count) thn)",
                          value: percent(f.revenueCAGR), verdict: f.growthVerdict)
            }
            metricRow("Revenue Growth (YoY)", value: percent(f.revenueGrowth))
            metricRow("Earnings Growth (YoY)", value: percent(f.earningsGrowth))

            if f.annualGrowth.count >= 2 {
                VStack(alignment: .leading, spacing: DesignSpacing.xs) {
                    ForEach(f.annualGrowth) { row in
                        HStack {
                            Text(String(row.year))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.secondary)
                                .frame(width: 44, alignment: .leading)
                            Text(money(row.revenue, currency: f.currency))
                                .font(.system(size: 12))
                                .foregroundColor(.primary.opacity(0.85))
                            Spacer()
                            if let ni = row.netIncome {
                                Text("Laba \(money(ni, currency: f.currency))")
                                    .font(.system(size: 11))
                                    .foregroundColor(ni >= 0 ? Color.ProfitGreen : Color.LossRed)
                            }
                        }
                    }
                }
                .padding(.top, DesignSpacing.xxs)
                Text("Pertumbuhan konsisten lebih bernilai daripada satu tahun melonjak tajam.")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - 5. Moat

    @ViewBuilder
    private func moatSection() -> some View {
        VStack(alignment: .leading, spacing: DesignSpacing.s) {
            HStack(spacing: DesignSpacing.s) {
                Image(systemName: "shield.lefthalf.filled")
                    .foregroundColor(Color.AccentGold)
                Text("Business Moat")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary.opacity(0.9))
            }
            if let text = moat?.moatText, !text.isEmpty {
                Text(text)
                    .font(.system(size: 12))
                    .foregroundColor(.primary.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                Text("Penilaian AI — bukan rekomendasi beli/jual.")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            } else if moat == nil {
                HStack(spacing: DesignSpacing.s) {
                    ProgressView().scaleEffect(0.7)
                    Text("Menganalisis keunggulan kompetitif…")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            } else {
                Text("Analisis moat belum tersedia untuk emiten ini.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Reusable subviews

    @ViewBuilder
    private func section<Content: View>(
        icon: String, title: String,
        verdict: FundamentalVerdict, verdictLabel: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignSpacing.m) {
            HStack(spacing: DesignSpacing.s) {
                Image(systemName: icon)
                    .foregroundColor(color(for: verdict))
                    .font(.system(size: 13))
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary.opacity(0.9))
                Spacer()
                if verdict != .unknown {
                    verdictPill(verdictLabel, verdict: verdict)
                }
            }
            content()
        }
    }

    /// Satu baris metrik: label kiri, nilai kanan, opsional pill verdict.
    /// Disembunyikan otomatis kalau nilainya "-" (data tidak tersedia).
    @ViewBuilder
    private func metricRow(_ label: String, value: String,
                           verdict: FundamentalVerdict? = nil) -> some View {
        if value != "-" {
            HStack {
                Text(label)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Spacer()
                Text(value)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                if let verdict, verdict != .unknown {
                    verdictPill(verdict.label, verdict: verdict)
                }
            }
        }
    }

    private func verdictPill(_ text: String, verdict: FundamentalVerdict) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(color(for: verdict))
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(color(for: verdict).opacity(0.14))
            .cornerRadius(5)
    }

    private func color(for verdict: FundamentalVerdict) -> Color {
        switch verdict {
        case .good:    return Color.ProfitGreen
        case .fair:    return Color.AccentGold
        case .weak:    return Color.LossRed
        case .unknown: return .secondary
        }
    }

    private func fcfVerdict(_ v: Double?) -> FundamentalVerdict {
        guard let v else { return .unknown }
        return v >= 0 ? .good : .weak
    }

    // MARK: - Formatting

    private func ratio(_ v: Double?) -> String {
        guard let v else { return "-" }
        return String(format: "%.1fx", v)
    }

    private func percent(_ v: Double?) -> String {
        guard let v else { return "-" }
        return String(format: "%.1f%%", v * 100)
    }

    /// Nominal ringkas dengan simbol mata uang (Rp untuk IDR, $ untuk USD).
    private func money(_ v: Double?, currency: String?) -> String {
        guard let v else { return "-" }
        let symbol: String
        switch (currency ?? "").uppercased() {
        case "IDR": symbol = "Rp"
        case "USD": symbol = "$"
        case "":    symbol = ""
        default:    symbol = (currency ?? "") + " "
        }
        let sign = v < 0 ? "-" : ""
        let a = Swift.abs(v)
        let num: String
        if a >= 1_000_000_000_000 { num = String(format: "%.1fT", a / 1_000_000_000_000) }
        else if a >= 1_000_000_000 { num = String(format: "%.1fB", a / 1_000_000_000) }
        else if a >= 1_000_000     { num = String(format: "%.1fJt", a / 1_000_000) }
        else                        { num = String(format: "%.0f", a) }
        return "\(sign)\(symbol)\(num)"
    }
}
