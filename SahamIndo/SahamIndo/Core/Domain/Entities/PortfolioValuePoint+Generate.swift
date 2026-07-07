//
//  PortfolioValuePoint+Generate.swift
//  StockAppTryNew
//
//  Static factory methods untuk membuat data chart portfolio.
//

import Foundation

extension PortfolioValuePoint {

    // MARK: - Portfolio Chart (semua holding)

    /// Menghasilkan titik-titik nilai portofolio dari `startDate` hingga hari ini.
    /// Setiap titik merepresentasikan nilai total semua `PortfolioItem` dengan
    /// simulasi pergerakan harga acak yang smooth (walk mundur dari nilai saat ini).
    static func generate(
        from items: [PortfolioItem],
        startDate: Date?
    ) -> [PortfolioValuePoint] {

        let activeItems = items.filter { $0.quantity > 0 }
        guard !activeItems.isEmpty else { return [] }

        let start = startDate
            ?? Calendar.current.date(byAdding: .day, value: -30, to: Date())!

        let totalDays = max(
            Calendar.current.dateComponents([.day], from: start, to: Date()).day ?? 1,
            1
        )
        let currentTotal = activeItems.reduce(0) { $0 + $1.value }
        guard currentTotal > 0 else { return [] }

        return simulateHistory(
            currentValue: currentTotal,
            days: totalDays,
            startDate: start,
            volatilityFactor: 0.012
        )
    }

    // MARK: - Per-Emiten Chart (satu holding)

    /// Menghasilkan titik-titik nilai satu holding dari tanggal beli hingga hari ini.
    static func generateForHolding(
        item: PortfolioItem,
        purchaseDate: Date,
        costBasis: Double
    ) -> [PortfolioValuePoint] {

        guard item.quantity > 0, costBasis > 0 else { return [] }

        let totalDays = max(
            Calendar.current.dateComponents([.day], from: purchaseDate, to: Date()).day ?? 1,
            1
        )
        let currentValue = item.value

        return simulateHistory(
            currentValue: currentValue,
            days: totalDays,
            startDate: purchaseDate,
            volatilityFactor: 0.015,
            anchorStartValue: costBasis   // titik awal dianker ke cost basis
        )
    }

    // MARK: - Private Helpers

    private static func simulateHistory(
        currentValue: Double,
        days: Int,
        startDate: Date,
        volatilityFactor: Double,
        anchorStartValue: Double? = nil
    ) -> [PortfolioValuePoint] {

        // Tentukan jumlah titik — max 90 titik supaya chart tetap smooth
        let pointCount = min(days + 1, 90)
        guard pointCount > 1 else {
            return [PortfolioValuePoint(date: startDate, value: anchorStartValue ?? currentValue),
                    PortfolioValuePoint(date: Date(), value: currentValue)]
        }

        let stepDays = Double(days) / Double(pointCount - 1)
        var values   = [Double](repeating: 0, count: pointCount)

        // Titik terakhir = nilai saat ini
        values[pointCount - 1] = currentValue

        // Titik pertama = anchor (cost basis) jika tersedia, atau simulasi mundur
        let startValue = anchorStartValue ?? currentValue

        // Isi titik tengah dengan interpolasi + noise
        var rng = SeededRandom(seed: UInt64(abs(currentValue)))
        for i in stride(from: pointCount - 2, through: 0, by: -1) {
            let progress   = Double(i) / Double(pointCount - 1)  // 0 = awal, 1 = akhir
            let trend      = startValue + (currentValue - startValue) * progress
            let noise      = trend * volatilityFactor * rng.nextGaussian()
            values[i]      = max(trend + noise, 1)
        }
        values[0] = startValue  // pastikan titik awal persis

        // Bangun array PortfolioValuePoint
        var points = [PortfolioValuePoint]()
        points.reserveCapacity(pointCount)
        for i in 0..<pointCount {
            let date = Calendar.current.date(
                byAdding: .second,
                value: Int(Double(i) * stepDays * 86400),
                to: startDate
            ) ?? startDate
            points.append(PortfolioValuePoint(date: date, value: values[i]))
        }
        return points
    }
}

// MARK: - Seeded Random (deterministik, tidak perlu import GameplayKit)

struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed == 0 ? 1 : seed }

    mutating func next() -> Double {
        // xorshift64
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return Double(state) / Double(UInt64.max)
    }

    /// Gaussian lewat Box-Muller
    mutating func nextGaussian() -> Double {
        let u1 = max(next(), 1e-10)
        let u2 = next()
        return sqrt(-2 * log(u1)) * cos(2 * .pi * u2)
    }
}
