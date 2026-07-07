//
//  DetailPortfolioPerEmitentView.swift
//  StockAppTryNew
//
//  Refactored: MVVM + Clean Architecture, Separation of Concerns, SOLID
//  View is purely declarative — all logic delegated to PortfolioViewModel.
//

import SwiftUI

// MARK: - DetailPortfolioPerEmitentView

struct DetailPortfolioPerEmitentView: View {

    let item: PortfolioItem

    @EnvironmentObject private var vm:     PortfolioViewModel
    @EnvironmentObject private var router: Router

    @State private var showTradeSheet = false
    @State private var chartData: [PortfolioValuePoint] = []
    @State private var isLoadingChart = false

    private let accent  = Color.PrimaryYellow
    private let green   = Color.ProfitGreen
    private let red     = Color.LossRed
    //private let bgColor = Color.appBackground

    // MARK: - Derived holding data (computed, not business logic)
    // MARK: - Derived holding data (computed, not business logic)

    private var holding: Holding? {
        vm.holdings.first { $0.symbol == item.symbol }
    }

    private var hasPurchaseDate: Bool { holding?.purchaseDate != nil }

    private var purchaseDate: Date {
        holding?.purchaseDate
            ?? Calendar.current.date(byAdding: .day, value: -30, to: Date())!
    }

    private var costBasis:   Double { holding?.totalCostBasis ?? 0 }
    private var avgBuyPrice: Double { item.quantity > 0 ? costBasis / item.quantity : 0 }
    private var profitIDR:   Double { item.value - costBasis }
    private var profitPct:   Double { costBasis > 0 ? (profitIDR / costBasis) * 100 : 0 }

    private func reloadChartData() async {
        guard item.quantity > 0 else { chartData = []; return }
        isLoadingChart = true
        chartData = await vm.holdingValueHistory(symbol: item.symbol, quantity: item.quantity, since: purchaseDate)
        isLoadingChart = false
    }

    private var tradeRecords: [TradeRecord] {
        vm.tradeHistory.filter { $0.symbol == item.symbol }
    }

    private var symbolLots: [Lot] {
        vm.lots.filter { $0.symbol == item.symbol }.sorted { $0.buyDate > $1.buyDate }
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                EmitentStockHeaderCard(
                    item:      item,
                    profitIDR: profitIDR,
                    profitPct: profitPct,
                    green:     green,
                    red:       red
                )

                EmitentChartSection(
                    chartData:       chartData,
                    hasPurchaseDate: hasPurchaseDate,
                    isLoading:       isLoadingChart
                )

                EmitentHoldingDetailsCard(
                    item:        item,
                    holding:     holding,
                    avgBuyPrice: avgBuyPrice,
                    costBasis:   costBasis,
                    profitIDR:   profitIDR,
                    profitPct:   profitPct,
                    green:       green,
                    red:         red
                )

                if !symbolLots.isEmpty {
                    EmitentLotPerformanceSection(
                        lots:          symbolLots,
                        currentPrice:  item.price,
                        green:         green,
                        red:           red
                    )
                }

                if !tradeRecords.isEmpty {
                    EmitentTradeHistorySection(
                        records: tradeRecords,
                        accent:  accent,
                        green:   green,
                        red:     red
                    )
                }

                EmitentActionButtons(
                    accent:          accent,
                    onSeeDetails:    { router.push(.stockDetail(item)) },
                    onTrade:         { showTradeSheet = true }
                )
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .background(Color.DarkPurpleAppBackground.ignoresSafeArea())
        .navigationTitle(item.symbol)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showTradeSheet) {
            TradeSheetView(stock: item)
                .presentationDetents([.large])
                .environmentObject(vm)
        }
        .task(id: purchaseDate) { await reloadChartData() }
        .onChange(of: item.quantity) { _, _ in Task { await reloadChartData() } }
    }
}

// MARK: - Lot Performance Section
// Membandingkan harga beli tiap lot (termasuk lot yang di-backdate, misal "beli
// 3 bulan lalu") dengan harga pasar saat ini — tanpa perlu menyimpan histori
// harga harian, cukup pakai harga-beli yang sudah tercatat per lot.

struct EmitentLotPerformanceSection: View {

    let lots:         [Lot]
    let currentPrice: Double
    let green:        Color
    let red:          Color

    private let cardBg = Color.appCardBackground

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Performa per Lot")
                    .font(.system(size: 14, weight: .bold)).foregroundColor(.primary)
                Spacer()
                Text("\(lots.count) lot")
                    .font(.system(size: 11)).foregroundColor(.secondary)
            }

            Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)

            VStack(spacing: 0) {
                ForEach(lots) { lot in
                    VStack(spacing: 0) {
                        LotRowView(lot: lot, currentPrice: currentPrice, green: green, red: red)
                        if lot.id != lots.last?.id {
                            Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 1)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.primary.opacity(0.08), lineWidth: 1))
    }
}

