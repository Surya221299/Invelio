//
//  PortfolioView.swift
//  StockAppTryNew
//
//  Refactored: MVVM + Clean Architecture, Separation of Concerns, SOLID
//  View is purely declarative — all logic delegated to PortfolioViewModel.
//

import SwiftUI

// MARK: - PortfolioView

struct PortfolioView: View {

    @EnvironmentObject private var vm:     PortfolioViewModel
    @EnvironmentObject private var router: Router

    @State private var selectedStockForTrade: PortfolioItem? = nil

    private let accent  = Color.AccentGold
    private let green   = Color.ProfitGreen
    private let red     = Color.LossRed
    private let cardBg  = Color.appCardBackground

    // MARK: Filtered / sorted data (view-layer derived state only)

    private var activePositions: [PortfolioItem] {
        vm.items.filter { $0.quantity > 0 }.sorted { $0.value > $1.value }
    }

    private var aiRecommendations: [PortfolioItem] {
        vm.items.sorted { $0.sentiment.score > $1.sentiment.score }
                .prefix(5).map { $0 }
    }

    // MARK: Body

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                PortfolioPositionsSectionView(
                    positions: activePositions,
                    holdings:  vm.holdings,
                    onTapItem: { router.push(.portfolioDetail($0)) },
                    onTrade:   { selectedStockForTrade = $0 }
                )

                if let health = vm.health {
                    PortfolioDailyCard(health: health, isLoading: vm.isAnalyzingHealth)
                    PortfolioHealthCard(health: health)
                }

                AIRecommendationsSectionView(
                    recommendations: aiRecommendations,
                    onTapItem:       { router.push(.stockDetail($0)) }
                )
            }
            .padding(.top, 20)
            .padding(.bottom, 24)
        }
        .background(Color.DarkPurpleAppBackground.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .top) { portfolioTopBar }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $selectedStockForTrade) { stock in
            TradeSheetView(stock: stock)
                .presentationDetents([.large])
                .environmentObject(vm)
        }
        .task { await vm.fetchData(); await vm.analyzeHealth() }
    }

    // MARK: - Top Bar

    private var portfolioTopBar: some View {
        HStack {
            HStack(spacing: 0) {
                Text("MY")
                    .font(.title).fontWeight(.bold).foregroundColor(.primary)
                Text(" PORTFOLIO")
                    .font(.title).fontWeight(.bold).foregroundColor(accent)
            }
            Spacer()
            Button(action: { vm.resetPortfolio() }) {
                Image(systemName: "arrow.counterclockwise")
                    .foregroundColor(red)
                    .padding(8)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.DarkPurpleAppBackground)
    }

}

// MARK: - Portfolio Summary Card

struct PortfolioSummaryCardView: View {

    let summary:         PortfolioSummary
    let items:           [PortfolioItem]
    let holdings:        [Holding]

    @State private var selectedPoint: StockDataPoint? = nil
    @State private var isDragging:    Bool             = false

    private let accent = Color.AccentGold
    private let green  = Color.ProfitGreen
    private let red    = Color.PortfolioLossRed
    private let cardGradient = LinearGradient(
        colors: [Color(hex: "665EBF"), Color(hex: "3D3788")],
        startPoint: .top,
        endPoint: .bottom
    )

    // MARK: - Live values (mengikuti posisi drag di chart, fallback ke summary asli)

    private var displayedValue: Double {
        if isDragging, let point = selectedPoint { return point.close }
        return summary.totalStockValue
    }

    private var displayedProfitIDR: Double {
        if isDragging, let point = selectedPoint { return point.close - summary.totalCostBasis }
        return summary.totalProfitIDR
    }

    private var displayedGrowthPercent: Double {
        guard summary.totalCostBasis > 0 else { return 0 }
        if isDragging, let point = selectedPoint {
            return ((point.close - summary.totalCostBasis) / summary.totalCostBasis) * 100
        }
        return summary.growthPercent
    }

