//
//  UserDefaultsPortfolioRepository.swift
//  StockAppTryNew
//
//  Created by Surya on 16/06/26.
//

import Foundation
// Implements PortfolioRepositoryProtocol — swap with CoreData/CloudKit without touching domain.

final class UserDefaultsPortfolioRepository: PortfolioRepositoryProtocol {

    private let defaults = UserDefaults.standard

    private enum Key {
        static let holdings      = "portfolio_holdings_idn_v4"
        static let tradeHistory  = "portfolio_trade_history_v1"
        static let lots          = "portfolio_lots_v1"
    }

    private static let defaultSymbols = [
        "BBCA","BBRI","BMRI","BBNI","TLKM",
        "ASII","UNVR","ADRO","GGRM","KLBF",
        "ANTM","PGAS","ICBP","INDF","UNTR",
        "PTBA","MEDC","BRIS","AMRT","MDKA"
    ]

    // MARK: - Holdings

    func loadHoldings() -> [Holding] {
        guard let data    = defaults.data(forKey: Key.holdings),
              var decoded = try? JSONDecoder().decode([Holding].self, from: data)
        else { return defaultHoldings() }

        // Migration: GOTO → GGRM
        var migrated = false
        for i in decoded.indices where decoded[i].symbol == "GOTO" {
            decoded[i] = Holding(symbol: "GGRM", quantity: decoded[i].quantity,
                                 totalCostBasis: decoded[i].totalCostBasis)
            migrated = true
        }
        decoded.removeAll(where: { $0.symbol == "GOTO" })
        if !decoded.contains(where: { $0.symbol == "GGRM" }) {
            decoded.append(Holding(symbol: "GGRM", quantity: 0, totalCostBasis: 0))
            migrated = true
        }
        if migrated { saveHoldings(decoded) }
        return decoded
    }

    func saveHoldings(_ holdings: [Holding]) {
        guard let data = try? JSONEncoder().encode(holdings) else { return }
        defaults.set(data, forKey: Key.holdings)
    }

    // MARK: - Cash


    // MARK: - Trade History

    func loadTradeHistory() -> [TradeRecord] {
        guard let data    = defaults.data(forKey: Key.tradeHistory),
              let decoded = try? JSONDecoder().decode([TradeRecord].self, from: data)
        else { return [] }
        return decoded
    }

    func saveTradeHistory(_ records: [TradeRecord]) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        defaults.set(data, forKey: Key.tradeHistory)
    }

    // MARK: - Lots

    func loadLots() -> [Lot] {
        guard let data    = defaults.data(forKey: Key.lots),
              let decoded = try? JSONDecoder().decode([Lot].self, from: data)
        else { return [] }
        return decoded
    }

    func saveLots(_ lots: [Lot]) {
        guard let data = try? JSONEncoder().encode(lots) else { return }
        defaults.set(data, forKey: Key.lots)
    }

    // MARK: - Default Holdings

    private func defaultHoldings() -> [Holding] {
        Self.defaultSymbols.map { Holding(symbol: $0, quantity: 0, totalCostBasis: 0) }
    }
}
