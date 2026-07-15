//
//  PortfolioChartViewModel.swift
//  StockAppTryNew
//
//  Drives ChartCanvasView / XAxisAnimatedLabels / TimeRangeSelectorView for
//  the Portfolio growth chart — conforms to ChartViewModelProtocol so the
//  exact same chart UI used in StockDetail can be reused here.
//  Data is a smoothed simulation of total portfolio value over time
//  (consistent with PortfolioValuePoint+Generate, which already simulates
//  history for the legacy single-range chart).
//

import Foundation
import Combine

@MainActor
final class PortfolioChartViewModel: ObservableObject, ChartViewModelProtocol {

    // MARK: - Published State

    @Published private(set) var dataPoints: [StockDataPoint] = []
    @Published private(set) var isLoading:  Bool             = false

    // Default ke .oneWeek — range minimum yang tersedia di PortfolioSummaryCardView.
    // (1D tidak ditampilkan di portfolio; 1W selalu jadi pilihan pertama.)
    @Published var selectedRange: TimeRange = .oneWeek

    // MARK: - ChartViewModelProtocol: 1D slot config
    // Portfolio is always IDX-only, so these are fixed constants.
    // Private statics are used internally (static functions, property initializers).
    // Instance computed vars below satisfy ChartViewModelProtocol.

    private static let idxOpenMinutes: Int = 9 * 60   // 09:00 WIB
    private static let idxTotalSlots:  Int = 87

    var oneDayTotalSlots:  Int { Self.idxTotalSlots }
    var oneDayOpenMinutes: Int { Self.idxOpenMinutes }

    // Slot penutupan sesi bursa IDX: 15:50 WIB → (15*60+50 - 540)/5 = 82.
    private static let oneDayClosingSlot = (15 * 60 + 50 - idxOpenMinutes) / 5  // = 82

    // MARK: - Computed

    var minPrice:    Double { dataPoints.map(\.close).min() ?? 0 }
    var maxPrice:    Double { dataPoints.map(\.close).max() ?? 0 }
    var startPrice:  Double { dataPoints.first?.close ?? 0 }
    var latestPrice: Double { dataPoints.last?.close  ?? 0 }

    // MARK: - Inputs

    private var items:    [PortfolioItem] = []
    private var holdings: [Holding]       = []

    // MARK: - Public Actions

    /// Call whenever portfolio items/holdings change (e.g. after a trade or refresh).
    func update(items: [PortfolioItem], holdings: [Holding]) {
        self.items    = items
        self.holdings = holdings
        Task { await fetchChartData() }
    }

    func fetchChartData() async {
        isLoading = true
        // yield agar SwiftUI sempat publish isLoading=true sebelum data langsung selesai
        await Task.yield()
        dataPoints = Self.generate(items: items, holdings: holdings, range: selectedRange)
        isLoading  = false
    }