    var body: some View {
        // alignment: .leading ditambahkan di sini — sebelumnya VStack ini
        // tidak punya alignment eksplisit (default .center), jadi grup teks
        // "Portfolio"/nilai/badge (yang lebih sempit) ke-tengah-tengahkan
        // relatif terhadap lebar chart di bawahnya (yang full-width card),
        // meskipun ISI grup teks itu sendiri sudah leading-aligned satu sama
        // lain. Dengan .leading di sini, seluruh blok grup teks nempel ke
        // tepi kiri card, sejajar dengan awal chart.
        VStack(alignment: .leading, spacing: 0) {
            // Total asset + growth badge
            VStack(alignment: .leading, spacing: 2) {
                Text("Total Assets")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.75))
                // Saat men-scrub chart, tampilkan nilai portofolio pada titik yang
                // dipilih (mengikuti crosshair). Di luar drag, kembalikan ke
                // animator live (roll/flash dari nilai server).
                if isDragging {
                    Text(formatIDR(displayedValue))
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                } else {
                    PortfolioValueAnimator()
                }
                let isPos = displayedGrowthPercent >= 0
                HStack(spacing: 8) {
                    Text(isPos ? "+\(formatIDR(displayedProfitIDR))" : formatIDR(displayedProfitIDR))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(isPos ? green : red)

                    HStack(spacing: 4) {
                        Text(String(format: "%+.2f%%", displayedGrowthPercent))
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundColor(isPos ? green : red)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background((isPos ? green : red).opacity(0.18))
                    .clipShape(Capsule())
                }
            }
            .animation(.easeOut(duration: 0.15), value: isDragging)

            // Chart section is embedded below, inside the same card
            PortfolioChartSectionView(items: items, holdings: holdings,
                                       selectedPoint: $selectedPoint, isDragging: $isDragging)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 8)
        .background(cardGradient)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.12), lineWidth: 1))
        .padding(.horizontal, 16)
    }
}

// MARK: - Portfolio Chart Section

struct PortfolioChartSectionView: View {

    let items:    [PortfolioItem]
    let holdings: [Holding]

    @Binding var selectedPoint: StockDataPoint?
    @Binding var isDragging:    Bool

    @StateObject private var chartVM = PortfolioChartViewModel()
    @State private var chartSize:     CGSize = .zero

    private let orange = Color.PortfolioOrange
    private let areaGradientStops: [Gradient.Stop] = [
        .init(color: Color.PortfolioOrange.opacity(0.30), location: 0.0),
        .init(color: Color.PortfolioOrange.opacity(0.0),  location: 0.88)
    ]

    private var isEmptyPortfolio: Bool {
        let activeItems = items.filter { $0.quantity > 0 }
        let currentTotal = activeItems.reduce(0) { $0 + $1.value }
        return currentTotal == 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isEmptyPortfolio {
                emptyFlatLineChart
            } else {
                ChartCanvasView(
                    chartVM:                  chartVM,
                    selectedPoint:            $selectedPoint,
                    isDragging:               $isDragging,
                    chartSize:                $chartSize,
                    accentColor:              orange,
                    displayIsPositive:        true,
                    fixedColor:               orange,
                    revealOnFirstLoad:        true,
                    useHighPriorityDrag:      true,
                    showAreaGradient:         true,
                    lineWidth:                1.0,
                    containerBackgroundColor: .clear,
                    customAreaGradientStops:  areaGradientStops
                )
                .frame(height: 135)
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .onAppear { chartSize = geo.size }
                            .onChange(of: geo.size) { _, s in chartSize = s }
                    }
                )

                if !chartVM.dataPoints.isEmpty {
                    XAxisAnimatedLabels(chartVM: chartVM, chartSize: chartSize)
                        .padding(.top, -10)
                }
            }

            PortfolioTimeRangeSelectorView(chartVM: chartVM, holdings: holdings, onRangeChange: {
                selectedPoint = nil
                isDragging    = false
            }, tintColor: orange)
        }
        .animation(.easeInOut(duration: 0.3), value: isEmptyPortfolio)
        .task { chartVM.update(items: items, holdings: holdings) }
        .onChange(of: items)    { _, newItems    in chartVM.update(items: newItems, holdings: holdings) }
        .onChange(of: holdings) { _, newHoldings in chartVM.update(items: items, holdings: newHoldings) }
        .onChange(of: chartSize) { _, newSize in
            guard newSize.width > 0, !chartVM.dataPoints.isEmpty else { return }
            Task { await chartVM.fetchChartData() }
        }
    }

    private var emptyFlatLineChart: some View {
        GeometryReader { geo in
            let midY = geo.size.height / 2
            ZStack(alignment: .leading) {
                // Area gradient di bawah garis datar
                Path { path in
                    path.move(to: CGPoint(x: 0, y: midY))
                    path.addLine(to: CGPoint(x: geo.size.width, y: midY))
                    path.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height))
                    path.addLine(to: CGPoint(x: 0, y: geo.size.height))
                    path.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: orange.opacity(0.20), location: 0.0),
                            .init(color: orange.opacity(0.0),  location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                // Garis datar tepat di tengah vertikal (center vertical)
                Path { path in
                    path.move(to: CGPoint(x: 0, y: midY))
                    path.addLine(to: CGPoint(x: geo.size.width, y: midY))
                }
                .stroke(orange, lineWidth: 1.0)

                // Titik kecil di ujung kanan garis agar serasi dengan chart aktif
                Circle()
                    .fill(orange)
                    .frame(width: 5, height: 5)
                    .position(x: max(geo.size.width - 4, 0), y: midY)
            }
        }
        .frame(height: 135)
    }
}

