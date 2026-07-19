//
//  PortfolioDailyCard.swift
//  SahamIndo
//
//  Kartu "Portofolio Hari Ini" — narasi harian ("Explain My Portfolio Today")
//  yang di-generate backend + chip kontributor penopang/penekan.
//

import SwiftUI

struct PortfolioDailyCard: View {

    let health:      PortfolioHealth
    let isLoading:   Bool

    private let accent = Color.AccentGold
    private let green  = Color.ProfitGreen
    private let red    = Color.LossRed
    private let cardBg = Color.appCardBackground

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(accent)
                Text("Portofolio Hari Ini")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.primary)
                Spacer()
                if isLoading {
                    ProgressView().scaleEffect(0.7)
                }
            }

            Text(health.narasiHarian)
                .font(.system(size: 13))
                .foregroundColor(.primary.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)

            if !health.kontributorTeratas.isEmpty || !health.kontributorTerbawah.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(health.kontributorTeratas) { c in
                            contributorChip(c, positive: true)
                        }
                        ForEach(health.kontributorTerbawah) { c in
                            contributorChip(c, positive: false)
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.primary.opacity(0.08), lineWidth: 1))
        .padding(.horizontal, 16)
    }

    private func contributorChip(_ c: Contributor, positive: Bool) -> some View {
        let color = positive ? green : red
        return HStack(spacing: 4) {
            Image(systemName: positive ? "arrow.up.right" : "arrow.down.right")
                .font(.system(size: 9, weight: .bold))
            Text(c.symbol).font(.system(size: 11, weight: .bold))
            Text(String(format: "%+.1f%%", c.pctChange)).font(.system(size: 10, weight: .semibold))
        }
        .foregroundColor(color)
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
    }
}
