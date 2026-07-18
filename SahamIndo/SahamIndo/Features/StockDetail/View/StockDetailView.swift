//
//  StockDetailView.swift
//  StockAppTryNew
//
//  Refactored: MVVM + Clean Architecture, Separation of Concerns, SOLID
//  View is purely declarative — all logic delegated to StockDetailViewModel.
//  ViewModel is injected via DIContainer (Dependency Inversion Principle).
//

import SwiftUI
import Combine

// MARK: - StockDetailView

struct StockDetailView: View {

    @ObservedObject var viewModel: StockDetailViewModel

    // Single source of truth (sama persis dengan yang dipakai HomeView).
    // Diobservasi LANGSUNG di sini (bukan cuma lewat viewModel.objectWillChange
    // forwarding) sebagai jaminan tambahan — nested @Published object di
    // dalam ObservableObject lain tidak selalu cascade re-render, jadi observe
    // langsung ke singleton-nya lebih pasti.
    @ObservedObject private var livePriceStore = LivePriceStore.shared

    @EnvironmentObject private var portfolioVM: PortfolioViewModel
    @EnvironmentObject private var router:      Router

    // Crosshair state (pure UI state — belongs in View)
    @State private var selectedPoint: StockDataPoint? = nil
    @State private var isDragging    = false
    @State private var chartSize:    CGSize = .zero

    // Sheet state
    @State private var showTradeSheet = false
    /// Tipe transaksi awal saat sheet dibuka (0 = Beli, 1 = Jual).
    @State private var initialTradeType = 0

    // MARK: - Computed display values (change during drag)

    /// Market saham ini — dipakai untuk format harga yang benar (IDX tanpa
    /// desimal, non-IDX 2 desimal). `detail` (async) diprioritaskan, fallback
    /// ke `item.market` yang sudah tersedia sejak awal.
    private var market: String { viewModel.detail?.market ?? viewModel.item.market }

    /// Data pre-market/after-hours dari LivePriceStore (sama sumbernya dengan
    /// harga streaming) — nil kalau market tidak didukung (IDX) atau lagi
    /// tidak dalam sesi pre/post-market.
    private var extendedHours: ExtendedHoursUpdate? {
        livePriceStore.price(for: viewModel.item.symbol)?.extendedHours
    }

    private var displayPrice: Double {
        // Saat drag di chart, ikut titik yang dipegang jari.
        // Kalau tidak sedang drag, pakai harga streaming (near-real-time)
        // dan fallback ke candle terakhir kalau stream belum konek.
        selectedPoint?.close ?? viewModel.streamedOrLatestPrice
    }
    private var displayChange: Double {
        guard isDragging else { return viewModel.streamedChange ?? viewModel.item.change }
        return displayPrice - viewModel.startPrice
    }
    private var displayChangePct: Double {
        guard isDragging else { return viewModel.streamedPctChange ?? viewModel.item.percentChange }
        guard viewModel.startPrice != 0 else { return 0 }
        return (displayChange / viewModel.startPrice) * 100
    }
    private var displayIsPositive: Bool { isDragging ? displayPrice >= viewModel.startPrice : displayChange >= 0 }
    private var accentColor: Color {
        displayIsPositive ? Color.ProfitGreen : Color.LossRed
    }

    private var currentHolding: Holding? {
        portfolioVM.holdings.first { $0.symbol == viewModel.item.symbol }
    }
    private var currentQty: Double { currentHolding?.quantity ?? 0 }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 12) {
                    StockDetailHeaderView(item: viewModel.item)
                        .padding(.horizontal)

                    PriceInfoView(
                        displayPrice:      displayPrice,
                        displayChange:     displayChange,
                        displayChangePct:  displayChangePct,
                        displayIsPositive: displayIsPositive,
                        accentColor:       accentColor,
                        selectedRange:     viewModel.selectedRange,
                        selectedPoint:     selectedPoint,
                        isDragging:        isDragging,
                        market:            market
                    )
                    .padding(.horizontal)
                    .animation(.easeInOut(duration: 0.1), value: isDragging)

                    // Badge pre-market/after-hours — cuma muncul untuk NASDAQ/NYSE/ETF
                    // dan cuma kalau memang sedang dalam sesi itu saat ini.
                    // Saat drag, badge cuma di-FADE (opacity 0), BUKAN dihapus dari
                    // tree — kalau dihapus, tinggi + spacing VStack hilang sehingga
                    // chart & view di bawahnya ikut melompat ke atas.
                    HStack {
                        ExtendedHoursBadgeView(data: extendedHours, style: .full)
                        Spacer()
                    }
                    .padding(.horizontal)
                    .opacity(isDragging ? 0 : 1)
                    .animation(.easeInOut(duration: 0.1), value: isDragging)

                    ChartCanvasView(
                        chartVM:           viewModel,
                        selectedPoint:     $selectedPoint,
                        isDragging:        $isDragging,
                        chartSize:         $chartSize,
                        accentColor:       accentColor,
                        displayIsPositive: displayIsPositive,
                        market:            market
                    )
                    .frame(height: 230)
                    .background(
                        GeometryReader { geo in
                            Color.clear
                                .onAppear { chartSize = geo.size }
                                .onChange(of: geo.size) { _, s in chartSize = s }
                        }
                    )
                    .padding(.horizontal, 8)

                    if !viewModel.dataPoints.isEmpty {
                        XAxisAnimatedLabels(
                            chartVM:   viewModel,
                            chartSize: chartSize
                        )
                        .padding(.horizontal, 8)
                        .padding(.top, -16)
                        .padding(.vertical, 6)
                    }

                    TimeRangeSelectorView(chartVM: viewModel) {
                        selectedPoint = nil
                        isDragging    = false
                    }
                    .padding(.horizontal)
                    .padding(.top, -16)

                    Divider().padding(.horizontal)

                    AIInsightCard(symbol: viewModel.item.symbol)
                        .padding(.horizontal)
                        .animation(.easeInOut(duration: 0.3), value: viewModel.item.symbol)

                    EarningsRallyCard(
                        earnings: viewModel.earningsInfo,
                        rally:    viewModel.rallyStreak
                    )
                    .padding(.horizontal)

                    AnalystRatingsCard(ratings: viewModel.analystRatings)
                        .padding(.horizontal)

                    Spacer(minLength: 20)
                }
                .padding(.vertical, 12)
            }
            tradeButtonBar
        }
        .background(Color.DarkPurpleAppBackground.ignoresSafeArea())
        .navigationTitle(viewModel.item.symbol)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .sheet(isPresented: $showTradeSheet) {
            TradeSheetView(stock: viewModel.item, initialTradeType: initialTradeType, lockTradeType: true)
                .presentationDetents([.large])
                .environmentObject(portfolioVM)
        }
        .task { await viewModel.fetchChartData() }
        .task { await viewModel.fetchEarningsAndRallyInfo() }
        .task { await viewModel.fetchAnalystRatings() }
        .onReceive(
            Timer.publish(every: 5 * 60, on: .main, in: .common).autoconnect()
        ) { _ in
            guard viewModel.selectedRange == .oneDay else { return }
            Task { await viewModel.fetchChartData() }
        }
        // Live price streaming: connect saat halaman muncul, putus saat pergi
        // supaya tidak ada koneksi WebSocket menggantung di background.
        .onAppear { viewModel.startPriceStream() }
        .onDisappear { viewModel.stopPriceStream() }
    }

    // MARK: - Sticky Trade Button Bar

    private var tradeButtonBar: some View {
        VStack(spacing: 0) {
            Divider().background(Color.primary.opacity(0.08))
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    // Jual — kiri. Disabled + redup kalau tidak punya saham.
                    let canSell = currentQty > 0
                    Button(action: { initialTradeType = 1; showTradeSheet = true }) {
                        Text("Jual")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(Color.LossRed)
                            .cornerRadius(8)
                    }
                    .disabled(!canSell)
                    .opacity(canSell ? 1.0 : 0.25)

                    // Buy — kanan.
                    Button(action: { initialTradeType = 0; showTradeSheet = true }) {
                        Text("Buy")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(Color.ProfitGreen)
                            .cornerRadius(8)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.appCardBackground)
        }
    }
}

// MARK: - Stock Detail Header

struct StockDetailHeaderView: View {

    let item: PortfolioItem

    var body: some View {
        HStack(spacing: 10) {
            StockAvatarView(symbol: item.symbol)
                .scaleEffect(1.1)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.symbol)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                Text(item.name ?? "-")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            SentimentPillView(sentiment: item.sentiment)
        }
        .padding(.top, 6)
    }
}

// MARK: - Price Info

struct PriceInfoView: View {

