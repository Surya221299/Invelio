//
//  MiniSparklineView.swift
//  StockAppTryNew
//
//  Created by Surya on 16/06/26.
//

import SwiftUI
import Combine

// MARK: - MiniSparklineViewModel

@MainActor
final class MiniSparklineViewModel: ObservableObject {
    @Published private(set) var dataPoints: [StockDataPoint] = []

    private let chartRepository: ChartRepositoryProtocol

    init(chartRepository: ChartRepositoryProtocol) {
        self.chartRepository = chartRepository
    }

    func fetch(symbol: String) async {
        let (points, _) = await chartRepository.fetchCandles(symbol: symbol, range: .oneDay)
        dataPoints = normalizeToSlots(points)
    }

    // MARK: - Live price derived from candle data (same source as StockDetailView)

    /// Last candle close — matches what StockDetailView shows as latestPrice.
    var livePrice: Double { dataPoints.last?.close ?? 0 }

    /// Change from first candle (open of session) to last candle.
    var liveChange: Double { livePrice - (dataPoints.first?.close ?? livePrice) }

    /// Percent change from open of session.
    var livePctChange: Double {
        let open = dataPoints.first?.close ?? 0
        guard open > 0 else { return 0 }
        return (liveChange / open) * 100
    }

    // MARK: - Slot helpers (mirrors StockDetailViewModel exactly)

    // Total slot aktif bursa IDX per hari:
    //   Senin–Kamis: 09:00–12:00 (36 slot) + 13:30–15:55 (30 slot) + slot 15:55 = 67 slot
    //   Jumat      : 09:00–11:20 (28 slot) + 13:55–15:55 (25 slot) + slot 15:55 = 54 slot
    // StockDetailViewModel memakai konstanta tunggal 87 slot dengan mapping
    // "menit aktif" → slot. Kita gunakan pendekatan yang sama supaya X-koordinat identik.

    @Published private(set) var totalSlots: Int = 87
    private var openDate: Date?

    func slotIndex(for date: Date) -> Int {
        guard let open = openDate else { return 0 }
        let minutes = date.timeIntervalSince(open) / 60.0
        return max(0, min(Int(minutes / 5.0), totalSlots - 1))
    }

    private func normalizeToSlots(_ candles: [StockDataPoint]) -> [StockDataPoint] {
        guard !candles.isEmpty else { return [] }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Jakarta")!
        let now = Date()
        
        let startCandle = candles[0].date
        let openHour = cal.component(.hour, from: startCandle)
        let isUS = openHour >= 19 || openHour < 5
        let tSlots = isUS ? 79 : 87
        
        self.totalSlots = tSlots
        self.openDate = startCandle
        
        var slots: [StockDataPoint?] = Array(repeating: nil, count: tSlots)

        for candle in candles {
            let idx = slotIndex(for: candle.date)
            guard idx >= 0, idx < tSlots else { continue }
            slots[idx] = candle
        }

        let currentSlotIdx: Int
        if isUS {
            let hoursSinceOpen = now.timeIntervalSince(startCandle) / 3600.0
            if hoursSinceOpen >= 0 && hoursSinceOpen < 16 {
                let minutes = now.timeIntervalSince(startCandle) / 60.0
                currentSlotIdx = max(0, min(Int(minutes / 5.0), tSlots - 1))
            } else {
                currentSlotIdx = tSlots - 1
            }
        } else {
            if cal.isDate(startCandle, inSameDayAs: now) {
                let minutes = now.timeIntervalSince(startCandle) / 60.0
                currentSlotIdx = max(0, min(Int(minutes / 5.0), tSlots - 1))
            } else {
                currentSlotIdx = tSlots - 1
            }
        }

        for i in stride(from: 1, through: currentSlotIdx, by: 1) {
            if slots[i] == nil, let prev = slots[i - 1] {
                let slotDate = startCandle.addingTimeInterval(TimeInterval(i * 5 * 60))
                slots[i] = StockDataPoint(date: slotDate, close: prev.close, open: prev.close,
                                          high: prev.close, low: prev.close, volume: 0)
            }
        }
        return slots[0...currentSlotIdx].compactMap { $0 }
    }
}

// MARK: - MiniSparklineView

struct MiniSparklineView: View {

    @ObservedObject var vm: MiniSparklineViewModel

    private let green = Color.ProfitGreen
    private let red   = Color.LossRed

    @State private var pulseScale: CGFloat = 1.0

    // MARK: - Market Active Detection

    private var isMarketActive: Bool {
        guard let firstPoint = vm.dataPoints.first else { return false }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Jakarta")!
        let now = Date()
        let weekday = cal.component(.weekday, from: now)
        guard weekday >= 2 && weekday <= 6 else { return false }
        let openHour = cal.component(.hour, from: firstPoint.date)
        let isUS     = openHour >= 19 || openHour < 5
        let nowH     = cal.component(.hour,   from: now)
        let nowM     = cal.component(.minute, from: now)
        let nowMins  = nowH * 60 + nowM
        if isUS {
            return nowMins >= 20 * 60 || nowMins <= 5 * 60 + 30
        } else {
            return nowMins >= 9 * 60 && nowMins < 16 * 60
        }
    }

