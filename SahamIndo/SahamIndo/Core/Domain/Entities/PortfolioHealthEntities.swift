//
//  PortfolioHealthEntities.swift
//  SahamIndo
//
//  Domain entities untuk analisis kesehatan portofolio + narasi harian
//  ("Explain My Portfolio Today"). Murni Swift, tanpa dependency SwiftUI.
//

import Foundation

// MARK: - PortfolioHealth (agregat hasil analisis backend)

struct PortfolioHealth: Equatable {
    let ringkasan:        PortfolioHealthRingkasan
    let skorKesehatan:    Double          // 0–100
    let skorDiversifikasi: Double         // 0–100
    let levelRisiko:      String          // "Rendah" | "Sedang" | "Tinggi"
    let jumlahEmiten:     Int
    let jumlahSektor:     Int
    let konsentrasiEmiten: KonsentrasiEmiten?
    let konsentrasiSektor: KonsentrasiSektor?
    let flags:            [String]
    let alokasiSektor:    [SectorAllocation]
    let kontributorTeratas: [Contributor]
    let kontributorTerbawah: [Contributor]
    let narasiHarian:     String
    let saranRebalancing: [String]
}

struct PortfolioHealthRingkasan: Equatable {
    let totalValue: Double
    let totalCost:  Double
    let profitIDR:  Double
    let profitPct:  Double
}

struct KonsentrasiEmiten: Equatable {
    let symbol: String
    let persen: Double
}

struct KonsentrasiSektor: Equatable {
    let sektor: String
    let persen: Double
}

struct SectorAllocation: Identifiable, Equatable {
    var id: String { sektor }
    let sektor: String
    let value:  Double
    let persen: Double
}

struct Contributor: Identifiable, Equatable {
    var id: String { symbol }
    let symbol:        String
    let pctChange:     Double
    let kontribusiIDR: Double
}
