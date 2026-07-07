//
//  AIInsightCard.swift
//  StockAppTryNew
//
//  Wrapper ringkas yang dipakai di StockDetailView:
//      AIInsightCard(symbol: viewModel.item.symbol)
//
//  Komponen ini membuat chips insight per-emiten secara lokal,
//  lalu mendelegasikan rendering ke AIInsightCardView.
//

import SwiftUI

// MARK: - AIInsightCard

struct AIInsightCard: View {

    let symbol: String

    /// Chips di-generate sekali saat init, deterministik berdasarkan symbol.
    private let chips: [InsightChip]

    init(symbol: String) {
        self.symbol = symbol
        self.chips  = Self.makeChips(for: symbol)
    }

    var body: some View {
        AIInsightCardView(chips: chips)
    }

    // MARK: - Chip Generator

    private static func makeChips(for symbol: String) -> [InsightChip] {
        [
            InsightChip(
                label: "Analisis Teknikal",
                text:  technicalText(for: symbol)
            ),
            InsightChip(
                label: "Sentimen Berita",
                text:  newsText(for: symbol)
            ),
            InsightChip(
                label: "Fundamental",
                text:  fundamentalText(for: symbol)
            ),
        ]
    }

    // MARK: - Text Templates (deterministik, bervariasi per-symbol)

    private static func technicalText(for symbol: String) -> String {
        let seed = symbolSeed(symbol)
        let rsi  = 42 + (seed % 30)           // 42–71
        let ma   = seed % 2 == 0 ? "di atas" : "di bawah"
        let vol  = seed % 3 == 0 ? "meningkat signifikan" : (seed % 3 == 1 ? "stabil" : "menurun tipis")
        let bias = seed % 2 == 0 ? "**bullish**" : "**bearish**"

        return """
        **\(symbol)** saat ini menunjukkan RSI \(rsi), mengindikasikan momentum \(bias). \
        Harga berada \(ma) MA-20 dengan volume \(vol) dalam 5 sesi terakhir. \
        Support kuat teridentifikasi di area Fibonacci retracement 0.618, \
        sementara resistance terdekat ada di level pivot mingguan. \
        Pola candlestick terbaru memberi sinyal \(seed % 2 == 0 ? "potensi breakout" : "konsolidasi jangka pendek").
        """
    }

    private static func newsText(for symbol: String) -> String {
        let seed    = symbolSeed(symbol)
        let tone    = seed % 3 == 0 ? "**positif**" : (seed % 3 == 1 ? "**netral**" : "**mixed**")
        let topic   = seed % 4 == 0 ? "ekspansi bisnis ke pasar baru"
                    : seed % 4 == 1 ? "rilis laporan keuangan kuartal terbaru"
                    : seed % 4 == 2 ? "pengumuman dividen interim"
                    : "kontrak strategis dengan mitra internasional"

        return """
        Sentimen berita seputar **\(symbol)** dalam 7 hari terakhir cenderung \(tone). \
        Headline utama terkait \(topic) mendapat respons pasar yang beragam. \
        Analis menilai prospek jangka menengah masih didukung oleh fundamental sektor \
        yang solid. Tidak ada isu material negatif yang berpotensi menekan harga secara signifikan.
        """
    }

    private static func fundamentalText(for symbol: String) -> String {
        let seed = symbolSeed(symbol)
        let per  = String(format: "%.1f", 8.0 + Double(seed % 120) / 10.0)  // 8–20x
        let pbv  = String(format: "%.2f", 0.8 + Double(seed % 30)  / 10.0)  // 0.8–3.8x
        let roe  = 10 + (seed % 18)                                          // 10–27%
        let div  = String(format: "%.1f", 1.5 + Double(seed % 35)  / 10.0)  // 1.5–5%

        return """
        Secara fundamental, **\(symbol)** diperdagangkan pada PER \(per)x dan PBV \(pbv)x — \
        \(seed % 2 == 0 ? "relatif murah" : "wajar") dibanding rata-rata sektoral. \
        ROE tercatat \(roe)% dengan dividend yield \(div)%, mencerminkan \
        \(seed % 2 == 0 ? "kemampuan generasi kas yang kuat" : "profitabilitas yang stabil"). \
        Neraca perusahaan terlihat sehat dengan DER di bawah 1x. \
        Pertumbuhan revenue YoY positif menjadi katalis utama jangka panjang.
        """
    }

    /// Seed numerik sederhana dari string symbol untuk variasi deterministik.
    private static func symbolSeed(_ symbol: String) -> Int {
        symbol.unicodeScalars.reduce(0) { $0 + Int($1.value) }
    }
}