// MARK: - Active Positions Section

struct PortfolioPositionsSectionView: View {

    let positions: [PortfolioItem]
    let holdings:  [Holding]
    let onTapItem: (PortfolioItem) -> Void
    let onTrade:   (PortfolioItem) -> Void

    private let green  = Color.ProfitGreen
    private let red    = Color.LossRed
    private let cardBg = Color.appCardBackground

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Portofolio Aktif Saya")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.primary)
                .padding(.horizontal, 16)

            if positions.isEmpty {
                emptyPositionsPlaceholder
            } else {
                positionsList
            }
        }
    }

    private var emptyPositionsPlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "briefcase")
                .font(.system(size: 32)).foregroundColor(.secondary).padding(.bottom, 4)
            Text("Belum Ada Kepemilikan Saham")
                .font(.system(size: 13, weight: .bold)).foregroundColor(.primary)
            Text("Belum ada kepemilikan saham. Tambah saham pertama Anda untuk mulai tracking.")
                .font(.system(size: 11)).foregroundColor(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.primary.opacity(0.08), lineWidth: 1))
        .padding(.horizontal, 16)
    }

    private var positionsList: some View {
        VStack(spacing: 0) {
            ForEach(positions) { item in
                VStack(spacing: 0) {
                    PortfolioPositionRowView(
                        item:     item,
                        holding:  holdings.first { $0.symbol == item.symbol },
                        onTap:    { onTapItem(item) }
                    )
                    if item.symbol != positions.last?.symbol {
                        Divider().background(Color.primary.opacity(0.08))
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .background(cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.primary.opacity(0.08), lineWidth: 1))
        .padding(.horizontal, 16)
    }
}

// MARK: - Position Row

struct PortfolioPositionRowView: View {

    let item:    PortfolioItem
    let holding: Holding?
    let onTap:   () -> Void

    private let green = Color.ProfitGreen
    private let red   = Color.LossRed

    private var profitIDR: Double {
        let avgCost = (holding?.totalCostBasis ?? item.value) / max(item.quantity, 1)
        return item.value - (item.quantity * avgCost)
    }

    var body: some View {
        HStack {
            StockAvatarView(symbol: item.symbol)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.symbol).font(.system(size: 14, weight: .bold)).foregroundColor(.primary)
                Text("\(Int(item.quantity)) lembar").font(.caption2).foregroundColor(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(formatIDR(item.value))
                    .font(.system(size: 14, weight: .bold, design: .rounded)).foregroundColor(.primary)
                Text(profitIDR >= 0 ? "+\(formatIDR(profitIDR))" : formatIDR(profitIDR))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(profitIDR >= 0 ? green : red)
            }
            .padding(.trailing, 8)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }
}

// MARK: - AI Recommendations Section

struct AIRecommendationsSectionView: View {

    let recommendations: [PortfolioItem]
    let onTapItem:       (PortfolioItem) -> Void

    private let green  = Color.ProfitGreen
    private let red    = Color.LossRed
    private let cardBg = Color.appCardBackground

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Rekomendasi Trading AI (Top 5)")
                    .font(.system(size: 15, weight: .bold)).foregroundColor(.primary)
                Text("Saham terbaik minggu ini disaring oleh model multi-timeframe trend & fundamental.")
                    .font(.system(size: 10)).foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)

            VStack(spacing: 0) {
                ForEach(recommendations) { item in
                    VStack(spacing: 0) {
                        AIRecommendationRowView(item: item, onTap: { onTapItem(item) })
                        if item.symbol != recommendations.last?.symbol {
                            Divider().background(Color.primary.opacity(0.08))
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .background(cardBg)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.primary.opacity(0.08), lineWidth: 1))
            .padding(.horizontal, 16)
        }
    }
}

// MARK: - AI Recommendation Row

struct AIRecommendationRowView: View {

    let item:  PortfolioItem
    let onTap: () -> Void

    private let green = Color.ProfitGreen
    private let red   = Color.LossRed

    var body: some View {
        HStack {
            StockAvatarView(symbol: item.symbol)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.symbol)
                        .font(.system(size: 14, weight: .bold)).foregroundColor(.primary)
                        .fixedSize(horizontal: true, vertical: false)
                    SentimentPillView(sentiment: item.sentiment, size: .small)
                        .fixedSize(horizontal: true, vertical: false)
                }
                Text(item.name ?? "-")
                    .font(.caption2).foregroundColor(.secondary).lineLimit(1).truncationMode(.tail)
                SentimentBarView(sentiment: item.sentiment)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(formatIDR(item.price))
                    .font(.system(size: 14, weight: .semibold)).foregroundColor(.primary)
                    .fixedSize(horizontal: true, vertical: false)
                Text(String(format: "%+.2f%%", item.percentChange))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(item.percentChange >= 0 ? green : red)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.trailing, 8)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }
}