struct LotRowView: View {

    let lot:          Lot
    let currentPrice: Double
    let green:        Color
    let red:          Color

    private var profitIDR: Double { (currentPrice - lot.buyPrice) * lot.quantity }
    private var profitPct: Double { lot.buyPrice > 0 ? (currentPrice - lot.buyPrice) / lot.buyPrice * 100 : 0 }
    private var daysHeld:  Int    { Calendar.current.dateComponents([.day], from: lot.buyDate, to: Date()).day ?? 0 }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(Int(lot.quantity)) lembar @ \(formatIDR(lot.buyPrice))")
                    .font(.system(size: 12, weight: .semibold)).foregroundColor(.primary)
                Text("\(formatDate(lot.buyDate)) · \(daysHeld) hari lalu")
                    .font(.system(size: 10)).foregroundColor(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(profitIDR >= 0 ? "+\(formatIDR(profitIDR))" : formatIDR(profitIDR))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(profitIDR >= 0 ? green : red)
                Text(String(format: "%+.2f%%", profitPct))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(profitIDR >= 0 ? green : red)
            }
        }
        .padding(.vertical, 10)
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "d MMM yyyy"
        f.locale = Locale(identifier: "id_ID")
        return f.string(from: date)
    }
}

// MARK: - Stock Header Card

struct EmitentStockHeaderCard: View {

    let item:      PortfolioItem
    let profitIDR: Double
    let profitPct: Double
    let green:     Color
    let red:       Color

    private let cardBg = Color.appCardBackground

    var body: some View {
        VStack(spacing: 12) {
            // Symbol row
            HStack(spacing: 12) {
                StockAvatarView(symbol: item.symbol)

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.symbol)
                        .font(.system(size: 18, weight: .bold)).foregroundColor(.primary)
                    Text(item.name ?? "-")
                        .font(.system(size: 11)).foregroundColor(.secondary).lineLimit(1)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    Text(formatIDR(item.price))
                        .font(.system(size: 16, weight: .bold, design: .rounded)).foregroundColor(.primary)
                    let isPos = item.percentChange >= 0
                    HStack(spacing: 3) {
                        Image(systemName: isPos ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 8, weight: .bold))
                        Text(String(format: "%+.2f%%", item.percentChange))
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundColor(isPos ? green : red)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background((isPos ? green : red).opacity(0.12))
                    .clipShape(Capsule())
                }
            }

            Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)

            // Value + P&L summary
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Nilai Kepemilikan")
                        .font(.system(size: 10)).foregroundColor(.secondary)
                    Text(formatIDR(item.value))
                        .font(.system(size: 24, weight: .bold, design: .rounded)).foregroundColor(.primary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Profit / Loss")
                        .font(.system(size: 10)).foregroundColor(.secondary)
                    Text(profitIDR >= 0 ? "+\(formatIDR(profitIDR))" : formatIDR(profitIDR))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(profitIDR >= 0 ? green : red)
                    Text(String(format: "%+.2f%%", profitPct))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(profitIDR >= 0 ? green : red)
                }
            }
        }
        .padding(16)
        .background(cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.primary.opacity(0.08), lineWidth: 1))
    }
}

// MARK: - Chart Section

struct EmitentChartSection: View {

    let chartData:       [PortfolioValuePoint]
    let hasPurchaseDate: Bool
    let isLoading:       Bool

    private let cardBg = Color.appCardBackground

    var body: some View {
        if isLoading && chartData.isEmpty {
            ProgressView().tint(.PrimaryYellow)
                .frame(maxWidth: .infinity)
                .frame(height: 160)
                .background(cardBg)
                .clipShape(RoundedRectangle(cornerRadius: 16))
        } else if !chartData.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Grafik Nilai Kepemilikan")
                        .font(.system(size: 13, weight: .bold)).foregroundColor(.primary)
                    Spacer()
                    if !hasPurchaseDate {
                        HStack(spacing: 3) {
                            Image(systemName: "info.circle").font(.system(size: 9))
                            Text("Estimasi 30 hari").font(.system(size: 9, weight: .medium))
                        }
                        .foregroundColor(.secondary)
                    }
                }

                PortfolioHistoryChart(data: chartData)
                    .background(cardBg)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.primary.opacity(0.08), lineWidth: 1))
            }
        }
    }
}

// MARK: - Holding Details Card

