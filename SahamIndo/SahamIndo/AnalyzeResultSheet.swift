//
//  AnalyzeResultSheet.swift
//  SahamIndo
//
//  Bottom sheet yang muncul setelah tombol "Analyze" selesai.
//  Menampilkan skor total AI, breakdown komponen, rekomendasi,
//  narasi alasan, dan tombol "Tambah ke Watchlist".
//

import SwiftUI

struct AnalyzeResultSheet: View {

    let result: AnalyzeResult
    /// (kode, addToWatchlist: Bool)
    let onWatchlistAction: (String, Bool) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    headerCard
                    scoreBreakdownCard
                    if let alasan = result.alasan, !alasan.isEmpty {
                        alasanCard(alasan)
                    }
                    watchlistButton
                }
                .padding()
            }
            .background(Color.DarkPurpleAppBackground.ignoresSafeArea())
            .navigationTitle("Hasil Analisis AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Tutup") { dismiss() }
                        .foregroundColor(Color.PrimaryYellow)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Header

    private var headerCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                MarketBadge(market: result.market)
                Text(result.kode)
                    .font(.title2.bold())
                Spacer()
            }

            // Skor total gauge
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 14)
                Circle()
                    .trim(from: 0, to: result.skorDisplay / 100)
                    .stroke(sentimentColor, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.8), value: result.skorDisplay)
                VStack(spacing: 2) {
                    Text(String(format: "%.0f", result.skorDisplay))
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                    Text("/ 100").font(.caption).foregroundColor(.secondary)
                }
            }
            .frame(width: 120, height: 120)

            // Rekomendasi pill
            if let rek = result.rekomendasi {
                Text(rek.uppercased())
                    .font(.caption.bold())
                    .padding(.horizontal, 16).padding(.vertical, 6)
                    .background(sentimentColor.opacity(0.20))
                    .foregroundColor(sentimentColor)
                    .clipShape(Capsule())
            }
        }
        .padding()
        .background(Color(.systemGray6).opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Score Breakdown

    private var scoreBreakdownCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Breakdown Skor").font(.headline).foregroundColor(.primary)

            ScoreBar(label: "Fundamental", value: result.skorFundamental, color: .blue)
            ScoreBar(label: "Sentimen",    value: result.skorSentimen,    color: .orange)
            ScoreBar(label: "Teknikal",    value: result.skorTeknikal,    color: .green)
            ScoreBar(label: "Risiko",      value: result.skorRisiko,      color: .red)
        }
        .padding()
        .background(Color(.systemGray6).opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Alasan AI

    private func alasanCard(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Narasi AI", systemImage: "text.bubble")
                .font(.headline)
            Text(text)
                .font(.callout)
                .foregroundColor(.secondary)
                .lineSpacing(4)
        }
        .padding()
        .background(Color(.systemGray6).opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Watchlist Button

    private var watchlistButton: some View {
        Button {
            onWatchlistAction(result.kode, !result.isWatchlist)
            dismiss()
        } label: {
            Label(
                result.isWatchlist ? "Hapus dari Watchlist" : "Tambah ke Watchlist",
                systemImage: result.isWatchlist ? "star.slash.fill" : "star.fill"
            )
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding()
            .background(result.isWatchlist ? Color(.systemGray5) : Color.PrimaryYellow)
            .foregroundColor(result.isWatchlist ? .secondary : .black)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .padding(.top, 4)
    }

    // MARK: - Helpers

    private var sentimentColor: Color {
        switch result.sentimentType {
        case .recommended: return .green
        case .caution:     return .red
        case .neutral:     return Color.PrimaryYellow
        }
    }
}

// MARK: - ScoreBar

private struct ScoreBar: View {
    let label: String
    let value: Double?
    let color: Color

    private var safeValue: Double { min(max(value ?? 0, 0), 100) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.caption).foregroundColor(.secondary)
                Spacer()
                Text(value != nil ? String(format: "%.1f", safeValue) : "–")
                    .font(.caption.bold()).foregroundColor(.primary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.08))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color.opacity(0.7))
                        .frame(width: geo.size.width * (safeValue / 100))
                        .animation(.easeInOut(duration: 0.6), value: safeValue)
                }
            }
            .frame(height: 6)
        }
    }
}