// MARK: - Trade Sheet View

struct TradeSheetView: View {

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var vm: PortfolioViewModel

    let stock: PortfolioItem
    /// Tipe transaksi awal saat sheet dibuka (0 = Beli, 1 = Jual).
    /// Default 0 supaya call-site lama tetap kompatibel.
    var initialTradeType: Int = 0
    /// Kalau true, segmented control Beli/Jual disembunyikan — sheet dikunci ke
    /// `initialTradeType` (dipakai saat dibuka dari tombol Buy/Jual terpisah di
    /// StockDetailView yang sudah menentukan aksinya).
    var lockTradeType: Bool = false

    @State private var tradeType      = 0  // 0 = Beli, 1 = Jual
    @State private var useNominal     = true
    @State private var tradeAmountStr = ""
    @State private var buyDate        = Date()
    @State private var historicalPrice:    Double? = nil
    // isHolidayDate dihapus — IDXTradingCalendar.isTradingDay sudah mencakup tanggal merah.
    @State private var isFetchingHistory   = false
    @State private var message:       String? = nil
    @State private var isError        = false
    @FocusState private var isInputFocused: Bool

    private let accent         = Color.AccentGold
    private let green          = Color.ProfitGreen
    private let red            = Color.LossRed
    private let cardBg         = Color.appCardBackground
    private let quickIDR:  [Double] = [1_000_000, 5_000_000, 10_000_000, 50_000_000]
    private let quickLots: [Double] = [1, 5, 10, 50]

    private var isBackdated: Bool {
        tradeType == 0 && !Calendar.current.isDateInToday(buyDate)
    }
    /// `true` jika tanggal yang dipilih bukan hari bursa (weekend ATAU tanggal merah IDX).
    /// Delegasi ke IDXTradingCalendar — single source of truth.
    private var isWeekendDate: Bool {
        !IDXTradingCalendar.isTradingDay(buyDate)
    }
    /// Harga yang dipakai untuk transaksi: harga live untuk hari ini, atau harga
    /// closing IDX sungguhan pada tanggal yang dipilih kalau backdated.
    private var price: Double {
        isBackdated ? (historicalPrice ?? stock.price) : stock.price
    }

    private var inputAmount: Double {
        Double(tradeAmountStr.filter { "0123456789".contains($0) }) ?? 0
    }
    private var calculatedLots:   Double {
        useNominal ? floor(inputAmount / (price * 100.0)) : inputAmount
    }
    private var calculatedShares: Double { calculatedLots * 100.0 }
    private var subtotal:         Double { calculatedShares * price }
    private var transactionFee:   Double { subtotal * (tradeType == 0 ? 0.0 : 0.0030) }
    private var estTotal:         Double { tradeType == 0 ? subtotal + transactionFee : subtotal - transactionFee }
    private var ownedQty:         Double { vm.holdings.first { $0.symbol == stock.symbol }?.quantity ?? 0 }

    private var canExecute: Bool {
        guard calculatedShares > 0 else { return false }
        if tradeType == 0 {
            if isWeekendDate || isFetchingHistory { return false }
            if isBackdated && historicalPrice == nil { return false }
            return true   // tidak ada pembatasan saldo — langsung add share
        }
        return calculatedShares <= ownedQty
    }