    func oneDaySlotIndex(for date: Date) -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Jakarta")!
        let h = cal.component(.hour, from: date)
        let m = cal.component(.minute, from: date)
        let minutesSinceOpen = (h * 60 + m) - Self.idxOpenMinutes
        return max(0, min(minutesSinceOpen / 5, Self.idxTotalSlots - 1))
    }

    // MARK: - Synthetic Series Generation

    private static func generate(items: [PortfolioItem], holdings: [Holding], range: TimeRange) -> [StockDataPoint] {
        let activeItems  = items.filter { $0.quantity > 0 }
        let currentTotal = activeItems.reduce(0) { $0 + $1.value }
        guard currentTotal > 0 else { return [] }

        let now = Date()
        let cal = Calendar.current

        // Anchor trajektori grafik ke MODAL (total cost basis) → nilai sekarang,
        // supaya titik awal & arah grafik BENAR: posisi rugi turun, untung naik.
        // Contoh: beli 10jt, sekarang -18% → grafik "Semua" mulai dari 10jt
        // (profit 0 di tanggal beli) turun ke 8,2jt. Sebelumnya start selalu
        // currentTotal*0.94 sehingga rugi pun tampil sebagai garis NAIK.
        // `startValue(at:)` menginterpolasi nilai pada garis modal→sekarang untuk
        // range yang lebih pendek (1W/1M/…). Fallback ke perilaku lama bila modal
        // atau tanggal beli tidak tersedia.
        let activeHoldings = holdings.filter { $0.quantity > 0 }
        let costBasis      = activeHoldings.reduce(0) { $0 + $1.totalCostBasis }
        let earliest       = activeHoldings.compactMap { $0.purchaseDate }.min()

        func startValue(at windowStart: Date) -> Double {
            // Selama modal diketahui, JANGAN pernah pakai fallback currentTotal*0.94
            // (itu yang bikin titik awal salah, mis. 10jt tampil ~7,96jt).
            guard costBasis > 0 else { return currentTotal * 0.94 }
            guard let earliest else { return costBasis }   // tanpa tanggal beli → anggap window = sejak beli
            let total = now.timeIntervalSince(earliest)
            guard total > 0 else { return costBasis }
            let clamped = max(windowStart, earliest)   // sebelum tanggal beli → modal penuh
            let f = max(0, min(clamped.timeIntervalSince(earliest) / total, 1))
            return costBasis + (currentTotal - costBasis) * f
        }

        switch range {
        case .oneDay:
            return oneDaySlots(currentTotal: currentTotal)

        case .oneWeek:
            // 1W: satu titik per hari bursa aktif IDX — Sabtu, Minggu, dan
            // tanggal merah tidak masuk. Ini paralel dengan cara StockDetailView
            // mengonsumsi data candle real yang hanya berisi hari perdagangan.
            let winStart = cal.date(byAdding: .day, value: -7, to: now) ?? now
            return oneWeekTradingDays(currentTotal: currentTotal,
                                      startValue: startValue(at: winStart),
                                      holdings: holdings)

        case .all:
            // All: tampilkan dari tanggal pembelian pertama sampai hari ini.
            if let earliest {
                let days = max(cal.dateComponents([.day], from: earliest, to: now).day ?? 1, 1)
                return walk(currentValue: currentTotal, startValue: startValue(at: earliest),
                            days: days, startDate: earliest)
            }
            // Fallback: tidak ada tanggal beli — tampilkan 7 hari terakhir, tetap
            // mulai dari modal bila diketahui.
            let fallbackStart = cal.date(byAdding: .day, value: -7, to: now) ?? now
            return walk(currentValue: currentTotal, startValue: startValue(at: fallbackStart),
                        days: 7, startDate: fallbackStart)

        default:
            var days = lookbackDays(for: range, now: now)
            if let earliest {
                let sinceEarliest = max(cal.dateComponents([.day], from: earliest, to: now).day ?? days, 1)
                days = min(days, sinceEarliest)
            }
            let start = cal.date(byAdding: .day, value: -days, to: now) ?? now
            return walk(currentValue: currentTotal, startValue: startValue(at: start),
                        days: days, startDate: start)
        }
    }

    private static func lookbackDays(for range: TimeRange, now: Date) -> Int {
        let cal = Calendar.current
        switch range {
        case .oneDay:     return 0
        case .oneWeek:    return 5   // tidak dipakai lagi (branch tersendiri)
        case .oneMonth:   return 30
        case .threeMonth: return 90
        case .ytd:
            var comps = cal.dateComponents([.year], from: now)
            comps.month = 1; comps.day = 1
            let jan1 = cal.date(from: comps) ?? now
            return max(cal.dateComponents([.day], from: jan1, to: now).day ?? 1, 1)
        case .oneYear:    return 365
        case .fiveYear:   return 365 * 5
        case .all:        return 365 * 10  // fallback; tidak dipakai — generate() handle .all sendiri
        }
    }

    // MARK: - 1W: Hari Bursa Saja

    /// Menghasilkan satu titik per hari bursa aktif IDX untuk 5 hari terakhir.
    ///
    /// ### Mengapa ini diperlukan
    /// `walk()` lama membagi 7 hari kalender secara merata — titik-titik bisa
    /// jatuh di Sabtu, Minggu, atau tanggal merah IDX.  `AxisTickGenerator`
    /// memakai `firstIndexPerDay` yang langsung membaca tanggal dari `data`,
    /// sehingga label X-axis menampilkan hari libur tersebut.
    ///
    /// `StockDetailView` tidak memiliki masalah ini karena data candle real dari
    /// API IDX hanya berisi hari perdagangan.  Di sini kita replika perilaku
    /// itu: enumerate mundur dari hari bursa aktif terakhir, kumpulkan tepat
    /// 5 hari bursa, hasilkan satu titik per hari.
    ///
    /// ### Penanganan hari libur / weekend
    /// `IDXTradingCalendar.lastActiveTradingDay` mundur ke hari bursa terakhir
    /// jika hari ini libur/weekend.  `previousTradingDay(before:)` lalu mundur
    /// satu hari bursa per langkah — tidak pernah mendarat di Sabtu/Minggu/
    /// tanggal merah.  Semua titik bertanggal hari bursa nyata.
    private static func oneWeekTradingDays(currentTotal: Double, startValue: Double, holdings: [Holding]) -> [StockDataPoint] {
        let cal      = IDXTradingCalendar.jakartaCalendar
        let now      = Date()

        // Batas awal portofolio (opsional): jika baru dibeli kemarin,
        // jangan tampilkan 5 hari penuh.
        let earliest = holdings.compactMap { $0.purchaseDate }.min()

        // Kumpulkan hari bursa aktif dari hari ini mundur ke belakang
        let lastActive = IDXTradingCalendar.lastActiveTradingDay(relativeTo: now)
        var tradingDays: [Date] = []
        var cursor = lastActive
        while tradingDays.count < 5 {
            // Jika ada tanggal pembelian pertama, stop sebelum tanggal itu
            if let earliest, cal.startOfDay(for: cursor) < cal.startOfDay(for: earliest) { break }
            tradingDays.insert(cursor, at: 0)   // sisipkan di depan → urutan kronologis
            cursor = IDXTradingCalendar.previousTradingDay(before: cursor)
        }

        guard !tradingDays.isEmpty else {
            return [point(date: now, value: currentTotal)]
        }

        let count  = tradingDays.count
        var values = [Double](repeating: 0, count: count)
        values[count - 1] = currentTotal

        var rng = SeededRandom(seed: UInt64(abs(currentTotal)) &+ UInt64(count) &+ 1)
        for i in stride(from: count - 2, through: 0, by: -1) {
            let progress = Double(i) / Double(count - 1)
            let trend    = startValue + (currentTotal - startValue) * progress
            let noise    = trend * 0.012 * rng.nextGaussian()
            values[i]    = max(trend + noise, 1)
        }
        values[0] = startValue

        // Satu titik per hari bursa; jam di-set ke 15:50 (penutupan) kecuali
        // hari terakhir yang sedang berjalan (gunakan waktu sekarang).
        return tradingDays.enumerated().map { idx, day in
            let isLastDay = (idx == count - 1)
            let isToday   = cal.isDate(day, inSameDayAs: now)
            let date: Date
            if isLastDay && isToday && IDXTradingCalendar.isTradingDay(now) {
                // Sesi sedang berjalan: gunakan waktu sekarang
                date = now
            } else {
                // Sesi selesai: tandai jam penutupan 15:50 WIB
                date = cal.date(bySettingHour: 15, minute: 50, second: 0, of: day) ?? day
            }
            return point(date: date, value: values[idx])
        }
    }

    // MARK: - Multi-Day Walk (1M / 3M / YTD / 1Y / 5Y)

    /// Smooth interpolation + noise walk ending exactly at `currentValue`.
    ///
    /// ### Penanganan hari libur / weekend
    /// Sama seperti `oneWeekTradingDays`, titik-titik di sini di-enumerate dari
    /// hari bursa aktif IDX saja (`IDXTradingCalendar.isTradingDay`) — Sabtu,
    /// Minggu, dan tanggal merah di `idxHolidays` tidak pernah dijadikan
    /// dataPoint. Untuk range panjang (1Y/5Y) jumlah hari bursa di-subsample
    /// rata agar titik tetap dibatasi ≤90 (performa render), tapi titik
    /// terakhir selalu dijaga tepat di hari bursa terakhir agar anchor ke
    /// `currentValue` tetap akurat.
    private static func walk(currentValue: Double, startValue: Double, days: Int, startDate: Date) -> [StockDataPoint] {
        let cal  = IDXTradingCalendar.jakartaCalendar
        let now  = Date()

        // Kumpulkan semua hari bursa aktif dari startDate s/d hari bursa terakhir.
        let lastActive = IDXTradingCalendar.lastActiveTradingDay(relativeTo: now)
        let endDay     = cal.startOfDay(for: lastActive)
        var tradingDays: [Date] = []
        var cursor = cal.startOfDay(for: startDate)
        while cursor <= endDay {
            if IDXTradingCalendar.isTradingDay(cursor) { tradingDays.append(cursor) }
            cursor = cal.date(byAdding: .day, value: 1, to: cursor) ?? endDay.addingTimeInterval(86400)
        }

        guard !tradingDays.isEmpty else {
            return [point(date: startDate, value: currentValue * 0.97),
                    point(date: now,        value: currentValue)]
        }

        // Subsample merata kalau jumlah hari bursa melebihi batas render,
        // tapi tetap sertakan hari bursa terakhir sebagai anchor.
        let maxPoints: Int
        let sampledDays: [Date]
        if tradingDays.count > 90 {
            maxPoints = 90
            let sampleStep = Double(tradingDays.count - 1) / Double(maxPoints - 1)
            sampledDays = (0..<maxPoints).map { i in
                tradingDays[min(Int((Double(i) * sampleStep).rounded()), tradingDays.count - 1)]
            }
        } else {
            sampledDays = tradingDays
        }

        let pointCount = sampledDays.count
        guard pointCount > 1 else { return [point(date: sampledDays[0], value: currentValue)] }

        var values = [Double](repeating: 0, count: pointCount)
        values[pointCount - 1] = currentValue

        var rng = SeededRandom(seed: UInt64(abs(currentValue)) &+ UInt64(pointCount) &+ 1)
        for i in stride(from: pointCount - 2, through: 0, by: -1) {
            let progress = Double(i) / Double(pointCount - 1)
            let trend    = startValue + (currentValue - startValue) * progress
            let noise    = trend * 0.012 * rng.nextGaussian()
            values[i]    = max(trend + noise, 1)
        }
        values[0] = startValue

        // Jam di-set ke 15:50 WIB (penutupan) kecuali hari terakhir yang
        // sedang berjalan (gunakan waktu sekarang), sama seperti oneWeekTradingDays.
        return sampledDays.enumerated().map { idx, day in
            let isLastDay = (idx == pointCount - 1)
            let isToday   = cal.isDate(day, inSameDayAs: now)
            let date: Date
            if isLastDay && isToday && IDXTradingCalendar.isTradingDay(now) {
                date = now
            } else {
                date = cal.date(bySettingHour: 15, minute: 50, second: 0, of: day) ?? day
            }
            return point(date: date, value: values[idx])
        }
    }

    // MARK: - 1D Slot Generation

    /// Membuat slot 5-menit untuk hari bursa aktif terakhir.
    ///
    /// ### Aturan libur market (Sabtu / Minggu / tanggal merah IDX)
    /// Jika hari ini bukan hari bursa, `IDXTradingCalendar.lastActiveTradingDay`
    /// mundur ke hari bursa terakhir (misal Jumat). Semua data-point bertanggal
    /// hari bursa itu, **bukan** hari ini.
    ///
    /// ### currentSlotIdx di-cap ke oneDayClosingSlot (82 = 15:50 WIB)
    /// Slot 83–86 (15:55–16:10) tidak ada perdagangan di IDX.
    /// `StockDetailViewModel.normalizeToSlots` menghindarinya secara alami
    /// karena API tidak mengembalikan candle lewat 15:50.
    /// Di sini kita cap sendiri agar `buildMorphPoints` di `ChartCanvasView`
    /// identik dengan data real.
    private static func oneDaySlots(currentTotal: Double) -> [StockDataPoint] {
        let cal = IDXTradingCalendar.jakartaCalendar
        let now = Date()

        // Hari referensi: hari bursa aktif terakhir
        let refDay  = IDXTradingCalendar.lastActiveTradingDay(relativeTo: now)
        let refDate = cal.startOfDay(for: refDay)

        // Slot aktif terakhir, di-cap ke jam penutupan 15:50 (slot 82)
        let isRefToday = cal.isDate(refDay, inSameDayAs: now)
        let currentSlotIdx: Int
        if isRefToday && IDXTradingCalendar.isTradingDay(now) {
            let nowH = cal.component(.hour,   from: now)
            let nowM = cal.component(.minute, from: now)
            let slotFromOpen = (nowH * 60 + nowM - idxOpenMinutes) / 5
            currentSlotIdx = max(0, min(slotFromOpen, oneDayClosingSlot))
        } else {
            currentSlotIdx = oneDayClosingSlot
        }

        // Nilai simulasi untuk slot 0…currentSlotIdx
        let startValue = currentTotal * 0.985
        var values     = [Double](repeating: 0, count: currentSlotIdx + 1)
        values[currentSlotIdx] = currentTotal

        var rng = SeededRandom(seed: UInt64(abs(currentTotal)) &+ 7)
        for i in stride(from: currentSlotIdx - 1, through: 0, by: -1) {
            let progress = Double(i) / Double(max(currentSlotIdx, 1))
            let trend    = startValue + (currentTotal - startValue) * progress
            let noise    = trend * 0.004 * rng.nextGaussian()
            values[i]    = max(trend + noise, 1)
        }
        values[0] = startValue

        // Kembalikan tepat (currentSlotIdx + 1) titik — semua bertanggal refDate
        return (0...currentSlotIdx).map { i in
            let minutes = idxOpenMinutes + i * 5
            let date    = cal.date(bySettingHour: minutes / 60,
                                   minute:        minutes % 60,
                                   second:        0,
                                   of:            refDate) ?? now
            return point(date: date, value: values[i])
        }
    }

    private static func point(date: Date, value: Double) -> StockDataPoint {
        StockDataPoint(date: date, close: value, open: value, high: value, low: value, volume: 0)
    }
}
