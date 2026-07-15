//
//  PortfolioViewModel.swift
//  StockAppTryNew
//
//  Created by Surya on 16/06/26.
//

import SwiftUI
import Combine

@MainActor
final class PortfolioViewModel: ObservableObject {

    // MARK: - Published State

    @Published private(set) var items:        [PortfolioItem] = []
    @Published private(set) var holdings:     [Holding]       = []
    @Published private(set) var tradeHistory: [TradeRecord]   = []
    @Published private(set) var lots:         [Lot]           = []
    @Published private(set) var isLoading:    Bool            = false
    @Published var errorMessage: String?

    /// Nilai saham terakhir yang tersimpan di cache (UserDefaults).
    /// Ditampilkan saat app baru buka sebelum data server tiba.
    @Published private(set) var cachedStockValue: Double = 0

    /// Nilai saham terbaru dari server. Nil selama belum ada response.
    @Published private(set) var serverStockValue: Double? = nil

    /// Hasil analisis kesehatan portofolio + narasi harian dari backend.
    @Published private(set) var health: PortfolioHealth? = nil
    @Published private(set) var isAnalyzingHealth: Bool = false

    private let cachedValueKey = "portfolio_cached_stock_value_v1"

    // MARK: - Computed

    var totalStockValue: Double { items.reduce(0) { $0 + $1.value } }
    var totalCostBasis:  Double { holdings.reduce(0) { $0 + $1.totalCostBasis } }
    var totalProfitIDR:  Double { totalStockValue - totalCostBasis }
    var summary: PortfolioSummary {
        PortfolioSummary(totalStockValue: totalStockValue, totalCostBasis: totalCostBasis)
    }

    // MARK: - Dependencies

    private let fetchStocksUseCase:   FetchStocksUseCase
    private let buyUseCase:           BuyStockUseCase
    private let sellUseCase:          SellStockUseCase
    private let portfolioRepository:  PortfolioRepositoryProtocol
    private let fetchChartUseCase:    FetchChartDataUseCase
    private let healthRepository:     PortfolioHealthRepositoryProtocol

    // MARK: - Init

    init(
        fetchStocksUseCase:   FetchStocksUseCase,
        buyUseCase:           BuyStockUseCase,
        sellUseCase:          SellStockUseCase,
        portfolioRepository:  PortfolioRepositoryProtocol,
        fetchChartUseCase:    FetchChartDataUseCase,
        healthRepository:     PortfolioHealthRepositoryProtocol
    ) {
        self.fetchStocksUseCase   = fetchStocksUseCase
        self.buyUseCase           = buyUseCase
        self.sellUseCase          = sellUseCase
        self.portfolioRepository  = portfolioRepository
        self.fetchChartUseCase    = fetchChartUseCase
        self.healthRepository     = healthRepository
        loadPersistedData()
        cachedStockValue = UserDefaults.standard.double(forKey: cachedValueKey)
    }

    // MARK: - Public Actions

    func fetchData() async {
        isLoading    = true
        errorMessage = nil
        let (newItems, _) = await fetchStocksUseCase.execute(holdings: holdings)
        items     = newItems
        isLoading = false
        // Simpan nilai baru ke cache dan expose sebagai serverStockValue.
        // Update juga saat nilai = 0 ASAL memang tidak ada kepemilikan aktif
        // (mis. semua saham sudah dijual / portfolio di-reset) — supaya saldo
        // benar-benar turun ke 0, bukan "stuck" di nilai terakhir. Nilai 0 saat
        // MASIH ada holding (mis. fetch gagal) tetap diabaikan agar cache aman.
        let newValue         = totalStockValue
        let hasActiveHolding = holdings.contains { $0.quantity > 0 }
        if newValue > 0 || !hasActiveHolding {
            serverStockValue = newValue
            UserDefaults.standard.set(newValue, forKey: cachedValueKey)
            cachedStockValue = newValue
        }
    }

    /// Analisis kesehatan portofolio + narasi harian dari backend.
    /// Dipanggil setelah data holdings siap (mis. di `.task` view) dan setelah
    /// transaksi buy/sell. Tidak dipanggil pada tiap refresh harga streaming
    /// karena memicu LLM lokal (mahal).
    func analyzeHealth() async {
        let active = holdings.filter { $0.quantity > 0 }
        guard !active.isEmpty else {
            health = nil
            return
        }
        isAnalyzingHealth = true
        defer { isAnalyzingHealth = false }
        do {
            health = try await healthRepository.analyze(holdings: active)
        } catch {
            // Diamkan — kartu kesehatan cukup disembunyikan bila gagal.
            print("[PortfolioVM] analyzeHealth gagal: \(error.localizedDescription)")
        }
    }