struct EmitentHoldingDetailsCard: View {

    let item:        PortfolioItem
    let holding:     Holding?
    let avgBuyPrice: Double
    let costBasis:   Double
    let profitIDR:   Double
    let profitPct:   Double
    let green:       Color
    let red:         Color

    private let cardBg = Color.appCardBackground

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Detail Kepemilikan")
                    .font(.system(size: 14, weight: .bold)).foregroundColor(.primary)
                Spacer()
            }

            Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)

            VStack(spacing: 10) {
                infoRow(label: "Jumlah Saham",
                        value: "\(Int(item.quantity)) lembar (\(Int(item.quantity / 100)) Lot)")
                infoRow(label: "Harga Rata-Rata Beli", value: formatIDR(avgBuyPrice))
                infoRow(label: "Total Modal",          value: formatIDR(costBasis))
                infoRow(label: "Nilai Pasar Saat Ini", value: formatIDR(item.value))

                Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)

                HStack {
                    Text("Profit / Loss")
                        .font(.system(size: 12)).foregroundColor(.secondary)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(profitIDR >= 0 ? "+\(formatIDR(profitIDR))" : formatIDR(profitIDR))
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(profitIDR >= 0 ? green : red)
                        Text(String(format: "%+.2f%%", profitPct))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(profitIDR >= 0 ? green : red)
                    }
                }

                if let pd = holding?.purchaseDate {
                    infoRow(label: "Tanggal Pertama Beli", value: formatDate(pd))
                    let daysSince = Calendar.current.dateComponents([.day], from: pd, to: Date()).day ?? 0
                    infoRow(label: "Lama Kepemilikan", value: "\(daysSince) hari")
                }
            }
        }
        .padding(16)
        .background(cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.primary.opacity(0.08), lineWidth: 1))
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 12)).foregroundColor(.secondary)
            Spacer()
            Text(value).font(.system(size: 12, weight: .semibold)).foregroundColor(.primary)
        }
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "d MMMM yyyy"
        f.locale = Locale(identifier: "id_ID")
        return f.string(from: date)
    }
}

// MARK: - Trade History Section

struct EmitentTradeHistorySection: View {

    let records: [TradeRecord]
    let accent:  Color
    let green:   Color
    let red:     Color

    private let cardBg = Color.appCardBackground

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Riwayat Transaksi")
                    .font(.system(size: 14, weight: .bold)).foregroundColor(.primary)
                Spacer()
                Text("\(records.count) transaksi")
                    .font(.system(size: 11)).foregroundColor(.secondary)
            }

            Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)

            VStack(spacing: 0) {
                ForEach(records) { record in
                    VStack(spacing: 0) {
                        TradeRecordRowView(record: record, accent: accent, green: green, red: red)
                        if record.id != records.last?.id {
                            Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 1)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.primary.opacity(0.08), lineWidth: 1))
    }
}

// MARK: - Trade Record Row

struct TradeRecordRowView: View {

    let record: TradeRecord
    let accent: Color
    let green:  Color
    let red:    Color

    var body: some View {
        HStack(spacing: 12) {
            Text(record.type == .buy ? "BELI" : "JUAL")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(record.type == .buy ? .black : .SurfaceWhite)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(record.type == .buy ? accent : red)
                .clipShape(Capsule())

            VStack(alignment: .leading, spacing: 2) {
                Text("\(Int(record.quantity)) lembar @ \(formatIDR(record.price))")
                    .font(.system(size: 12, weight: .semibold)).foregroundColor(.primary)
                Text(formatDateTime(record.date))
                    .font(.system(size: 10)).foregroundColor(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(record.type == .buy
                     ? "-\(formatIDR(record.totalAmount))"
                     : "+\(formatIDR(record.totalAmount))")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(record.type == .buy ? red : green)
                Text("fee \(formatIDR(record.fee))")
                    .font(.system(size: 9)).foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 10)
    }

    private func formatDateTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "d MMM yyyy, HH:mm"
        f.locale = Locale(identifier: "id_ID")
        return f.string(from: date)
    }
}

// MARK: - Action Buttons

struct EmitentActionButtons: View {

    let accent:       Color
    let onSeeDetails: () -> Void
    let onTrade:      () -> Void

    private let cardBg = Color.appCardBackground

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onSeeDetails) {
                HStack(spacing: 6) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                    Text("See Details")
                }
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(cardBg)
                .cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(accent.opacity(0.35), lineWidth: 1))
            }

            Button(action: onTrade) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.left.arrow.right")
                    Text("Trade")
                }
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(accent)
                .cornerRadius(12)
            }
        }
    }
}