    private func updatePulse() {
        guard isMarketActive else { pulseScale = 1.0; return }
        pulseScale = 1.0
        withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
            pulseScale = 2.4
        }
    }

    var body: some View {
        let points      = vm.dataPoints
        let totalSlots  = vm.totalSlots
        let slotIndices = points.map { vm.slotIndex(for: $0.date) }

        ZStack(alignment: .topLeading) {
            Canvas { ctx, size in
                guard points.count > 1 else { return }
                let closes   = points.map(\.close)
                let startVal = closes[0]
                let minVal   = closes.min()!
                let maxVal   = closes.max()!
                let range    = max(maxVal - minVal, 1)
                let w = size.width; let h = size.height; let padV: CGFloat = 4
                let usableH  = h - padV * 2

                func xFor(_ i: Int) -> CGFloat {
                    CGFloat(slotIndices[i]) / CGFloat(totalSlots - 1) * w
                }
                func yFor(_ v: Double) -> CGFloat { padV + usableH * (1 - (v - minVal) / range) }

                let startY = yFor(startVal)

                let pts: [CGPoint] = (0..<closes.count).map { i in
                    CGPoint(x: xFor(i), y: yFor(closes[i]))
                }
                let tension: CGFloat = 0.33

                func buildArea(closeY: CGFloat) -> Path {
                    var p = Path()
                    guard !pts.isEmpty else { return p }
                    p.move(to: CGPoint(x: pts[0].x, y: closeY))
                    p.addLine(to: pts[0])
                    for i in 1..<pts.count {
                        let p0 = pts[max(i - 2, 0)]
                        let p1 = pts[i - 1]
                        let p2 = pts[i]
                        let p3 = pts[min(i + 1, pts.count - 1)]
                        let cp1 = CGPoint(x: p1.x + (p2.x - p0.x) * tension,
                                          y: p1.y + (p2.y - p0.y) * tension)
                        let cp2 = CGPoint(x: p2.x - (p3.x - p1.x) * tension,
                                          y: p2.y - (p3.y - p1.y) * tension)
                        p.addCurve(to: p2, control1: cp1, control2: cp2)
                    }
                    p.addLine(to: CGPoint(x: pts.last!.x, y: closeY))
                    p.closeSubpath()
                    return p
                }

                func buildLine() -> Path {
                    var p = Path()
                    guard !pts.isEmpty else { return p }
                    p.move(to: pts[0])
                    for i in 1..<pts.count {
                        let p0 = pts[max(i - 2, 0)]
                        let p1 = pts[i - 1]
                        let p2 = pts[i]
                        let p3 = pts[min(i + 1, pts.count - 1)]
                        let cp1 = CGPoint(x: p1.x + (p2.x - p0.x) * tension,
                                          y: p1.y + (p2.y - p0.y) * tension)
                        let cp2 = CGPoint(x: p2.x - (p3.x - p1.x) * tension,
                                          y: p2.y - (p3.y - p1.y) * tension)
                        p.addCurve(to: p2, control1: cp1, control2: cp2)
                    }
                    return p
                }

                let lineStyle = StrokeStyle(lineWidth: 0.6, lineCap: .round, lineJoin: .round)
                let line = buildLine()

                ctx.drawLayer { layer in
                    layer.clip(to: Path(CGRect(x: 0, y: 0, width: w, height: startY)))
                    layer.fill(buildArea(closeY: startY), with: .linearGradient(
                        Gradient(stops: [.init(color: green.opacity(0.18), location: 0),
                                         .init(color: green.opacity(0.06), location: 1)]),
                        startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: startY)))
                    layer.stroke(line, with: .color(green), style: lineStyle)
                }
                ctx.drawLayer { layer in
                    layer.clip(to: Path(CGRect(x: 0, y: startY, width: w, height: h - startY)))
                    layer.fill(buildArea(closeY: h), with: .linearGradient(
                        Gradient(stops: [.init(color: red.opacity(0.18), location: 0),
                                         .init(color: red.opacity(0.04), location: 1)]),
                        startPoint: CGPoint(x: 0, y: startY), endPoint: CGPoint(x: 0, y: h)))
                    layer.stroke(line, with: .color(red), style: lineStyle)
                }

                let lastY      = yFor(closes.last!)
                let lastColor  = closes.last! >= startVal ? green : red
                var dash = Path()
                dash.move(to: CGPoint(x: 0, y: lastY)); dash.addLine(to: CGPoint(x: w, y: lastY))
                ctx.stroke(dash, with: .color(lastColor.opacity(0.5)),
                           style: StrokeStyle(lineWidth: 0.75, dash: [3, 3]))
                let dotX = xFor(closes.count - 1); let dotR: CGFloat = 2.5
                ctx.fill(Path(ellipseIn: CGRect(x: dotX-dotR, y: lastY-dotR, width: dotR*2, height: dotR*2)),
                         with: .color(lastColor))
            }

            // Pulse overlay — Canvas can't animate, so we layer a SwiftUI Circle on top.
            // Only visible when market is active.
            if points.count > 1, isMarketActive {
                GeometryReader { geo in
                    let closes   = points.map(\.close)
                    let minVal   = closes.min()!
                    let maxVal   = closes.max()!
                    let valRange = max(maxVal - minVal, 1)
                    let h        = geo.size.height
                    let padV: CGFloat = 4
                    let usableH  = h - padV * 2
                    let w        = geo.size.width
                    let dotX     = CGFloat(slotIndices.last ?? 0) / CGFloat(max(totalSlots - 1, 1)) * w
                    let lastY    = padV + usableH * CGFloat(1 - (closes.last! - minVal) / valRange)
                    let dotColor = closes.last! >= closes.first! ? green : red

                    Circle()
                        .fill(dotColor.opacity(0.25))
                        .frame(width: 5 * pulseScale, height: 5 * pulseScale)
                        .position(x: dotX, y: lastY)
                }
            }
        }
        .task(id: vm.dataPoints.count) { updatePulse() }
        .onChange(of: vm.dataPoints) { _, _ in updatePulse() }
    }
}