    private func formatShortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "d MMM yyyy"
        f.locale = Locale(identifier: "id_ID")
        return f.string(from: date)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if !lockTradeType {
                    Picker("Tipe Transaksi", selection: $tradeType) {
                        Text("JUAL").tag(1); Text("BELI").tag(0)
                    }
                    .pickerStyle(.segmented).padding(.top, 12)
                }

                // Stock info bar
                HStack(spacing: 12) {
                    StockAvatarView(symbol: stock.symbol)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(stock.symbol).font(.system(size: 16, weight: .bold)).foregroundColor(.primary)
                        Text(stock.name ?? "-").font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        if isBackdated && isFetchingHistory {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Text(formatIDR(price))
                                .font(.system(size: 16, weight: .bold, design: .rounded)).foregroundColor(.primary)
                        }
                        Text(isBackdated ? "Harga closing \(formatShortDate(buyDate))" : "Harga saat ini")
                            .font(.caption2).foregroundColor(.secondary)
                    }
                }
                .padding().background(cardBg).cornerRadius(12)

                // Holdings quick info
                HStack {
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text("Saham Dimiliki").font(.caption2).foregroundColor(.secondary)
                        Text("\(Int(ownedQty)) lembar (\(Int(ownedQty / 100)) Lot)")
                            .font(.system(size: 14, weight: .bold)).foregroundColor(.primary)
                    }
                }
                .padding(.horizontal, 4)

                // Input type picker
                Picker("Input Tipe", selection: $useNominal) {
                    Text("Nominal (Rupiah)").tag(true); Text("Jumlah Lot").tag(false)
                }
                .pickerStyle(.segmented)

                // Backdated purchase date (simulasi "add lot" — misal beli 3 bulan lalu)
                if tradeType == 0 {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 4) {
                            Text("Tanggal Pembelian").font(.caption).foregroundColor(.secondary)
                            Text("(untuk simulasi)").font(.caption2).foregroundColor(.secondary.opacity(0.7))
                        }
                        DatePicker("", selection: $buyDate, in: ...Date(), displayedComponents: .date)
                            .datePickerStyle(.compact)
                            .labelsHidden()
                            .tint(accent)

                        if isWeekendDate {
                            // isWeekendDate = !IDXTradingCalendar.isTradingDay → mencakup weekend + tanggal merah
                            Text("Tanggal ini bukan hari bursa (libur / tanggal merah IDX) — pilih hari perdagangan lain.")
                                .font(.system(size: 11, weight: .semibold)).foregroundColor(red)
                        } else if isBackdated, let hp = historicalPrice {
                            Text("Harga closing \(stock.symbol) pada \(formatShortDate(buyDate)): \(formatIDR(hp))")
                                .font(.system(size: 11, weight: .medium)).foregroundColor(.secondary)
                        }
                    }
                    .padding(12)
                    .background(cardBg)
                    .cornerRadius(10)
                    .onChange(of: buyDate) { _, newDate in
                        historicalPrice = nil
                        // isWeekendDate sudah cek via IDXTradingCalendar (termasuk tanggal merah)
                        guard !isWeekendDate, !Calendar.current.isDateInToday(newDate) else { return }
                        Task {
                            isFetchingHistory = true
                            if let result = await vm.historicalClosePrice(symbol: stock.symbol, date: newDate) {
                                historicalPrice = result.price
                            }
                            isFetchingHistory = false
                        }
                    }
                }

                // Amount input
                VStack(alignment: .leading, spacing: 8) {
                    Text(useNominal ? "Nominal Transaksi (IDR)" : "Jumlah Pembelian (Lot)")
                        .font(.caption).foregroundColor(.secondary)
                    TextField(useNominal ? "Masukkan nominal Rupiah" : "Masukkan jumlah Lot",
                              text: $tradeAmountStr)
                        .keyboardType(.numberPad)
                        .focused($isInputFocused)
                        .padding()
                        .background(Color(.systemFill))
                        .cornerRadius(10)
                        .foregroundColor(.primary)
                        .font(.system(size: 16, weight: .bold))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(accent.opacity(0.3), lineWidth: 1))
                }

                // Quick amount buttons
                HStack(spacing: 8) {
                    if useNominal {
                        ForEach(quickIDR, id: \.self) { amount in
                            Button(action: { tradeAmountStr = String(format: "%.0f", amount) }) {
                                Text(formatIDRShort(amount))
                                    .font(.system(size: 12, weight: .bold)).foregroundColor(.primary)
                                    .padding(.vertical, 8).frame(maxWidth: .infinity)
                                    .background(Color.primary.opacity(0.08)).cornerRadius(8)
                            }
                        }
                    } else {
                        ForEach(quickLots, id: \.self) { lot in
                            Button(action: { tradeAmountStr = String(format: "%.0f", lot) }) {
                                Text("\(Int(lot)) Lot")
                                    .font(.system(size: 12, weight: .bold)).foregroundColor(.primary)
                                    .padding(.vertical, 8).frame(maxWidth: .infinity)
                                    .background(Color.primary.opacity(0.08)).cornerRadius(8)
                            }
                        }
                    }
                }

                // Invoice summary
                TradeInvoiceView(
                    calculatedLots:   calculatedLots,
                    calculatedShares: calculatedShares,
                    subtotal:         subtotal,
                    fee:              transactionFee,
                    estTotal:         estTotal,
                    tradeType:        tradeType
                )

                // Validation warning
                let minLotPrice = price * 100.0
                if useNominal, inputAmount > 0, inputAmount < minLotPrice {
                    Text("Nominal di bawah batas minimum 1 Lot (Rp \(formatIDR(minLotPrice)))")
                        .font(.system(size: 11, weight: .semibold)).foregroundColor(red)
                }

                if let msg = message {
                    Text(msg)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(isError ? red : green)
                        .multilineTextAlignment(.center)
                }

                Spacer()

                Button(action: executeTrade) {
                    Text(tradeType == 0 ? "Eksekusi Beli Saham" : "Eksekusi Jual Saham")
                        .font(.system(size: 15, weight: .bold)).foregroundColor(.black)
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(tradeType == 0 ? accent : green).cornerRadius(12)
                }
                .disabled(!canExecute).opacity(canExecute ? 1.0 : 0.4)
            }
            .padding(16)
            .background(Color.DarkPurpleAppBackground.ignoresSafeArea())
            .onAppear { tradeType = initialTradeType }
            .navigationTitle("Transaksi Simulator")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Batal") { dismiss() }.foregroundColor(.secondary)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Selesai") { isInputFocused = false }
                        .foregroundColor(accent).fontWeight(.bold)
                }
            }
        }
    }

    private func executeTrade() {
        guard canExecute else { return }
        let qty = calculatedShares
        if tradeType == 0 {
            vm.buy(symbol: stock.symbol, amountIDR: subtotal, price: price, date: buyDate)
            message = "Berhasil membeli \(Int(calculatedLots)) Lot (\(Int(qty)) lembar) \(stock.symbol)!"
        } else {
            vm.sell(symbol: stock.symbol, quantity: qty)
            message = "Berhasil menjual \(Int(calculatedLots)) Lot (\(Int(qty)) lembar) \(stock.symbol)!"
        }
        isError = false
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { dismiss() }
    }
}

