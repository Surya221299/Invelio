//
//  PortfolioHealthDTOs.swift
//  SahamIndo
//
//  DTO request/response untuk POST /portfolio/analyze + mapping ke domain.
//

import Foundation

// MARK: - Request

struct PortfolioAnalyzeRequestDTO: Encodable {
    let holdings: [HoldingDTO]

    struct HoldingDTO: Encodable {
        let symbol:     String
        let quantity:   Double
        let cost_basis: Double
        let market:     String
    }
}

// MARK: - Response

struct PortfolioAnalyzeResponseDTO: Decodable {
    let ringkasan:        RingkasanDTO
    let kesehatan:        KesehatanDTO
    let alokasi_sektor:   [SektorDTO]
    let kontributor:      KontributorDTO
    let narasi_harian:    String
    let saran_rebalancing: [String]

    struct RingkasanDTO: Decodable {
        let total_value: Double
        let total_cost:  Double
        let profit_idr:  Double
        let profit_pct:  Double
    }

    struct KesehatanDTO: Decodable {
        let skor_kesehatan:     Double
        let skor_diversifikasi: Double
        let level_risiko:       String
        let jumlah_emiten:      Int
        let jumlah_sektor:      Int
        let konsentrasi_emiten: KonsentrasiEmitenDTO?
        let konsentrasi_sektor: KonsentrasiSektorDTO?
        let flags:              [String]
    }

    struct KonsentrasiEmitenDTO: Decodable { let symbol: String; let persen: Double }
    struct KonsentrasiSektorDTO: Decodable { let sektor: String; let persen: Double }

    struct SektorDTO: Decodable {
        let sektor: String
        let value:  Double
        let persen: Double
    }

    struct KontributorDTO: Decodable {
        let teratas:  [KontribItemDTO]
        let terbawah: [KontribItemDTO]
    }

    struct KontribItemDTO: Decodable {
        let symbol:         String
        let pct_change:     Double
        let kontribusi_idr: Double
    }
}

// MARK: - Mapping DTO → Domain

extension PortfolioAnalyzeResponseDTO {

    func toDomain() -> PortfolioHealth {
        PortfolioHealth(
            ringkasan: PortfolioHealthRingkasan(
                totalValue: ringkasan.total_value,
                totalCost:  ringkasan.total_cost,
                profitIDR:  ringkasan.profit_idr,
                profitPct:  ringkasan.profit_pct
            ),
            skorKesehatan:     kesehatan.skor_kesehatan,
            skorDiversifikasi: kesehatan.skor_diversifikasi,
            levelRisiko:       kesehatan.level_risiko,
            jumlahEmiten:      kesehatan.jumlah_emiten,
            jumlahSektor:      kesehatan.jumlah_sektor,
            konsentrasiEmiten: kesehatan.konsentrasi_emiten.map {
                KonsentrasiEmiten(symbol: $0.symbol, persen: $0.persen)
            },
            konsentrasiSektor: kesehatan.konsentrasi_sektor.map {
                KonsentrasiSektor(sektor: $0.sektor, persen: $0.persen)
            },
            flags: kesehatan.flags,
            alokasiSektor: alokasi_sektor.map {
                SectorAllocation(sektor: $0.sektor, value: $0.value, persen: $0.persen)
            },
            kontributorTeratas: kontributor.teratas.map {
                Contributor(symbol: $0.symbol, pctChange: $0.pct_change, kontribusiIDR: $0.kontribusi_idr)
            },
            kontributorTerbawah: kontributor.terbawah.map {
                Contributor(symbol: $0.symbol, pctChange: $0.pct_change, kontribusiIDR: $0.kontribusi_idr)
            },
            narasiHarian:     narasi_harian,
            saranRebalancing: saran_rebalancing
        )
    }
}
