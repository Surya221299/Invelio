//
//  PortfolioHealthRepository.swift
//  SahamIndo
//
//  Impl PortfolioHealthRepositoryProtocol — memanggil POST /portfolio/analyze.
//

import Foundation

final class PortfolioHealthRepository: PortfolioHealthRepositoryProtocol {

    func analyze(holdings: [Holding]) async throws -> PortfolioHealth {
        let dtoHoldings = holdings
            .filter { $0.quantity > 0 }
            .map {
                PortfolioAnalyzeRequestDTO.HoldingDTO(
                    symbol:     $0.symbol,
                    quantity:   $0.quantity,
                    cost_basis: $0.totalCostBasis,
                    market:     "IDX"
                )
            }
        let body = PortfolioAnalyzeRequestDTO(holdings: dtoHoldings)
        let dto  = try await APIClient.post(.analyzePortfolio, body: body,
                                            as: PortfolioAnalyzeResponseDTO.self)
        return dto.toDomain()
    }
}
