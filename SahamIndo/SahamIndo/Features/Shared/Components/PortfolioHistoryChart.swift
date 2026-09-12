//
//  PortfolioHistoryChart.swift
//  StockAppTryNew
//
//  Area chart untuk menampilkan riwayat nilai portofolio / kepemilikan saham.
//  Menggunakan Canvas (tanpa Charts framework) agar kompatibel iOS 15+.
//

import SwiftUI

// MARK: - PortfolioHistoryChart

struct PortfolioHistoryChart: View {

    let data: [PortfolioValuePoint]

    // Warna
    private let textSec  = Color.secondary

    // Tinggi canvas
    private let chartHeight: CGFloat = 160

    // MARK: - Derived

    private var values: [Double] { data.map(\.value) }
    private var firstValue: Double { values.first ?? 0 }
    private var lastValue:  Double { values.last  ?? 0 }
    private var minVal:     Double { values.min() ?? 0 }
    private var maxVal:     Double { values.max() ?? 1 }
    private var isPositive: Bool   { lastValue >= firstValue }

    private var lineColor: Color { isPositive ? Color.ProfitGreen : Color.LossRed }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Nilai saat ini + perubahan
            headerRow

            // Canvas chart
            Canvas { ctx, size in
                drawChart(ctx: ctx, size: size)
            }
            .frame(height: chartHeight)

            // Label sumbu X
            xAxisLabels
        }
        .padding(14)
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(formatIDR(lastValue))
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.primary)

            let delta    = lastValue - firstValue
            let deltaPct = firstValue > 0 ? (delta / firstValue) * 100 : 0
            HStack(spacing: 3) {
                Image(systemName: isPositive ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: 10, weight: .bold))
                Text(String(format: "%+.2f%%", deltaPct))
                    .font(.system(size: 12, weight: .bold))
            }
            .foregroundColor(lineColor)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(lineColor.opacity(0.12))
            .clipShape(Capsule())

            Spacer()
        }
    }

    // MARK: - X-Axis Labels

    private var xAxisLabels: some View {
        HStack {
            Text(shortDate(data.first?.date))
                .font(.system(size: 9)).foregroundColor(textSec)
            Spacer()
            if data.count > 2 {
                Text(shortDate(data[data.count / 2].date))
                    .font(.system(size: 9)).foregroundColor(textSec)
            }
            Spacer()
            Text(shortDate(data.last?.date))
                .font(.system(size: 9)).foregroundColor(textSec)
        }
    }

    // MARK: - Canvas Drawing

    private func drawChart(ctx: GraphicsContext, size: CGSize) {
        guard values.count > 1 else { return }

        let w       = size.width
        let h       = size.height
        let padV:   CGFloat = 4
        let usableH = h - padV * 2
        let range   = max(maxVal - minVal, 1)

        func xFor(_ i: Int) -> CGFloat {
            CGFloat(i) / CGFloat(values.count - 1) * w
        }
        func yFor(_ v: Double) -> CGFloat {
            padV + usableH * CGFloat(1 - (v - minVal) / range)
        }

        // --- Area fill (gradient) ---
        var area = Path()
        area.move(to: CGPoint(x: xFor(0), y: h))
        area.addLine(to: CGPoint(x: xFor(0), y: yFor(values[0])))
        for i in 1..<values.count {
            let px = xFor(i - 1); let py = yFor(values[i - 1])
            let cx = xFor(i);     let cy = yFor(values[i])
            let cpX = px + (cx - px) * 0.5
            area.addCurve(
                to:       CGPoint(x: cx, y: cy),
                control1: CGPoint(x: cpX, y: py),
                control2: CGPoint(x: cpX, y: cy)
            )
        }
        area.addLine(to: CGPoint(x: xFor(values.count - 1), y: h))
        area.closeSubpath()

        ctx.fill(area, with: .linearGradient(
            Gradient(stops: [
                .init(color: lineColor.opacity(0.25), location: 0),
                .init(color: lineColor.opacity(0.02), location: 1)
            ]),
            startPoint: CGPoint(x: 0, y: 0),
            endPoint:   CGPoint(x: 0, y: h)
        ))

        // --- Line ---
        var line = Path()
        line.move(to: CGPoint(x: xFor(0), y: yFor(values[0])))
        for i in 1..<values.count {
            let px = xFor(i - 1); let py = yFor(values[i - 1])
            let cx = xFor(i);     let cy = yFor(values[i])
            let cpX = px + (cx - px) * 0.5
            line.addCurve(
                to:       CGPoint(x: cx, y: cy),
                control1: CGPoint(x: cpX, y: py),
                control2: CGPoint(x: cpX, y: cy)
            )
        }
        ctx.stroke(line, with: .color(lineColor),
                   style: StrokeStyle(lineWidth: 0.6, lineCap: .round, lineJoin: .round))

        // --- Garis horizontal baseline (nilai pertama) ---
        let baseY = yFor(firstValue)
        var dash  = Path()
        dash.move(to: CGPoint(x: 0, y: baseY))
        dash.addLine(to: CGPoint(x: w, y: baseY))
        ctx.stroke(dash, with: .color(lineColor.opacity(0.35)),
                   style: StrokeStyle(lineWidth: 0.8, dash: [4, 4]))

        // --- Dot terakhir ---
        let lastX  = xFor(values.count - 1)
        let lastY  = yFor(values.last!)
        let dotR:  CGFloat = 4
        ctx.fill(
            Path(ellipseIn: CGRect(x: lastX - dotR, y: lastY - dotR,
                                   width: dotR * 2, height: dotR * 2)),
            with: .color(lineColor)
        )
        // Ring luar
        ctx.stroke(
            Path(ellipseIn: CGRect(x: lastX - dotR - 2, y: lastY - dotR - 2,
                                   width: (dotR + 2) * 2, height: (dotR + 2) * 2)),
            with: .color(lineColor.opacity(0.35)),
            style: StrokeStyle(lineWidth: 1.2)
        )
    }

    // MARK: - Helpers

    private func shortDate(_ date: Date?) -> String {
        guard let date else { return "" }
        let f = DateFormatter()
        f.locale     = Locale(identifier: "id_ID")
        f.dateFormat = "d MMM"
        return f.string(from: date)
    }
}
