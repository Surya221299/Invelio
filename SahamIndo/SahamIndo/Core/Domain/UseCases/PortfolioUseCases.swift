//
//  PortfolioUseCases.swift
//  StockAppTryNew
//
//  Created by Surya on 16/06/26.
//

import Foundation
// All trading business rules live here — not in ViewModel or View.

// MARK: - Constants

private enum TradingFee {
    static let buy:  Double = 0.0020
    static let sell: Double = 0.0030
}

// MARK: - BuyStockUseCase

final class BuyStockUseCase {

    struct Result {
        let updatedHoldings: [Holding]
        let tradeRecord: TradeRecord
        let newLot: Lot
    }

    func execute(
        symbol: String,
        amountIDR: Double,
        currentPrice: Double,
        holdings: [Holding],
        date: Date = Date()
    ) -> Swift.Result<Result, PortfolioError> {
        guard currentPrice > 0, amountIDR > 0 else { return .failure(.invalidInput) }

        let lots    = floor(amountIDR / (currentPrice * 100))
        let qty     = lots * 100
        guard qty > 0 else { return .failure(.quantityTooSmall) }

        let cost      = qty * currentPrice
        let totalCost = cost * (1.0 + TradingFee.buy)

        var updatedHoldings = holdings
        if let idx = updatedHoldings.firstIndex(where: { $0.symbol == symbol }) {
            updatedHoldings[idx].quantity       += qty
            updatedHoldings[idx].totalCostBasis += cost
            // Earliest purchaseDate wins (keeps "lama kepemilikan" accurate even
            // if a backdated lot is added later).
            if updatedHoldings[idx].purchaseDate == nil || date < updatedHoldings[idx].purchaseDate! {
                updatedHoldings[idx].purchaseDate = date
            }
        } else {
            updatedHoldings.append(
                Holding(symbol: symbol, quantity: qty, totalCostBasis: cost, purchaseDate: date)
            )
        }

        let fee    = cost * TradingFee.buy
        let record = TradeRecord(date: date, symbol: symbol, type: .buy, quantity: qty,
                                 price: currentPrice, fee: fee, totalAmount: totalCost)
        let lot    = Lot(symbol: symbol, quantity: qty, buyPrice: currentPrice, buyDate: date)

        return .success(Result(
            updatedHoldings: updatedHoldings,
            tradeRecord: record,
            newLot: lot
        ))
    }
}

// MARK: - SellStockUseCase

final class SellStockUseCase {

    struct Result {
        let updatedHoldings: [Holding]
        let tradeRecord: TradeRecord
        let updatedLots: [Lot]
    }

    func execute(
        symbol: String,
        quantity: Double,
        currentPrice: Double,
        holdings: [Holding],
        lots: [Lot] = []
    ) -> Swift.Result<Result, PortfolioError> {
        guard quantity > 0 else { return .failure(.invalidInput) }
        guard let idx = holdings.firstIndex(where: { $0.symbol == symbol }) else {
            return .failure(.holdingNotFound)
        }

        let owned   = holdings[idx].quantity
        let sellQty = min(quantity, owned)
        guard sellQty > 0 else { return .failure(.quantityTooSmall) }

        let avgCost    = owned > 0 ? holdings[idx].totalCostBasis / owned : 0
        let revenue    = sellQty * currentPrice
        let netRevenue = revenue * (1.0 - TradingFee.sell)
        let fee        = revenue * TradingFee.sell

        var updatedHoldings = holdings
        updatedHoldings[idx].quantity       -= sellQty
        updatedHoldings[idx].totalCostBasis -= sellQty * avgCost
        if updatedHoldings[idx].quantity < 1e-5 {
            updatedHoldings[idx].quantity       = 0
            updatedHoldings[idx].totalCostBasis = 0
        }

        // Consume lots FIFO — oldest purchase date first.
        var remaining    = sellQty
        var updatedLots  = lots
        let orderedIdx = updatedLots.indices
            .filter { updatedLots[$0].symbol == symbol }
            .sorted { updatedLots[$0].buyDate < updatedLots[$1].buyDate }
        for i in orderedIdx {
            guard remaining > 1e-9 else { break }
            let take = min(updatedLots[i].quantity, remaining)
            updatedLots[i].quantity -= take
            remaining               -= take
        }
        updatedLots.removeAll { $0.quantity < 1e-5 }

        let record = TradeRecord(symbol: symbol, type: .sell, quantity: sellQty,
                                 price: currentPrice, fee: fee, totalAmount: netRevenue)

        return .success(Result(
            updatedHoldings: updatedHoldings,
            tradeRecord: record,
            updatedLots: updatedLots
        ))
    }
}

// MARK: - PortfolioError

enum PortfolioError: LocalizedError {
    case invalidInput
    case quantityTooSmall
    case holdingNotFound

    var errorDescription: String? {
        switch self {
        case .invalidInput:      return "Input tidak valid."
        case .quantityTooSmall:  return "Jumlah terlalu kecil (minimal 1 lot = 100 lembar)."
        case .holdingNotFound:   return "Saham tidak ditemukan di portofolio."
        }
    }
}