    /// - Parameter date: Tanggal pembelian. Default hari ini, tapi bisa di-backdate
    ///   (misalnya 3 bulan lalu) untuk simulasi "add lot" & perbandingan harga.
    func buy(symbol: String, amountIDR: Double, price: Double, date: Date = Date()) {
        let result = buyUseCase.execute(symbol: symbol, amountIDR: amountIDR,
                                        currentPrice: price, holdings: holdings,
                                        date: date)
        switch result {
        case .success(let r):
            holdings     = r.updatedHoldings
            tradeHistory.insert(r.tradeRecord, at: 0)
            lots.append(r.newLot)
            persist()
            Task { await fetchData(); await analyzeHealth() }
        case .failure(let err):
            errorMessage = err.errorDescription
        }
    }

    func sell(symbol: String, quantity: Double) {
        guard let price = items.first(where: { $0.symbol == symbol })?.price else { return }
        let result = sellUseCase.execute(symbol: symbol, quantity: quantity,
                                         currentPrice: price, holdings: holdings,
                                         lots: lots)
        switch result {
        case .success(let r):
            holdings    = r.updatedHoldings
            tradeHistory.insert(r.tradeRecord, at: 0)
            lots        = r.updatedLots
            persist()
            Task { await fetchData(); await analyzeHealth() }
        case .failure(let err):
            errorMessage = err.errorDescription
        }
    }

    /// Closing price IDX yang sebenarnya pada tanggal tertentu — dipakai saat
    /// "add lot" dengan tanggal mundur (backdated), supaya tidak salah pakai
    /// harga hari ini. Mencocokkan candle pada hari yang sama. `isTradingDay`
    /// `false` berarti tanggal itu libur bursa (akhir pekan/tanggal merah) —
    /// tidak ada candle persis di hari itu, jadi dipakai closing hari bursa
    /// terakhir sebelumnya sebagai referensi.
    func historicalClosePrice(symbol: String, date: Date) async -> (price: Double, isTradingDay: Bool)? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Jakarta")!

        let daysAgo = cal.dateComponents([.day], from: date, to: Date()).day ?? 0
        let (points, _) = await fetchChartUseCase.execute(symbol: symbol, range: Self.rangeFor(daysAgo: daysAgo))
        guard !points.isEmpty else { return nil }
        if let sameDay = points.first(where: { cal.isDate($0.date, inSameDayAs: date) }) {
            return (sameDay.close, true)
        }
        guard let prev = points.filter({ $0.date <= date }).max(by: { $0.date < $1.date }) else { return nil }
        return (prev.close, false)
    }

    /// Histori nilai kepemilikan yang RIIL (bukan simulasi) — harga candle asli
    /// dikali jumlah lembar, mulai persis dari tanggal pembelian (`purchaseDate`)
    /// sampai sekarang. Dipakai oleh grafik "Nilai Kepemilikan" per emiten.
    func holdingValueHistory(symbol: String, quantity: Double, since purchaseDate: Date) async -> [PortfolioValuePoint] {
        guard quantity > 0 else { return [] }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Jakarta")!

        let daysAgo = max(cal.dateComponents([.day], from: purchaseDate, to: Date()).day ?? 0, 0)
        let (points, _) = await fetchChartUseCase.execute(symbol: symbol, range: Self.rangeFor(daysAgo: daysAgo))
        guard !points.isEmpty else { return [] }

        let startOfPurchaseDay = cal.startOfDay(for: purchaseDate)
        let filtered = points.filter { $0.date >= startOfPurchaseDay }
        guard !filtered.isEmpty else { return [] }
        return filtered.map { PortfolioValuePoint(date: $0.date, value: $0.close * quantity) }
    }

    /// Pilih range candle setepat mungkin sesuai jarak tanggal — range yang
    /// terlalu panjang (mis. 5 tahun) sering dikirim backend sebagai candle
    /// mingguan/bulanan, jadi pencocokan per-hari bisa kena bar yang salah.
    private static func rangeFor(daysAgo: Int) -> TimeRange {
        switch daysAgo {
        case ..<25:   return .oneMonth
        case ..<80:   return .threeMonth
        case ..<300:  return .oneYear
        default:      return .fiveYear
        }
    }

    func resetPortfolio() {
        holdings     = holdings.map { Holding(id: $0.id, symbol: $0.symbol, quantity: 0, totalCostBasis: 0) }
        tradeHistory = []
        lots         = []
        health       = nil
        persist()
        Task { await fetchData() }
    }

    // MARK: - Persistence

    private func loadPersistedData() {
        holdings     = portfolioRepository.loadHoldings()
        tradeHistory = portfolioRepository.loadTradeHistory()
        lots         = portfolioRepository.loadLots()
    }

    private func persist() {
        portfolioRepository.saveHoldings(holdings)
        portfolioRepository.saveTradeHistory(tradeHistory)
        portfolioRepository.saveLots(lots)
    }
}
