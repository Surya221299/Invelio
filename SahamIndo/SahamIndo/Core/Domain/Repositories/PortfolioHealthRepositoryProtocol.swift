//
//  PortfolioHealthRepositoryProtocol.swift
//  SahamIndo
//
//  Kontrak untuk analisis kesehatan portofolio (Interface Segregation).
//

import Foundation

protocol PortfolioHealthRepositoryProtocol {
    /// Kirim holdings on-device ke backend, terima analisis kesehatan + narasi harian.
    func analyze(holdings: [Holding]) async throws -> PortfolioHealth
}
