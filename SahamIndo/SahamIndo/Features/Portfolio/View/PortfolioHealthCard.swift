//
//  PortfolioHealthCard.swift
//  SahamIndo
//
//  Kartu "Kesehatan Portofolio" — skor kesehatan (ring), alokasi sektor,
//  peringatan konsentrasi, dan saran rebalancing. Semua nilai explainable
//  (dihitung backend dari holdings user).
//

import SwiftUI

struct PortfolioHealthCard: View {

    let health: PortfolioHealth

    private let green  = Color.ProfitGreen
    private let gold   = Color.AccentGold
    private let red    = Color.LossRed
    private let cardBg = Color.appCardBackground

    // Warna berdasarkan skor kesehatan
    private var healthColor: Color {
        switch health.skorKesehatan {
        case 70...:  return green
        case 45..<70: return gold
        default:      return red
        }
    }

    private var riskColor: Color {
        switch health.levelRisiko {
        case "Rendah": return green
        case "Sedang": return gold
        default:       return red
        }
    }

    // Palet stabil untuk bar alokasi sektor
    private let sectorPalette: [Color] = [
        Color(hex: "6366F1"), Color(hex: "22C55E"), Color(hex: "EAB308"),
        Color(hex: "EC4899"), Color(hex: "06B6D4"), Color(hex: "F97316"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            scoreRow
            if !health.alokasiSektor.isEmpty { sektorSection }
            if !health.flags.isEmpty { flagsSection }
            if !health.saranRebalancing.isEmpty { saranSection }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.primary.opacity(0.08), lineWidth: 1))
        .padding(.horizontal, 16)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "heart.text.square.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(healthColor)
            Text("Kesehatan Portofolio")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.primary)
            Spacer()
            Text(health.levelRisiko)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(riskColor)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(riskColor.opacity(0.14))
                .clipShape(Capsule())
        }
    }

    // MARK: - Score ring + key stats

    private var scoreRow: some View {
        HStack(spacing: 18) {
            ring
            VStack(alignment: .leading, spacing: 8) {
                statLine(label: "Diversifikasi", value: "\(Int(health.skorDiversifikasi))/100")
                statLine(label: "Emiten", value: "\(health.jumlahEmiten)")
                statLine(label: "Sektor", value: "\(health.jumlahSektor)")
            }
            Spacer()
        }
    }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.08), lineWidth: 8)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, health.skorKesehatan / 100)))
                .stroke(healthColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(Int(health.skorKesehatan))")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                Text("/100").font(.system(size: 9)).foregroundColor(.secondary)
            }
        }
        .frame(width: 78, height: 78)
    }

    private func statLine(label: String, value: String) -> some View {
        HStack(spacing: 6) {
            Text(label).font(.system(size: 11)).foregroundColor(.secondary)
            Spacer(minLength: 8)
            Text(value).font(.system(size: 12, weight: .bold)).foregroundColor(.primary)
        }
        .frame(width: 150)
    }

    // MARK: - Alokasi sektor

    private var sektorSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Alokasi Sektor")
                .font(.system(size: 12, weight: .semibold)).foregroundColor(.secondary)
            ForEach(Array(health.alokasiSektor.prefix(6).enumerated()), id: \.element.id) { idx, s in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(s.sektor).font(.system(size: 11, weight: .medium)).foregroundColor(.primary)
                        Spacer()
                        Text(String(format: "%.0f%%", s.persen))
                            .font(.system(size: 11, weight: .bold)).foregroundColor(.primary)
                    }
                    GeometryReader { geo in
                        let color = sectorPalette[idx % sectorPalette.count]
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.08))
                            Capsule().fill(color)
                                .frame(width: max(4, geo.size.width * CGFloat(s.persen / 100)))
                        }
                    }
                    .frame(height: 6)
                }
            }
        }
    }

    // MARK: - Flags peringatan

    private var flagsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(health.flags, id: \.self) { f in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10)).foregroundColor(gold)
                        .padding(.top, 1)
                    Text(f).font(.system(size: 11)).foregroundColor(.primary.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(gold.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Saran rebalancing

    private var saranSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Saran Rebalancing")
                .font(.system(size: 12, weight: .semibold)).foregroundColor(.secondary)
            ForEach(health.saranRebalancing, id: \.self) { s in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10)).foregroundColor(green)
                        .padding(.top, 1)
                    Text(s).font(.system(size: 11)).foregroundColor(.primary.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
