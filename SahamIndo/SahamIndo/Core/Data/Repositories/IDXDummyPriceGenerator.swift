//
//  IDXDummyPriceGenerator.swift
//  StockAppTryNew
//
//  Created by Surya on 16/06/26.
//

import Foundation
// Fallback when both API and cache are unavailable.

struct IDXDummyPriceGenerator {

    static func generate(symbol: String, range: TimeRange) -> [StockDataPoint] {
        let seed    = abs(symbol.hashValue)
        let base    = Double(500 + seed % 9500)
        let count   = pointCount(for: range)
        var price   = base
        var results: [StockDataPoint] = []
        let now     = Date()

        for i in 0..<count {
            let interval = intervalSeconds(for: range)
            let date     = now.addingTimeInterval(Double(i - count) * interval)
            let delta    = (Double.random(in: -0.02...0.02)) * price
            price  = max(100, price + delta)
            results.append(StockDataPoint(
                date:   date,
                close:  price,
                open:   price - delta * 0.5,
                high:   price + abs(delta) * 0.3,
                low:    price - abs(delta) * 0.3,
                volume: Double(Int.random(in: 100_000...10_000_000))
            ))
        }
        return results
    }

    private static func pointCount(for range: TimeRange) -> Int {
        switch range {
        case .oneDay:     return 87
        case .oneWeek:    return 87 * 5
        case .oneMonth:   return 30
        case .threeMonth: return 90
        case .ytd:        return 180
        case .oneYear:    return 252
        case .fiveYear:   return 260
        case .all:        return 260
        }
    }

    private static func intervalSeconds(for range: TimeRange) -> Double {
        switch range {
        case .oneDay:     return 5 * 60
        case .oneWeek:    return 5 * 60
        default:          return 24 * 3600
        }
    }
}