    let displayPrice:      Double
    let displayChange:     Double
    let displayChangePct:  Double
    let displayIsPositive: Bool
    let accentColor:       Color
    let selectedRange:     TimeRange
    let selectedPoint:     StockDataPoint?
    let isDragging:        Bool
    /// "IDX" | "NASDAQ" | "NYSE" | "ETF" — default "IDX" untuk backward-compat.
    var market:            String = "IDX"

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                RollingPriceView(price: displayPrice, fontSize: 34, isInteractive: isDragging, market: market)
                    .frame(height: 34 * 1.25)
                HStack(spacing: 6) {
                    HStack(spacing: 5) {
                        Image(systemName: displayIsPositive ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 11, weight: .bold))
                        Text("\(displayIsPositive ? "+" : "")\(formatPrice(displayChange, market: market))")
                            .font(.system(size: 13, weight: .semibold))
                        Text("(\(String(format: "%+.2f%%", displayChangePct)))")
                            .font(.system(size: 12, weight: .medium))
                            .opacity(0.85)
                    }
                    .foregroundColor(accentColor)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(accentColor.opacity(0.12))
                    .cornerRadius(6)

                    Text(selectedRange.rawValue)
                        .font(.system(size: 14, weight: .bold))
                }
            }
            Spacer()
            // kasi info perusahaan di sini...(next feature)
        }
    }

    private func formatDragDate(_ date: Date, range: TimeRange) -> String {
        let df = DateFormatter()
        df.locale     = Locale(identifier: "id_ID")
        df.timeZone   = TimeZone(identifier: "Asia/Jakarta")!
        df.dateFormat = range.isIntraday ? "d MMM 'pukul' HH:mm" : "d MMM yyyy"
        return df.string(from: date)
    }
}

// MARK: - MorphPoint (VectorArithmetic for chart morphing)

struct MorphPoint: VectorArithmetic, Sendable {
    var x: CGFloat
    var y: CGFloat

    static var zero: MorphPoint { .init(x: 0, y: 0) }

    static func + (lhs: Self, rhs: Self) -> Self { .init(x: lhs.x + rhs.x, y: lhs.y + rhs.y) }
    static func - (lhs: Self, rhs: Self) -> Self { .init(x: lhs.x - rhs.x, y: lhs.y - rhs.y) }

    mutating func scale(by rhs: Double) { x *= CGFloat(rhs); y *= CGFloat(rhs) }

    var magnitudeSquared: Double { Double(x * x + y * y) }
}

// MARK: - AnimatableChartData

struct AnimatableChartData: VectorArithmetic, Equatable, Sendable {

    var points: [MorphPoint]

    static var zero: Self { .init(points: []) }

    static func + (lhs: Self, rhs: Self) -> Self {
        let n = max(lhs.points.count, rhs.points.count)
        let lp = lhs.padded(to: n); let rp = rhs.padded(to: n)
        var result: [MorphPoint] = []; result.reserveCapacity(n)
        for i in 0..<n { result.append(lp[i] + rp[i]) }
        return .init(points: result)
    }

    static func - (lhs: Self, rhs: Self) -> Self {
        let n = max(lhs.points.count, rhs.points.count)
        let lp = lhs.padded(to: n); let rp = rhs.padded(to: n)
        var result: [MorphPoint] = []; result.reserveCapacity(n)
        for i in 0..<n { result.append(lp[i] - rp[i]) }
        return .init(points: result)
    }

    mutating func scale(by rhs: Double) { for i in points.indices { points[i].scale(by: rhs) } }

    var magnitudeSquared: Double { points.reduce(0) { $0 + $1.magnitudeSquared } }

    private func padded(to count: Int) -> [MorphPoint] {
        guard let last = points.last else { return Array(repeating: .zero, count: count) }
        if points.count >= count { return points }
        return points + Array(repeating: last, count: count - points.count)
    }
}

// MARK: - NormalizedChartData (kept for legacy shapes)

struct NormalizedChartData: VectorArithmetic, Equatable, Sendable {
    var values: [Double]

    static var zero: NormalizedChartData { .init(values: []) }

    static func + (lhs: NormalizedChartData, rhs: NormalizedChartData) -> NormalizedChartData {
        let n = max(lhs.values.count, rhs.values.count)
        guard n > 0 else { return .zero }
        return .init(values: (0..<n).map { i in
            (i < lhs.values.count ? lhs.values[i] : (lhs.values.last ?? 0)) +
            (i < rhs.values.count ? rhs.values[i] : (rhs.values.last ?? 0))
        })
    }

    static func - (lhs: NormalizedChartData, rhs: NormalizedChartData) -> NormalizedChartData {
        let n = max(lhs.values.count, rhs.values.count)
        guard n > 0 else { return .zero }
        return .init(values: (0..<n).map { i in
            (i < lhs.values.count ? lhs.values[i] : (lhs.values.last ?? 0)) -
            (i < rhs.values.count ? rhs.values[i] : (rhs.values.last ?? 0))
        })
    }

    mutating func scale(by rhs: Double) { values = values.map { $0 * rhs } }
    var magnitudeSquared: Double { values.reduce(0) { $0 + $1 * $1 } }
}

// MARK: - Chart Canvas View

struct ChartCanvasView<VM: ChartViewModelProtocol>: View {

    @ObservedObject var chartVM:    VM
    @Binding var selectedPoint:     StockDataPoint?
    @Binding var isDragging:        Bool
    @Binding var chartSize:         CGSize

    let accentColor:       Color
    let displayIsPositive: Bool
    /// When set, line + area gradient render in this single color instead of
    /// the default green-above / red-below split (used by the Portfolio chart).
    var fixedColor: Color? = nil
    /// When true, the first non-1D load plays a left→right clip reveal instead of
    /// a spring morph. Pass true for Portfolio; false (default) for StockDetailView.
    var revealOnFirstLoad: Bool = false
    /// "IDX" | "NASDAQ" | "NYSE" | "ETF" — dipakai untuk format label Max/Min.
    /// Default "IDX" supaya PortfolioHistoryChart (nilai portofolio, selalu
    /// Rupiah) tidak perlu diubah.
    var market: String = "IDX"
    /// Attach the scrub gesture as `.highPriorityGesture` instead of `.gesture`.
    /// Needed when the chart lives inside a clipped card nested in a vertical
    /// ScrollView (Portfolio card di HomeView) — di situ ScrollView memenangkan
    /// pan gesture sehingga crosshair tidak pernah aktif. StockDetail (chart
    /// langsung anak ScrollView) tetap pakai `.gesture` default.
    var useHighPriorityDrag: Bool = false

    @State private var animatedData:        AnimatableChartData = .zero
    @State private var oneDayReady:         Bool    = false
    @State private var oneDayClipWidth:     CGFloat = 0
    /// `true` setelah animasi reveal 1D (clip kiri→kanan) selesai. Selama masih
    /// `false`, dot aktif merambat mengikuti ujung garis (bukan diam di kanan).
    @State private var oneDayRevealDone:    Bool    = false
    @State private var hasEverLoadedOneDay: Bool    = false
    @State private var pulseScale:          CGFloat = 1.0
    /// Non-1D first-load reveal: clip slides left→right once, then stays full width.
    @State private var revealClipWidth:     CGFloat = 0
    @State private var hasRevealed:         Bool    = false
    /// Animated baseline Y — updated with the same spring as animatedData so
    /// AnimatableClipAbove/Below tracks the morph and never clips mid-transition.
    @State private var animatedBaselineY:   CGFloat = 0

    private let resampleCount = 300

    // MARK: - Market Active Detection

    /// Returns true if the market for the current data set is currently open.
    /// Works for both IDX (Mon–Fri 09:00–16:00 WIB) and US stocks
    /// (Mon–Fri ~20:30–05:00 WIB / varies by DST).
    /// Uses the first candle's open time to detect which market, then checks
    /// whether `now` falls within a reasonable active window.
    private var isMarketActive: Bool {
        guard let firstPoint = chartVM.dataPoints.first else { return false }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Jakarta")!
        let now = Date()

        // Must be a weekday (Mon=2 … Fri=6 in Gregorian, Sun=1, Sat=7)
        let weekday = cal.component(.weekday, from: now)
        guard weekday >= 2 && weekday <= 6 else { return false }

        let openHour = cal.component(.hour, from: firstPoint.date)
        let isUS     = openHour >= 19 || openHour < 5

        let nowH = cal.component(.hour,   from: now)
        let nowM = cal.component(.minute, from: now)
        let nowMins = nowH * 60 + nowM

        if isUS {
            // NYSE/NASDAQ: 09:30–16:00 ET
            // In WIB (UTC+7): WIB = ET + 12 (EDT) or ET + 13 (EST)
            // 09:30 ET → 21:30 WIB (EDT) / 22:30 WIB (EST)
            // 16:00 ET → 04:00 WIB (EDT) / 05:00 WIB (EST)
            // Simple window: 20:00–05:30 WIB (generous to cover both DST cases)
            return nowMins >= 20 * 60 || nowMins <= 5 * 60 + 30
        } else {
            // IDX: hanya "aktif" saat sesi benar-benar berjalan — buka, belum
            // tutup, DAN bukan jam istirahat siang. Selama istirahat pulse dot
            // berhenti karena tidak ada perdagangan.
            return IDXTradingCalendar.isSessionOpen(now)
        }
    }

