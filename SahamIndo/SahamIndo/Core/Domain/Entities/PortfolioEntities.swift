//
//  PortfolioEntities.swift
//  StockAppTryNew
//
//  Created by Surya on 16/06/26.
//

import Foundation
// Core/Domain/Entities/PortfolioEntities.swift
// Portfolio-related domain entities — pure Swift.

// MARK: - Holding (persisted)

struct Holding: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var symbol: String
    var quantity: Double
    var totalCostBasis: Double
    var purchaseDate: Date?

    init(id: UUID = UUID(), symbol: String, quantity: Double,
         totalCostBasis: Double, purchaseDate: Date? = nil) {
        self.id             = id
        self.symbol         = symbol
        self.quantity       = quantity
        self.totalCostBasis = totalCostBasis
        self.purchaseDate   = purchaseDate
    }
}

// MARK: - PortfolioItem (computed, never persisted)

struct PortfolioItem: Identifiable, Hashable {
    let symbol: String
    let name: String?
    let price: Double
    let change: Double
    let percentChange: Double
    let quantity: Double
    let sentiment: Sentiment
    /// "IDX" | "NASDAQ" | "NYSE" | "ETF" — dipakai untuk format harga yang benar
    /// (IDX dibulatkan tanpa desimal, non-IDX 2 desimal, mis. "197,53").
    let market: String

    /// Stabil berdasarkan symbol (bukan UUID acak) — supaya saat harga
    /// diperbarui lewat streaming (instance PortfolioItem baru dibuat tiap
    /// update), SwiftUI List/ForEach tetap mengenalinya sebagai "baris yang
    /// sama, datanya berubah" alih-alih menganggap baris baru.
    var id: String { symbol }

    var value: Double { price * quantity }
    var costBasis: Double { quantity > 0 ? sentiment.score : 0 }  // kept for hashing
}

// MARK: - Lot (persisted) — individual purchase lot, enables "buy 3 months ago"
// style backdated simulation + per-lot performance comparison vs current price.

struct Lot: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var symbol: String
    var quantity: Double
    var buyPrice: Double
    var buyDate: Date

    var costBasis: Double { quantity * buyPrice }

    init(id: UUID = UUID(), symbol: String, quantity: Double, buyPrice: Double, buyDate: Date) {
        self.id       = id
        self.symbol   = symbol
        self.quantity = quantity
        self.buyPrice = buyPrice
        self.buyDate  = buyDate
    }
}

// MARK: - TradeRecord (persisted log)

struct TradeRecord: Identifiable, Codable {
    var id: UUID = UUID()
    var date: Date
    var symbol: String
    var type: TradeType
    var quantity: Double
    var price: Double
    var fee: Double
    var totalAmount: Double

    enum TradeType: String, Codable {
        case buy  = "buy"
        case sell = "sell"
    }

    init(id: UUID = UUID(), date: Date = Date(), symbol: String,
         type: TradeType, quantity: Double, price: Double,
         fee: Double, totalAmount: Double) {
        self.id          = id
        self.date        = date
        self.symbol      = symbol
        self.type        = type
        self.quantity    = quantity
        self.price       = price
        self.fee         = fee
        self.totalAmount = totalAmount
    }
}

// MARK: - PortfolioSummary (computed aggregate)

struct PortfolioSummary {
    let totalStockValue: Double
    let totalCostBasis:  Double

    /// Return keuntungan/kerugian dalam IDR (nilai pasar - modal beli)
    var totalProfitIDR: Double { totalStockValue - totalCostBasis }

    /// Return % berbasis cost basis (bukan deposit)
    var growthPercent: Double {
        guard totalCostBasis > 0 else { return 0 }
        return (totalProfitIDR / totalCostBasis) * 100
    }
}

// MARK: - PortfolioValuePoint (chart history)

struct PortfolioValuePoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
}