// MARK: - Portfolio Time Range Selector View
//
// Versi TimeRangeSelectorView khusus PortfolioSummaryCardView.
// Perbedaan utama vs TimeRangeSelectorView generik:
//   • 1D selalu DIHAPUS — tidak relevan untuk chart growth portofolio.
//   • 1W selalu WAJIB ada (range minimum).
//   • 3M hanya muncul jika user pernah add lot ≥ 3 bulan lalu.
//   • 5Y hanya muncul jika user pernah add saham di tahun 2022 atau sebelumnya.
//   • Range lain (1M, YTD, 1Y) selalu ditampilkan selama ada holding aktif.
//
// Logic ini membuat selector tumbuh secara organik sesuai panjang histori
// portofolio user — bukan menampilkan semua range sekaligus di hari pertama.

struct PortfolioTimeRangeSelectorView<VM: ChartViewModelProtocol>: View {

    @ObservedObject var chartVM: VM
    let holdings:       [Holding]
    let onRangeChange:  () -> Void
    var tintColor:      Color = Color.VibrantOrange

    // MARK: - Computed: ranges yang relevan berdasarkan histori holding

    /// Tanggal pembelian paling awal dari semua holding.
    private var earliestPurchase: Date? {
        holdings.compactMap { $0.purchaseDate }.min()
    }

    /// Jumlah hari sejak pembelian pertama (0 jika belum pernah beli).
    private var daysSinceEarliestPurchase: Int {
        guard let earliest = earliestPurchase else { return 0 }
        return Calendar.current.dateComponents([.day], from: earliest, to: Date()).day ?? 0
    }