    var body: some View {
        interactiveChart
        .onChange(of: chartVM.isLoading) { _, isLoading in
            guard !isLoading else { return }
            applyChartData()
        }
        // Fallback A: chartSize baru tersedia setelah data masuk (race condition awal).
        // Hanya aktif jika animatedData masih kosong (belum pernah render).
        .onChange(of: chartSize) { _, newSize in
            guard newSize.width > 0,
                  !chartVM.dataPoints.isEmpty,
                  animatedData.points.isEmpty   // sudah dirender → tidak perlu trigger ulang
            else { return }
            applyChartData()
        }
        // Fallback B: dataPoints berubah tapi chartSize sudah tersedia (data sinkron).
        .onChange(of: chartVM.dataPoints) { _, _ in
            guard chartSize.width > 0 else { return }
            applyChartData()
            updatePulse()
        }
        .onAppear { updatePulse() }
        .onChange(of: chartVM.selectedRange) { _, _ in updatePulse() }
    }

    /// Scrub gesture di-attach sebagai high-priority hanya bila diminta (Portfolio
    /// card di dalam ScrollView). `useHighPriorityDrag` konstan per call-site,
    /// jadi cabang ini stabil dan tidak memicu reset identity SwiftUI.
    @ViewBuilder
    private var interactiveChart: some View {
        if useHighPriorityDrag {
            coreChart.highPriorityGesture(dragGesture)
        } else {
            coreChart.gesture(dragGesture)
        }
    }

    private var coreChart: some View {
        ZStack {
            let shouldShow = chartSize.height > 0 &&
                (oneDayReady || !animatedData.points.isEmpty)

            if shouldShow {
                chartContent
            } else if chartVM.dataPoints.isEmpty && !chartVM.isLoading {
                Text("Data tidak tersedia")
                    .font(.caption).foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.appCardBackground))
        // Catatan: clip rounded TIDAK dipasang di sini lagi — kalau seluruh ZStack
        // di-clip, dot harga terakhir / pulse ring di tepi kanan (x ≈ width-4)
        // ikut ter-crop. Clip rounded sekarang hanya membungkus grafik area/line
        // di dalam `chartContent`, sedangkan dot & crosshair digambar sebagai
        // overlay tanpa clip. Lihat chartContent.
        .contentShape(Rectangle().inset(by: -40))
    }

    // MARK: - Pulse Animation

    private func updatePulse() {
        // Only animate on 1D range when market is active
        guard chartVM.selectedRange == .oneDay, isMarketActive else {
            pulseScale = 1.0   // reset to resting state
            return
        }
        pulseScale = 1.0
        withAnimation(
            .easeInOut(duration: 1.1)
            .repeatForever(autoreverses: true)
        ) {
            pulseScale = 2.4
        }
    }

    // MARK: - Apply Data → Animasi

