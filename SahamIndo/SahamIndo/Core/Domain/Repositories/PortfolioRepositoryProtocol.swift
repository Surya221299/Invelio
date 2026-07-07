//
//  PortfolioRepositoryProtocol.swift
//  StockAppTryNew
//
//  Created by Surya on 16/06/26.
//

import Foundation
// Single-responsibility: portfolio CRUD & trade log persistence.

protocol PortfolioRepositoryProtocol {
    // Holdings
    func loadHoldings() -> [Holding]
    func saveHoldings(_ holdings: [Holding])
 
    // Cash
 
    // Trade history
    func loadTradeHistory() -> [TradeRecord]
    func saveTradeHistory(_ records: [TradeRecord])
 
    // Lots (individual purchase lots, for per-lot performance comparison)
    func loadLots() -> [Lot]
    func saveLots(_ lots: [Lot])
}
 