    /// Tahun pembelian pertama.
    private var earliestPurchaseYear: Int? {
        guard let earliest = earliestPurchase else { return nil }
        return Calendar.current.component(.year, from: earliest)
    }

    /// Daftar TimeRange yang ditampilkan, sesuai histori portofolio user.
    private var availableRanges: [TimeRange] {
        var ranges: [TimeRange] = [.oneWeek]    // 1W selalu wajib ada

        // 1M: selalu tampil (bahkan jika baru beli kemarin — chart tetap bisa
        //     di-render, hanya akan pendek)
        ranges.append(.oneMonth)

        // 3M: muncul jika ada lot yang dibeli ≥ 90 hari lalu
        if daysSinceEarliestPurchase >= 90 {
            ranges.append(.threeMonth)
        }

        // YTD: tampil jika pembelian pertama sudah di tahun yang sama atau lebih awal
        ranges.append(.ytd)

        // 1Y: tampil jika portofolio sudah ada ≥ 365 hari
        if daysSinceEarliestPurchase >= 365 {
            ranges.append(.oneYear)
        }

        // 5Y: tampil jika user pernah add saham di tahun 2022 atau lebih lama
        if let year = earliestPurchaseYear, year <= 2022 {
            ranges.append(.fiveYear)
        }

        // All: selalu ada di paling kanan — menampilkan seluruh histori sejak
        // pembelian pertama. Berguna berapapun panjang portofolio.
        ranges.append(.all)

        return ranges
    }

    @Namespace private var animation

    var body: some View {
        HStack(spacing: 2) {
            ForEach(availableRanges, id: \.self) { range in
                let isSelected = chartVM.selectedRange == range
                Button {
                    guard chartVM.selectedRange != range else { return }
                    withAnimation(.easeInOut(duration: 0.2)) {
                        chartVM.selectedRange = range
                    }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    ZStack {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(tintColor)
                                .matchedGeometryEffect(id: "activePortfolioRange", in: animation)
                                .shadow(color: tintColor.opacity(0.35), radius: 3, y: 1)
                        }
                        Text(range.rawValue)
                            .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                            .foregroundColor(isSelected ? .black : .white.opacity(0.70))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .frame(height: 24)
        .background(Color.black.opacity(0.25))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .onChange(of: chartVM.selectedRange) { _, _ in
            onRangeChange()
            Task { await chartVM.fetchChartData() }
        }
        // Jika range yang sedang dipilih tidak lagi tersedia (misal user reset
        // portfolio), fallback ke 1W agar tidak ada state invalid.
        .onAppear {
            if !availableRanges.contains(chartVM.selectedRange) {
                chartVM.selectedRange = .oneWeek
            }
        }
        .onChange(of: holdings) { _, _ in
            if !availableRanges.contains(chartVM.selectedRange) {
                chartVM.selectedRange = .oneWeek
            }
        }
    }
}

// MARK: - Trade Invoice View


struct TradeInvoiceView: View {

    let calculatedLots:   Double
    let calculatedShares: Double
    let subtotal:         Double
    let fee:              Double
    let estTotal:         Double
    let tradeType:        Int

    private let accent = Color.AccentGold
    private let green  = Color.ProfitGreen
    private let cardBg = Color.appCardBackground

    var body: some View {
        VStack(spacing: 8) {
            invoiceRow(label: "Jumlah Transaksi",
                       value: "\(Int(calculatedLots)) Lot (\(Int(calculatedShares)) lembar)")
            invoiceRow(label: "Subtotal",                     value: formatIDR(subtotal))
            invoiceRow(label: "Broker Fee (Pajak + Levy)",    value: formatIDR(fee))
            Divider().background(Color.primary.opacity(0.1))
            invoiceRow(
                label:  tradeType == 0 ? "Total Estimasi Bayar" : "Total Estimasi Terima",
                value:  formatIDR(estTotal),
                isBold: true,
                color:  tradeType == 0 ? accent : green
            )
        }
        .padding()
        .background(cardBg)
        .cornerRadius(12)
    }

    private func invoiceRow(label: String, value: String,
                            isBold: Bool = false, color: Color = .primary) -> some View {
        HStack {
            Text(label).font(.system(size: 11)).foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: isBold ? .bold : .regular))
                .foregroundColor(color)
        }
    }
}