    private func applyChartData() {
        guard !chartVM.dataPoints.isEmpty, chartSize.width > 0 else { return }

        if chartVM.selectedRange == .oneDay {
            // Jika animasi clip kiri→kanan sedang berjalan (oneDayReady=true tapi clipWidth
            // belum penuh), jangan interrupt — biarkan animasi selesai.
            if hasEverLoadedOneDay && oneDayReady { return }

            let oneDayTarget = buildMorphPoints(chartVM.dataPoints, range: chartVM.selectedRange, size: chartSize)
            let lastSlotIdx  = chartVM.oneDaySlotIndex(for: chartVM.dataPoints.last!.date)
            let innerW       = chartSize.width - 8
            let xLast        = 4 + CGFloat(lastSlotIdx) / CGFloat(chartVM.oneDayTotalSlots - 1) * innerW
            let targetClip   = min(xLast + 4, chartSize.width)

            if !hasEverLoadedOneDay {
                animatedData        = oneDayTarget
                hasEverLoadedOneDay = true
                oneDayReady         = true
                oneDayClipWidth     = 0
                oneDayRevealDone    = false
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 1.2)) { oneDayClipWidth = targetClip }
                    // Setelah reveal selesai, dot pindah ke mode "ikuti data terakhir"
                    // (agar update streaming live tetap menggerakkan dot).
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.25) { oneDayRevealDone = true }
                }
            } else {
                oneDayReady = false
                withAnimation(.spring(response: 1.2, dampingFraction: 1.0)) { animatedData = oneDayTarget }
            }
        } else {
            oneDayReady = false
            let target = buildMorphPoints(chartVM.dataPoints, range: chartVM.selectedRange, size: chartSize)

            if revealOnFirstLoad && !hasRevealed {
                // First ever non-1D load: Y fix langsung, hanya clip yang beranimasi kiri→kanan
                animatedData      = target
                animatedBaselineY = yPos(for: chartVM.startPrice, in: chartSize)
                revealClipWidth   = 0
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 1.2)) { revealClipWidth = chartSize.width }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) { hasRevealed = true }
                }
            } else {
                // Range change: morph dari posisi saat ini ke target dengan spring
                if animatedData.points.isEmpty {
                    animatedData = AnimatableChartData(points: (0..<resampleCount).map { i in
                        let t = CGFloat(i) / CGFloat(resampleCount - 1)
                        return MorphPoint(x: t * chartSize.width, y: chartSize.height / 2)
                    })
                }
                let targetBaselineY = yPos(for: chartVM.startPrice, in: chartSize)
                withAnimation(.spring(response: 1.55, dampingFraction: 1.0)) {
                    animatedData      = target
                    animatedBaselineY = targetBaselineY
                }
            }
        }
    }

    // MARK: Chart Content

    @ViewBuilder
    private var chartContent: some View {
        let data    = chartVM.dataPoints
        let minP    = chartVM.minPrice
        let maxP    = chartVM.maxPrice
        let startP  = chartVM.startPrice
        let lastP   = chartVM.latestPrice
        let isOneDay = chartVM.selectedRange == .oneDay && oneDayReady

        let yMax      = yPos(for: maxP,   in: chartSize)
        let yMin      = yPos(for: minP,   in: chartSize)
        let yBaseline = yPos(for: startP, in: chartSize)
        let yLast     = yPos(for: lastP,  in: chartSize)

        let greenColor = fixedColor ?? Color.ProfitGreen
        let redColor   = fixedColor ?? Color.LossRed

        let oneDayPoints: [OneDayLineShape.Point] = isOneDay ? {
            let closes = data.map(\.close)
            let minV   = closes.min() ?? minP
            let maxV   = closes.max() ?? maxP
            let range  = maxV - minV
            return data.map { pt in
                OneDayLineShape.Point(
                    slotIndex: chartVM.oneDaySlotIndex(for: pt.date),
                    normY: range > 0 ? (pt.close - minV) / range : 0.5
                )
            }
        }() : []

        ZStack {
            // ==== Grafik chart — DI-CLIP rounded (sudut kartu membulat) ====
            // Hanya area/line/dash yang di-clip. Dot & crosshair digambar sebagai
            // overlay di luar clip ini supaya tidak ter-crop di tepi kanan.
            ZStack {
                DashLine(from: CGPoint(x: 0, y: yMax), to: CGPoint(x: chartSize.width, y: yMax))
                    .stroke(Color.secondary.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                DashLine(from: CGPoint(x: 0, y: yMin), to: CGPoint(x: chartSize.width, y: yMin))
                    .stroke(Color.secondary.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                AnimatableHDashLine(y: yBaseline)
                    .stroke(Color.AccentGold.opacity(0.50),
                            style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                    .animation(.spring(response: 1.55, dampingFraction: 1.0), value: yBaseline)

                if isOneDay {
                    ZStack {
                        OneDayAreaShape(points: oneDayPoints, totalSlots: chartVM.oneDayTotalSlots,
                                        hPad: 4, closingY: yBaseline)
                            .fill(LinearGradient(stops: [
                                .init(color: greenColor.opacity(0.38), location: 0.0),
                                .init(color: greenColor.opacity(0.18), location: 0.5),
                                .init(color: greenColor.opacity(0.0),  location: 1.0)],
                                startPoint: .top, endPoint: .bottom))
                            .clipShape(Rectangle().path(in: CGRect(x: 0, y: 0, width: chartSize.width, height: yBaseline)))
                        OneDayAreaShape(points: oneDayPoints, totalSlots: chartVM.oneDayTotalSlots,
                                        hPad: 4, closingY: yBaseline)
                            .fill(LinearGradient(stops: [
                                .init(color: redColor.opacity(0.38), location: 0.0),
                                .init(color: redColor.opacity(0.18), location: 0.5),
                                .init(color: redColor.opacity(0.0),  location: 1.0)],
                                startPoint: .bottom, endPoint: .top))
                            .clipShape(Rectangle().path(in: CGRect(x: 0, y: yBaseline,
                                width: chartSize.width, height: chartSize.height - yBaseline)))
                        OneDayLineShape(points: oneDayPoints, totalSlots: chartVM.oneDayTotalSlots, hPad: 4)
                            .stroke(greenColor, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                            .clipShape(Rectangle().path(in: CGRect(x: 0, y: 0, width: chartSize.width, height: yBaseline)))
                        OneDayLineShape(points: oneDayPoints, totalSlots: chartVM.oneDayTotalSlots, hPad: 4)
                            .stroke(redColor, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                            .clipShape(Rectangle().path(in: CGRect(x: 0, y: yBaseline,
                                width: chartSize.width, height: chartSize.height - yBaseline)))
                    }
                    .clipShape(AnimatableClipRect(clipWidth: oneDayClipWidth))

                } else {
                    ZStack {
                        MorphingXYAreaShape(data: animatedData, closingY: animatedBaselineY)
                            .fill(LinearGradient(stops: [
                                .init(color: greenColor.opacity(0.38), location: 0.0),
                                .init(color: greenColor.opacity(0.18), location: 0.5),
                                .init(color: greenColor.opacity(0.0),  location: 1.0)],
                                startPoint: .top, endPoint: .bottom))
                            .clipShape(AnimatableClipAbove(cutY: animatedBaselineY))
                        MorphingXYAreaShape(data: animatedData, closingY: animatedBaselineY)
                            .fill(LinearGradient(stops: [
                                .init(color: redColor.opacity(0.38), location: 0.0),
                                .init(color: redColor.opacity(0.18), location: 0.5),
                                .init(color: redColor.opacity(0.0),  location: 1.0)],
                                startPoint: .bottom, endPoint: .top))
                            .clipShape(AnimatableClipBelow(cutY: animatedBaselineY, totalHeight: chartSize.height))
                        MorphingXYLineShape(data: animatedData)
                            .stroke(greenColor, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                            .clipShape(AnimatableClipAbove(cutY: animatedBaselineY))
                        MorphingXYLineShape(data: animatedData)
                            .stroke(redColor, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                            .clipShape(AnimatableClipBelow(cutY: animatedBaselineY, totalHeight: chartSize.height))
                    }
                    .clipShape(AnimatableClipRect(clipWidth: (!revealOnFirstLoad || hasRevealed) ? chartSize.width : revealClipWidth))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // ==== Overlay — TIDAK di-clip (dot & shadow bebas di tepi) ====

            // Max / Min labels
            Text("Max \(formatPrice(maxP, market: market))")
                .font(.system(size: 9, weight: .semibold)).foregroundColor(.secondary)
                .padding(.horizontal, 4).padding(.vertical, 2)
                .background(Color.appElevatedBackground.opacity(0.85)).cornerRadius(4)
                .position(x: chartSize.width - 34, y: yMax - 10)
            Text("Min \(formatPrice(minP, market: market))")
                .font(.system(size: 9, weight: .semibold)).foregroundColor(.secondary)
                .padding(.horizontal, 4).padding(.vertical, 2)
                .background(Color.appCardBackground.opacity(0.85)).cornerRadius(4)
                .position(x: chartSize.width - 34, y: yMin + 10)

            // Active price dot & dashed line — 1D (pulse saat market aktif)
            if isOneDay && !isDragging {
                let innerW   = chartSize.width - 8
                let dotColor = lastP >= startP ? greenColor : redColor

                if !oneDayRevealDone && data.count > 1 {
                    // Reveal pertama: garis 1D tumbuh kiri→kanan via oneDayClipWidth.
                    // Dot ikut merambat di ujung garis (tipX = oneDayClipWidth),
                    // bukan langsung menempel di posisi terakhir. Titik polyline
                    // dihitung identik dengan OneDayLineShape (hPad 4) & yPos.
                    let tipPoints: [CGPoint] = data.map { pt in
                        let slot = chartVM.oneDaySlotIndex(for: pt.date)
                        return CGPoint(
                            x: 4 + CGFloat(slot) / CGFloat(chartVM.oneDayTotalSlots - 1) * innerW,
                            y: yPos(for: pt.close, in: chartSize)
                        )
                    }
                    ZStack {
                        Circle().fill(dotColor).frame(width: 9, height: 9)
                            .shadow(color: dotColor.opacity(0.7), radius: 5)
                        Circle().fill(Color.SurfaceWhite).frame(width: 4, height: 4)
                    }
                    .frame(width: 9, height: 9)
                    .position(x: 0, y: 0)
                    .modifier(GrowingLineTip(tipX: oneDayClipWidth, points: tipPoints))
                } else {
                    // Settled: dot menempel di data terakhir (mengikuti update live).
                    let lastSlotIdx = data.isEmpty ? 0 : chartVM.oneDaySlotIndex(for: data.last!.date)
                    let dotX        = 4 + CGFloat(lastSlotIdx) / CGFloat(chartVM.oneDayTotalSlots - 1) * innerW

                    AnimatableHDashLine(y: yLast)
                        .stroke(dotColor.opacity(0.70), style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                    if isMarketActive {
                        Circle()
                            .fill(dotColor.opacity(0.25))
                            .frame(width: 9 * pulseScale, height: 9 * pulseScale)
                            .position(x: dotX, y: yLast)
                    }
                    Circle().fill(dotColor).frame(width: 9, height: 9)
                        .shadow(color: dotColor.opacity(0.7), radius: 5)
                        .position(x: dotX, y: yLast)
                    Circle().fill(Color.SurfaceWhite).frame(width: 4, height: 4)
                        .position(x: dotX, y: yLast)
                }
            }

            // Last price dot & dashed line (non-1D)
            if !isDragging && !isOneDay {
                let dotColor  = lastP >= startP ? greenColor : redColor
                let tipPoints = animatedData.points.map { CGPoint(x: $0.x, y: $0.y) }

                if revealOnFirstLoad && !hasRevealed && tipPoints.count > 1 {
                    // First-load reveal: dot merambat mengikuti ujung garis yang
                    // sedang tumbuh (tipX = revealClipWidth yang di-animate).
                    // Garis referensi horizontal disembunyikan dulu — muncul saat
                    // reveal selesai (cabang else di bawah).
                    ZStack {
                        Circle().fill(dotColor).frame(width: 9, height: 9)
                            .shadow(color: dotColor.opacity(0.7), radius: 5)
                        Circle().fill(Color.SurfaceWhite).frame(width: 4, height: 4)
                    }
                    .frame(width: 9, height: 9)
                    .position(x: 0, y: 0)
                    .modifier(GrowingLineTip(tipX: revealClipWidth, points: tipPoints))
                } else {
                    let animX = animatedData.points.last.map { $0.x } ?? xFor(index: data.count - 1, count: data.count, width: chartSize.width)
                    let animY = animatedData.points.last.map { $0.y } ?? yLast

                    AnimatableHDashLine(y: animY)
                        .stroke(dotColor.opacity(0.70), style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                        .animation(.spring(response: 1.55, dampingFraction: 1.0), value: animY)
                    Circle().fill(dotColor).frame(width: 9, height: 9)
                        .shadow(color: dotColor.opacity(0.7), radius: 5)
                        .position(x: animX, y: animY)
                    Circle().fill(Color.SurfaceWhite).frame(width: 4, height: 4)
                        .position(x: animX, y: animY)
                }
            }

            // Crosshair
            if isDragging, let point = selectedPoint {
                let ptColor = point.close >= startP ? greenColor : redColor
                CrosshairView(
                    point:       point,
                    chartVM:     chartVM,
                    chartSize:   chartSize,
                    accentColor: ptColor,
                    xPos: xFor(index: data.firstIndex(where: { $0.id == point.id }) ?? 0,
                               count: data.count, width: chartSize.width),
                    yPos: yPos(for: point.close, in: chartSize)
                )
            }
        }
    }

    // MARK: - Drag Gesture

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { val in
                isDragging = true
                let data = chartVM.dataPoints
                guard !data.isEmpty, chartSize.width > 0 else { return }

                let innerWidth = chartSize.width - 8
                let clampedX   = max(0, min(val.location.x - 4, innerWidth))
                let nearest: StockDataPoint

                if chartVM.selectedRange == .oneDay {
                    let totalSlots = chartVM.oneDayTotalSlots
                    let slotFrac   = clampedX / innerWidth * CGFloat(totalSlots - 1)
                    let targetSlot = Int(slotFrac.rounded())
                    nearest = data.min(by: {
                        abs(chartVM.oneDaySlotIndex(for: $0.date) - targetSlot) <
                        abs(chartVM.oneDaySlotIndex(for: $1.date) - targetSlot)
                    }) ?? data[0]
                } else {
                    let touchX = clampedX + 4
                    if !animatedData.points.isEmpty {
                        let bestMorphIdx = animatedData.points.indices.min(by: {
                            abs(animatedData.points[$0].x - touchX) <
                            abs(animatedData.points[$1].x - touchX)
                        }) ?? 0
                        let dataFrac = CGFloat(bestMorphIdx) / CGFloat(max(animatedData.points.count - 1, 1))
                        let i = max(0, min(Int((dataFrac * CGFloat(data.count - 1)).rounded()), data.count - 1))
                        nearest = data[i]
                    } else {
                        let i = max(0, min(Int((clampedX / innerWidth * CGFloat(data.count - 1)).rounded()), data.count - 1))
                        nearest = data[i]
                    }
                }

                if nearest.id != selectedPoint?.id {
                    selectedPoint = nearest
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            }
            .onEnded { _ in
                withAnimation(.easeOut(duration: 0.25)) {
                    isDragging    = false
                    selectedPoint = nil
                }
            }
    }

    // MARK: - Build MorphPoints

    private func buildMorphPoints(_ data: [StockDataPoint], range: TimeRange, size: CGSize) -> AnimatableChartData {
        guard data.count > 1, size.width > 0, size.height > 0 else { return .zero }

        let closes = data.map(\.close)
        let minV   = closes.min()!; let maxV = closes.max()!; let vRange = maxV - minV
        let topPad: CGFloat = 20; let bottomPad: CGFloat = 20; let hPad: CGFloat = 4
        let usable = size.height - topPad - bottomPad
        let innerW = size.width  - hPad * 2

        if range == .oneDay {
            let totalSlots  = chartVM.oneDayTotalSlots
            let lastSlotIdx = chartVM.oneDaySlotIndex(for: data.last!.date)
            var morphPoints: [MorphPoint] = []; morphPoints.reserveCapacity(resampleCount)

            for i in 0..<resampleCount {
                let slotFrac = CGFloat(i) / CGFloat(resampleCount - 1) * CGFloat(totalSlots - 1)
                let slot     = Int(slotFrac)
                let x: CGFloat; let y: CGFloat

                if slot <= lastSlotIdx {
                    let activeFrac = CGFloat(lastSlotIdx) / CGFloat(totalSlots - 1)
                    let dataFrac   = (slotFrac / CGFloat(totalSlots - 1)) / max(activeFrac, 1e-6) * CGFloat(data.count - 1)
                    let lo   = max(0, min(Int(dataFrac), data.count - 1))
                    let hi   = min(lo + 1, data.count - 1)
                    let frac = dataFrac - CGFloat(lo)
                    let val  = closes[lo] * Double(1 - frac) + closes[hi] * Double(frac)
                    let normY = vRange > 0 ? (val - minV) / vRange : 0.5
                    y = topPad + usable * CGFloat(1.0 - normY)
                    x = hPad + slotFrac / CGFloat(totalSlots - 1) * innerW
                } else {
                    let normY = vRange > 0 ? (closes.last! - minV) / vRange : 0.5
                    y = topPad + usable * CGFloat(1.0 - normY)
                    x = hPad + CGFloat(lastSlotIdx) / CGFloat(totalSlots - 1) * innerW
                }
                morphPoints.append(MorphPoint(x: x, y: y))
            }
            return AnimatableChartData(points: morphPoints)
        } else {
            let exponent = range.xSpacingExponent
            let points: [MorphPoint] = (0..<resampleCount).map { i in
                let tData = Double(i) / Double(resampleCount - 1) * Double(data.count - 1)
                let lo    = max(0, min(Int(tData), data.count - 1))
                let hi    = min(lo + 1, data.count - 1)
                let frac  = tData - Double(lo)
                let val   = closes[lo] * (1 - frac) + closes[hi] * frac
                let normY = vRange > 0 ? (val - minV) / vRange : 0.5
                let y     = topPad + usable * CGFloat(1.0 - normY)
                let t = CGFloat(i) / CGFloat(resampleCount - 1)
                let x = hPad + pow(t, exponent) * innerW
                return MorphPoint(x: x, y: y)
            }
            return AnimatableChartData(points: points)
        }
    }

    // MARK: - Coordinate Helpers

    private func xFor(index: Int, count: Int, width: CGFloat) -> CGFloat {
        let innerWidth = width - 8
        if chartVM.selectedRange == .oneDay {
            let data = chartVM.dataPoints
            guard index < data.count else { return 4 + CGFloat(index) / CGFloat(max(count - 1, 1)) * innerWidth }
            let slotIdx = chartVM.oneDaySlotIndex(for: data[index].date)
            return 4 + CGFloat(slotIdx) / CGFloat(chartVM.oneDayTotalSlots - 1) * innerWidth
        }
        guard !animatedData.points.isEmpty else { return 4 + CGFloat(index) / CGFloat(max(count - 1, 1)) * innerWidth }
        let fraction = CGFloat(index) / CGFloat(max(count - 1, 1))
        let ptIndex  = Int((fraction * CGFloat(animatedData.points.count - 1)).rounded())
            .clamped(to: 0...(animatedData.points.count - 1))
        return animatedData.points[ptIndex].x
    }

    private func yPos(for value: Double, in size: CGSize) -> CGFloat {
        let topPad: CGFloat = 20; let bottomPad: CGFloat = 20
        let usable = size.height - topPad - bottomPad
        guard usable > 0 else { return size.height / 2 }
        let range = chartVM.maxPrice - chartVM.minPrice
        let norm  = range > 0 ? (value - chartVM.minPrice) / range : 0.5
        return topPad + usable * (1 - norm)
    }
}

// MARK: - Shape Definitions

struct DashLine: Shape {
    let from: CGPoint; let to: CGPoint
    func path(in rect: CGRect) -> Path {
        var p = Path(); p.move(to: from); p.addLine(to: to); return p
    }
}

struct AnimatableHDashLine: Shape {
    var y: CGFloat
    var animatableData: CGFloat { get { y } set { y = newValue } }
    func path(in rect: CGRect) -> Path {
        var p = Path(); p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: rect.width, y: y)); return p
    }
}

struct OneDayLineShape: Shape {
    struct Point { let slotIndex: Int; let normY: Double }
    var points: [Point]; var totalSlots: Int; var hPad: CGFloat

    func path(in rect: CGRect) -> Path {
        guard points.count > 1 else { return Path() }
        let topPad: CGFloat = 20; let bottomPad: CGFloat = 20
        let usable = rect.height - topPad - bottomPad
        let innerWidth = rect.width - hPad * 2
        guard usable > 0, innerWidth > 0 else { return Path() }
        func cgPoint(_ p: Point) -> CGPoint {
            CGPoint(x: hPad + CGFloat(p.slotIndex) / CGFloat(totalSlots - 1) * innerWidth,
                    y: topPad + usable * CGFloat(1.0 - p.normY))
        }
        var path = Path(); path.move(to: cgPoint(points[0]))
        for i in 1..<points.count { path.addLine(to: cgPoint(points[i])) }
        return path
    }
}

struct AnimatableClipRect: Shape {
    var clipWidth: CGFloat
    var animatableData: CGFloat { get { clipWidth } set { clipWidth = newValue } }
    func path(in rect: CGRect) -> Path { Path(CGRect(x: 0, y: 0, width: max(0, clipWidth), height: rect.height)) }
}

/// Menggeser view (dot harga terakhir) mengikuti UJUNG garis yang sedang tumbuh
/// kiri→kanan saat reveal pertama. `tipX` di-animate (= revealClipWidth); tiap
/// frame kita cari y pada polyline `points` di x = tipX, lalu translate view
/// (yang di-`position(x:0,y:0)`) ke titik itu. Karena `tipX` adalah
/// `animatableData`, SwiftUI meng-interpolasi-nya per-frame sehingga dot benar-
/// benar ikut merambat di sepanjang garis, bukan diam di posisi akhir.
struct GrowingLineTip: GeometryEffect {
    var tipX: CGFloat
    let points: [CGPoint]

    var animatableData: CGFloat {
        get { tipX }
        set { tipX = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        guard let first = points.first, let last = points.last else {
            return ProjectionTransform()
        }
        let x = min(max(tipX, first.x), last.x)
        let y = interpolatedY(atX: x)
        return ProjectionTransform(CGAffineTransform(translationX: x, y: y))
    }

    /// y pada polyline (titik terurut menaik di x) untuk x tertentu.
    private func interpolatedY(atX x: CGFloat) -> CGFloat {
        guard let first = points.first, let last = points.last else { return 0 }
        if x <= first.x { return first.y }
        if x >= last.x  { return last.y }
        for i in 1..<points.count where points[i].x >= x {
            let p0 = points[i - 1], p1 = points[i]
            let dx = p1.x - p0.x
            let t  = dx == 0 ? 0 : (x - p0.x) / dx
            return p0.y + (p1.y - p0.y) * t
        }
        return last.y
    }
}

struct AnimatableClipAbove: Shape {
    var cutY: CGFloat
    var animatableData: CGFloat { get { cutY } set { cutY = newValue } }
    func path(in rect: CGRect) -> Path { Path(CGRect(x: 0, y: 0, width: rect.width, height: max(0, cutY))) }
}

struct AnimatableClipBelow: Shape {
    var cutY: CGFloat; var totalHeight: CGFloat
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(cutY, totalHeight) }
        set { cutY = newValue.first; totalHeight = newValue.second }
    }
    func path(in rect: CGRect) -> Path {
        Path(CGRect(x: 0, y: cutY, width: rect.width, height: max(0, totalHeight - cutY)))
    }
}

struct OneDayAreaShape: Shape {
    var points: [OneDayLineShape.Point]; var totalSlots: Int; var hPad: CGFloat; var closingY: CGFloat

    func path(in rect: CGRect) -> Path {
        guard points.count > 1 else { return Path() }
        let topPad: CGFloat = 20; let bottomPad: CGFloat = 20
        let usable = rect.height - topPad - bottomPad
        let innerWidth = rect.width - hPad * 2
        guard usable > 0, innerWidth > 0 else { return Path() }
        func cgPoint(_ p: OneDayLineShape.Point) -> CGPoint {
            CGPoint(x: hPad + CGFloat(p.slotIndex) / CGFloat(totalSlots - 1) * innerWidth,
                    y: topPad + usable * CGFloat(1.0 - p.normY))
        }
        var path = Path(); path.move(to: cgPoint(points[0]))
        for i in 1..<points.count { path.addLine(to: cgPoint(points[i])) }
        let lastX  = hPad + CGFloat(points.last!.slotIndex)  / CGFloat(totalSlots - 1) * innerWidth
        let firstX = hPad + CGFloat(points.first!.slotIndex) / CGFloat(totalSlots - 1) * innerWidth
        path.addLine(to: CGPoint(x: lastX,  y: closingY))
        path.addLine(to: CGPoint(x: firstX, y: closingY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Crosshair View

struct CrosshairView<VM: ChartViewModelProtocol>: View {
    let point: StockDataPoint; let chartVM: VM
    let chartSize: CGSize; let accentColor: Color; let xPos: CGFloat; let yPos: CGFloat

    var body: some View {
        ZStack {
            DashLine(from: CGPoint(x: 0, y: yPos), to: CGPoint(x: chartSize.width, y: yPos))
                .stroke(accentColor.opacity(0.6), style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
            DashLine(from: CGPoint(x: xPos, y: 0), to: CGPoint(x: xPos, y: chartSize.height))
                .stroke(Color.primary.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            Circle().fill(accentColor).frame(width: 13, height: 13)
                .shadow(color: accentColor.opacity(0.7), radius: 6).position(x: xPos, y: yPos)
            Circle().fill(Color.SurfaceWhite).frame(width: 5, height: 5).position(x: xPos, y: yPos)
            TooltipView(date: point.date, range: chartVM.selectedRange, xPos: xPos, chartWidth: chartSize.width)
        }
    }
}

// MARK: - Tooltip View

struct TooltipView: View {
    let date: Date; let range: TimeRange; let xPos: CGFloat; let chartWidth: CGFloat

    private let h: CGFloat = 26; private let pad: CGFloat = 4

    private var text: String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "id_ID")
        df.timeZone = TimeZone(identifier: "Asia/Jakarta")!
        df.dateFormat = range.isIntraday ? "d MMM 'at' HH:mm" : "d MMM yyyy"
        return df.string(from: date)
    }
    private var estimatedWidth: CGFloat { CGFloat(text.count) * 7.5 + 20 }
    private var clampedX: CGFloat {
        var x = xPos - estimatedWidth / 2
        x = max(pad, min(x, chartWidth - estimatedWidth - pad))
        return x + estimatedWidth / 2
    }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold)).foregroundColor(.primary)
            .padding(.horizontal, 0).padding(.vertical, 4).frame(height: h)
            .background(
                RoundedRectangle(cornerRadius: 6).fill(Color(.systemBackground))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.08), lineWidth: 1))
                    .shadow(color: .black.opacity(0.12), radius: 4, x: 0, y: 2)
            )
            .position(x: clampedX, y: h / 2 + 4)
            .transition(.opacity)
    }
}

// MARK: - Axis Tick Model

struct AxisTick: Identifiable, Equatable {
    let id:    Int
    let normX: Double
    let label: String
}

// MARK: - Axis Tick Generator

enum AxisTickGenerator {

    private static var jakartaCal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Jakarta")!
        return c
    }()

    static func ticks<VM: ChartViewModelProtocol>(for data: [StockDataPoint], range: TimeRange, chartVM: VM) -> [AxisTick] {
        guard !data.isEmpty else { return [] }
        switch range {
        case .oneDay:     return oneDayTicks(data: data, chartVM: chartVM)
        case .oneWeek:    return oneWeekTicks(data: data)
        case .oneMonth:   return oneMonthTicks(data: data)
        case .threeMonth: return threeMonthTicks(data: data)
        case .ytd:        return ytdTicks(data: data)
        case .oneYear:    return oneYearTicks(data: data)
        case .fiveYear:   return fiveYearTicks(data: data)
        case .all:        return fiveYearTicks(data: data)
        }
    }

    private static func firstIndexPerDay(_ data: [StockDataPoint]) -> [(index: Int, date: Date)] {
        var seen = Set<String>(); var result: [(Int, Date)] = []
        let df = DateFormatter(); df.timeZone = TimeZone(identifier: "Asia/Jakarta")!; df.dateFormat = "yyyy-MM-dd"
        for (i, pt) in data.enumerated() {
            let key = df.string(from: pt.date)
            if !seen.contains(key) { seen.insert(key); result.append((i, pt.date)) }
        }
        return result
    }

    private static func firstIndexPerMonth(_ data: [StockDataPoint]) -> [(key: String, index: Int, date: Date)] {
        var buckets: [String: (Int, Date)] = [:]
        let df = DateFormatter(); df.timeZone = TimeZone(identifier: "Asia/Jakarta")!; df.dateFormat = "yyyy-MM"
        for (i, pt) in data.enumerated() {
            let key = df.string(from: pt.date)
            if buckets[key] == nil { buckets[key] = (i, pt.date) }
        }
        return buckets.keys.sorted().compactMap { k in buckets[k].map { (k, $0.0, $0.1) } }
    }

    private static func nearestIndex(in data: [StockDataPoint], to targetDate: Date) -> Int? {
        data.enumerated().min(by: {
            abs($0.element.date.timeIntervalSince(targetDate)) < abs($1.element.date.timeIntervalSince(targetDate))
        })?.offset
    }

    private static func oneDayTicks<VM: ChartViewModelProtocol>(data: [StockDataPoint], chartVM: VM) -> [AxisTick] {
        guard let firstDate = data.first?.date else { return [] }
        let weekday    = jakartaCal.component(.weekday, from: firstDate)
        // Use instance vars — US stocks have totalSlots=79 and openMinutes≠540
        let totalSlots = chartVM.oneDayTotalSlots
        let openMins   = chartVM.oneDayOpenMinutes
        let lastSlotIndex: Int = {
            guard let lastPt = data.last else { return 0 }
            let h = jakartaCal.component(.hour, from: lastPt.date)
            let m = jakartaCal.component(.minute, from: lastPt.date)
            let mins = (h * 60 + m) - openMins
            return max(0, min(mins / 5, totalSlots - 1))
        }()
        // IDX candidates (weekday != 6 = Saturday for US pre-market edge case)
        // For US stocks the open hour will be evening WIB so no IDX candidate will pass
        // the slotIndex >= 0 guard — axis will be empty (correct for US market).
        let candidates: [(hour: Int, minute: Int, label: String)] = weekday == 6
            ? [(9,30,"09:30"),(10,30,"10:30"),(11,30,"11:30"),(14,0,"14:00"),(15,0,"15:00")]
            : [(10,0,"10:00"),(11,0,"11:00"),(12,0,"12:00"),(13,30,"13:30"),(14,30,"14:30"),(15,30,"15:30")]
        var result: [AxisTick] = []; var ordinal = 0
        for slot in candidates {
            let slotIndex = (slot.hour * 60 + slot.minute - openMins) / 5
            guard slotIndex >= 0, slotIndex <= lastSlotIndex else { continue }
            result.append(AxisTick(id: ordinal, normX: Double(slotIndex) / Double(totalSlots - 1), label: slot.label))
            ordinal += 1
        }
        return result
    }

    private static func oneWeekTicks(data: [StockDataPoint]) -> [AxisTick] {
        let days = firstIndexPerDay(data); let total = max(data.count - 1, 1); let cal = jakartaCal
        let dayDF = DateFormatter(); dayDF.timeZone = TimeZone(identifier: "Asia/Jakarta")!; dayDF.dateFormat = "d"
        let monDF = DateFormatter(); monDF.locale = Locale(identifier: "en_US")
        monDF.timeZone = TimeZone(identifier: "Asia/Jakarta")!; monDF.dateFormat = "MMM"
        var ticks: [AxisTick] = []; var prevMonth = -1
        for (ordinal, pair) in days.enumerated() {
            let month = cal.component(.month, from: pair.date)
            let isNewMonth = (prevMonth != -1 && month != prevMonth)
            let label = isNewMonth ? monDF.string(from: pair.date) : dayDF.string(from: pair.date)
            ticks.append(AxisTick(id: ordinal, normX: Double(pair.index) / Double(total), label: label))
            prevMonth = month
        }
        return ticks
    }

    private static func oneMonthTicks(data: [StockDataPoint]) -> [AxisTick] {
        let days = firstIndexPerDay(data); let total = max(data.count - 1, 1); let cal = jakartaCal
        let dayDF = DateFormatter(); dayDF.timeZone = TimeZone(identifier: "Asia/Jakarta")!; dayDF.dateFormat = "d"
        let monDF = DateFormatter(); monDF.locale = Locale(identifier: "en_US")
        monDF.timeZone = TimeZone(identifier: "Asia/Jakarta")!; monDF.dateFormat = "MMM"
        var prevMonth = -1; var isNewMonthDay = [Bool]()
        for pair in days {
            let m = cal.component(.month, from: pair.date)
            isNewMonthDay.append(prevMonth != -1 && m != prevMonth); prevMonth = m
        }
        let maxLabels = min(5, days.count); var selectedIndices = Set<Int>()
        if days.count <= maxLabels { days.indices.forEach { selectedIndices.insert($0) } }
        else {
            let step = Double(days.count - 1) / Double(maxLabels - 1)
            for k in 0..<maxLabels { selectedIndices.insert(min(Int(Double(k) * step + 0.5), days.count - 1)) }
        }
        for (k, isNew) in isNewMonthDay.enumerated() { if isNew { selectedIndices.insert(k) } }
        let newMonthPositions = isNewMonthDay.indices.filter { isNewMonthDay[$0] }; let minGap = 2
        let filtered = selectedIndices.filter { k in
            guard !isNewMonthDay[k] else { return true }
            return !newMonthPositions.contains(where: { abs($0 - k) < minGap })
        }
        return filtered.sorted().enumerated().map { ordinal, k in
            let pair = days[k]
            let label = isNewMonthDay[k] ? monDF.string(from: pair.date) : dayDF.string(from: pair.date)
            return AxisTick(id: ordinal, normX: Double(pair.index) / Double(total), label: label)
        }
    }

    private static func threeMonthTicks(data: [StockDataPoint]) -> [AxisTick] {
        guard !data.isEmpty else { return [] }
        let total = max(data.count - 1, 1); let cal = jakartaCal
        let dayDF = DateFormatter(); dayDF.timeZone = TimeZone(identifier: "Asia/Jakarta")!; dayDF.dateFormat = "d"
        let monDF = DateFormatter(); monDF.locale = Locale(identifier: "en_US")
        monDF.timeZone = TimeZone(identifier: "Asia/Jakarta")!; monDF.dateFormat = "MMM"
        var ticks: [AxisTick] = []; var ordinal = 0
        ticks.append(AxisTick(id: ordinal, normX: 0.0, label: dayDF.string(from: data[0].date))); ordinal += 1
        let months = firstIndexPerMonth(data); let firstMonth = cal.component(.month, from: data[0].date)
        for m in months {
            guard cal.component(.month, from: m.date) != firstMonth else { continue }
            ticks.append(AxisTick(id: ordinal, normX: Double(m.index) / Double(total), label: monDF.string(from: m.date)))
            ordinal += 1
        }
        return ticks
    }

    private static func ytdTicks(data: [StockDataPoint]) -> [AxisTick] {
        guard !data.isEmpty else { return [] }
        let total = max(data.count - 1, 1); let cal = jakartaCal
        let monDF = DateFormatter(); monDF.locale = Locale(identifier: "en_US")
        monDF.timeZone = TimeZone(identifier: "Asia/Jakarta")!; monDF.dateFormat = "MMM"
        var ticks: [AxisTick] = []; var ordinal = 0
        ticks.append(AxisTick(id: ordinal, normX: 0.0, label: "2026")); ordinal += 1
        let firstMonth = cal.component(.month, from: data[0].date)
        for m in firstIndexPerMonth(data) {
            guard cal.component(.month, from: m.date) != firstMonth else { continue }
            ticks.append(AxisTick(id: ordinal, normX: Double(m.index) / Double(total), label: monDF.string(from: m.date)))
            ordinal += 1
        }
        return ticks
    }

    private static func oneYearTicks(data: [StockDataPoint]) -> [AxisTick] {
        guard !data.isEmpty else { return [] }
        let total = max(data.count - 1, 1); let cal = jakartaCal
        struct Target { let year: Int; let month: Int; let label: String }
        let targets = [Target(year: 2025, month: 6, label: "2025"), Target(year: 2025, month: 9, label: "Sep"),
                       Target(year: 2026, month: 1, label: "2026"), Target(year: 2026, month: 4, label: "Apr")]
        var ticks: [AxisTick] = []; var ordinal = 0
        for t in targets {
            var comps = DateComponents(); comps.year = t.year; comps.month = t.month; comps.day = 1
            comps.timeZone = cal.timeZone
            guard let targetDate = cal.date(from: comps), let idx = nearestIndex(in: data, to: targetDate) else { continue }
            ticks.append(AxisTick(id: ordinal, normX: Double(idx) / Double(total), label: t.label)); ordinal += 1
        }
        return ticks
    }

    private static func fiveYearTicks(data: [StockDataPoint]) -> [AxisTick] {
        guard !data.isEmpty else { return [] }
        let total = max(data.count - 1, 1); let cal = jakartaCal
        let lastYear = cal.component(.year, from: data.last!.date)
        var ticks: [AxisTick] = []; var ordinal = 0
        for year in 2022...lastYear {
            var comps = DateComponents(); comps.year = year; comps.month = 1; comps.day = 1
            comps.timeZone = cal.timeZone
            guard let targetDate = cal.date(from: comps), let idx = nearestIndex(in: data, to: targetDate) else { continue }
            ticks.append(AxisTick(id: ordinal, normX: Double(idx) / Double(total), label: "\(year)")); ordinal += 1
        }
        return ticks
    }
}

// MARK: - Animated Tick View

private struct AnimatedTickView: View {
    let tick: AxisTick; let targetX: CGFloat; let exitX: CGFloat
    let hPad: CGFloat; let innerWidth: CGFloat; let isEntering: Bool

    @State private var currentX: CGFloat? = nil
    private let spring: Animation = .spring(response: 0.55, dampingFraction: 0.80)
    private var labelOffset: CGFloat {
        if tick.normX <= 0.10 { return 8 }
        if tick.normX >= 0.90 { return -8 }
        return 0
    }

    var body: some View {
        VStack(spacing: 2) {
            Text(tick.label)
                .font(.system(size: 9, weight: .medium)).foregroundColor(.secondary)
                .fixedSize().lineLimit(1).offset(x: labelOffset)
        }
        .position(x: currentX ?? (isEntering ? exitX : targetX), y: 10)
        .opacity(currentX == nil ? 0 : 1)
        .onAppear {
            if isEntering {
                currentX = exitX
                DispatchQueue.main.async { withAnimation(spring) { currentX = targetX } }
            } else { currentX = targetX }
        }
        .onChange(of: targetX) { _, newX in withAnimation(spring) { currentX = newX } }
    }
}

// MARK: - XAxisAnimatedLabels

struct XAxisAnimatedLabels<VM: ChartViewModelProtocol>: View {
    @ObservedObject var chartVM: VM
    let chartSize: CGSize

    private let hPad: CGFloat = 4
    @State private var renderedTicks: [AxisTick] = []
    @State private var exitingTicks:  [AxisTick] = []
    @State private var lastKnownX:    [Int: CGFloat] = [:]

    private var innerWidth: CGFloat { max(chartSize.width - hPad * 2, 1) }
    private var exitX:      CGFloat { chartSize.width + 40 }

    var body: some View {
        ZStack {
            ForEach(renderedTicks) { tick in
                let exponent = chartVM.selectedRange.xSpacingExponent
                let targetX  = hPad + pow(CGFloat(tick.normX), exponent) * innerWidth
                let isNew    = lastKnownX[tick.id] == nil
                AnimatedTickView(tick: tick, targetX: targetX, exitX: exitX,
                                 hPad: hPad, innerWidth: innerWidth, isEntering: isNew)
            }
            ForEach(exitingTicks) { tick in
                ExitingTickView(tick: tick, startX: lastKnownX[tick.id] ?? exitX, exitX: exitX,
                                spring: .spring(response: 0.6, dampingFraction: 0.78))
            }
        }
        .frame(height: 20).clipped()
        .onChange(of: chartVM.dataPoints) { _, newData in updateTicks(from: newData) }
        .onChange(of: chartVM.selectedRange) { _, _ in
            if !chartVM.dataPoints.isEmpty { updateTicks(from: chartVM.dataPoints) }
        }
        .onAppear {
            if !chartVM.dataPoints.isEmpty {
                renderedTicks = AxisTickGenerator.ticks(for: chartVM.dataPoints, range: chartVM.selectedRange, chartVM: chartVM)
            }
        }
    }

    private func updateTicks(from data: [StockDataPoint]) {
        guard chartSize.width > 0 else { return }
        let newTicks = AxisTickGenerator.ticks(for: data, range: chartVM.selectedRange, chartVM: chartVM)
        let newIDs   = Set(newTicks.map(\.id))
        let leaving  = renderedTicks.filter { !newIDs.contains($0.id) }
        if !leaving.isEmpty {
            exitingTicks = leaving
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.95) {
                exitingTicks = exitingTicks.filter { t in !leaving.contains(t) }
            }
        }
        let stayingIDs = Set(renderedTicks.map(\.id)).intersection(newIDs)
        for tick in newTicks where stayingIDs.contains(tick.id) {
            lastKnownX[tick.id] = hPad + CGFloat(tick.normX) * innerWidth
        }
        renderedTicks = newTicks
    }
}

// MARK: - Exiting Tick View

private struct ExitingTickView: View {
    let tick: AxisTick; let startX: CGFloat; let exitX: CGFloat; let spring: Animation

    @State private var gone = false
    private var labelOffset: CGFloat {
        if tick.normX <= 0.10 { return 14 }
        if tick.normX >= 0.90 { return -14 }
        return 0
    }

    var body: some View {
        VStack(spacing: 2) {
            Text(tick.label).font(.system(size: 9, weight: .medium)).foregroundColor(.secondary)
                .fixedSize().lineLimit(1).offset(x: labelOffset)
        }
        .position(x: gone ? exitX : startX, y: 10)
        .opacity(gone ? 0 : 1)
        .onAppear { withAnimation(spring) { gone = true } }
    }
}

// MARK: - Time Range Selector

struct TimeRangeSelectorView<VM: ChartViewModelProtocol>: View {
    @ObservedObject var chartVM: VM
    let onRangeChange: () -> Void
    var tintColor: Color = Color.PrimaryYellow

    var body: some View {
        Picker("Range", selection: $chartVM.selectedRange) {
            ForEach(TimeRange.allCases, id: \.self) { range in Text(range.rawValue).tag(range) }
        }
        .pickerStyle(.segmented).tint(tintColor)
        .onChange(of: chartVM.selectedRange) { _, _ in
            onRangeChange()
            Task { await chartVM.fetchChartData() }
        }
    }
}

// MARK: - MorphingXYLineShape

struct MorphingXYLineShape: Shape {
    var data: AnimatableChartData
    var animatableData: AnimatableChartData { get { data } set { data = newValue } }

    func path(in rect: CGRect) -> Path {
        let pts = data.points; guard pts.count > 1 else { return Path() }
        var path = Path(); path.move(to: CGPoint(x: pts[0].x, y: pts[0].y))
        let tension: CGFloat = 0.4
        for i in 1..<pts.count {
            let p0 = pts[max(i-2,0)]; let p1 = pts[i-1]; let p2 = pts[i]; let p3 = pts[min(i+1,pts.count-1)]
            let cp1 = CGPoint(x: (p1.x + (p2.x-p0.x)*tension).clamped(to: 0...rect.width),
                              y:  p1.y + (p2.y-p0.y)*tension)
            let cp2 = CGPoint(x: (p2.x - (p3.x-p1.x)*tension).clamped(to: 0...rect.width),
                              y:  p2.y - (p3.y-p1.y)*tension)
            path.addCurve(to: CGPoint(x: p2.x, y: p2.y), control1: cp1, control2: cp2)
        }
        return path
    }
}

// MARK: - MorphingXYAreaShape

struct MorphingXYAreaShape: Shape {
    var data: AnimatableChartData; var closingY: CGFloat
    var animatableData: AnimatablePair<AnimatableChartData, CGFloat> {
        get { AnimatablePair(data, closingY) }
        set { data = newValue.first; closingY = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let pts = data.points; guard pts.count > 1 else { return Path() }
        var path = Path(); path.move(to: CGPoint(x: pts[0].x, y: pts[0].y))
        let tension: CGFloat = 0.4
        for i in 1..<pts.count {
            let p0 = pts[max(i-2,0)]; let p1 = pts[i-1]; let p2 = pts[i]; let p3 = pts[min(i+1,pts.count-1)]
            let cp1 = CGPoint(x: (p1.x + (p2.x-p0.x)*tension).clamped(to: 0...rect.width),
                              y:  p1.y + (p2.y-p0.y)*tension)
            let cp2 = CGPoint(x: (p2.x - (p3.x-p1.x)*tension).clamped(to: 0...rect.width),
                              y:  p2.y - (p3.y-p1.y)*tension)
            path.addCurve(to: CGPoint(x: p2.x, y: p2.y), control1: cp1, control2: cp2)
        }
        path.addLine(to: CGPoint(x: pts.last!.x,  y: closingY))
        path.addLine(to: CGPoint(x: pts.first!.x, y: closingY))
        path.closeSubpath(); return path
    }
}

// MARK: - MorphingLineShape (legacy)

struct MorphingLineShape: Shape {
    var normalized: NormalizedChartData
    var animatableData: NormalizedChartData { get { normalized } set { normalized = newValue } }

    func path(in rect: CGRect) -> Path {
        let vals = normalized.values; guard vals.count > 1 else { return Path() }
        let topPad: CGFloat = 20; let bottomPad: CGFloat = 20; let usable = rect.height - topPad - bottomPad
        guard usable > 0 else { return Path() }
        let hPad: CGFloat = 4; let innerWidth = rect.width - hPad * 2
        let xMin = hPad; let xMax = hPad + innerWidth
        let pts: [CGPoint] = vals.enumerated().map { i, v in
            CGPoint(x: hPad + CGFloat(i) / CGFloat(vals.count-1) * innerWidth,
                    y: topPad + usable * CGFloat(1.0 - v.clamped(to: -0.05...1.05)))
        }
        var path = Path(); path.move(to: pts[0])
        let tension: CGFloat = 0.4
        for i in 1..<pts.count {
            let p0 = pts[max(i-2,0)]; let p1 = pts[i-1]; let p2 = pts[i]; let p3 = pts[min(i+1,pts.count-1)]
            let cp1 = CGPoint(x: (p1.x+(p2.x-p0.x)*tension).clamped(to: xMin...xMax), y: p1.y+(p2.y-p0.y)*tension)
            let cp2 = CGPoint(x: (p2.x-(p3.x-p1.x)*tension).clamped(to: xMin...xMax), y: p2.y-(p3.y-p1.y)*tension)
            path.addCurve(to: p2, control1: cp1, control2: cp2)
        }
        return path
    }
}

// MARK: - MorphingAreaShape (legacy)

struct MorphingAreaShape: Shape {
    var normalized: NormalizedChartData; var closingY: CGFloat
    var animatableData: NormalizedChartData { get { normalized } set { normalized = newValue } }

    func path(in rect: CGRect) -> Path {
        let vals = normalized.values; guard vals.count > 1 else { return Path() }
        let topPad: CGFloat = 20; let bottomPad: CGFloat = 20; let usable = rect.height - topPad - bottomPad
        guard usable > 0 else { return Path() }
        let hPad: CGFloat = 4; let innerWidth = rect.width - hPad * 2
        let xMin = hPad; let xMax = hPad + innerWidth
        let pts: [CGPoint] = vals.enumerated().map { i, v in
            CGPoint(x: hPad + CGFloat(i) / CGFloat(vals.count-1) * innerWidth,
                    y: topPad + usable * CGFloat(1.0 - v.clamped(to: -0.05...1.05)))
        }
        var path = Path(); path.move(to: pts[0])
        let tension: CGFloat = 0.4
        for i in 1..<pts.count {
            let p0 = pts[max(i-2,0)]; let p1 = pts[i-1]; let p2 = pts[i]; let p3 = pts[min(i+1,pts.count-1)]
            let cp1 = CGPoint(x: (p1.x+(p2.x-p0.x)*tension).clamped(to: xMin...xMax), y: p1.y+(p2.y-p0.y)*tension)
            let cp2 = CGPoint(x: (p2.x-(p3.x-p1.x)*tension).clamped(to: xMin...xMax), y: p2.y-(p3.y-p1.y)*tension)
            path.addCurve(to: p2, control1: cp1, control2: cp2)
        }
        path.addLine(to: CGPoint(x: xMax, y: closingY)); path.addLine(to: CGPoint(x: xMin, y: closingY))
        path.closeSubpath(); return path
    }
}

// MARK: - Rolling Price View

struct RollingPriceView: View {
    let price: Double; let fontSize: CGFloat; var isInteractive: Bool = false
    /// "IDX" | "NASDAQ" | "NYSE" | "ETF" — default "IDX" untuk backward-compat.
    var market: String = "IDX"
    private var formatted: String { formatPriceWithSymbol(price, market: market) }
    private var tokens: [(id: Int, char: Character)] { Array(formatted.enumerated()).map { ($0.offset, $0.element) } }

    var body: some View {
        HStack(spacing: 1) {
            ForEach(tokens, id: \.id) { token in
                if let digit = token.char.wholeNumberValue {
                    RollingPriceDigit(digit: digit, delay: Double(token.id) * 0.04, fontSize: fontSize)
                } else {
                    Text(String(token.char)).font(.system(size: fontSize, weight: .bold, design: .rounded))
                }
            }
        }
    }
}

struct RollingPriceDigit: View {
    let digit: Int; let delay: Double; let fontSize: CGFloat; var isInteractive: Bool = false
    private var digitHeight: CGFloat { fontSize * 1.25 }

    var body: some View {
        GeometryReader { _ in
            VStack(spacing: 0) {
                ForEach(0..<10) { n in
                    Text("\(n)").font(.system(size: fontSize, weight: .bold, design: .rounded)).frame(height: digitHeight)
                }
            }
            .offset(y: -CGFloat(digit) * digitHeight)
            .animation(
                isInteractive
                    ? .interpolatingSpring(stiffness: 40, damping: 20)
                    : .interpolatingSpring(stiffness: 120, damping: 28).delay(delay),
                value: digit
            )
        }
        .frame(width: fontSize * 0.65, height: digitHeight).clipped()
    }
}

// MARK: - Comparable clamp helper

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
}

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int { Swift.min(Swift.max(self, range.lowerBound), range.upperBound) }
}
