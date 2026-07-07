//
//  PortfolioMapper.swift
//  StockAppTryNew
//
//  Core/Data/Mappers/PortfolioMapper.swift
//  Tanggung jawab tunggal: mapping DTO → Domain Entity untuk Insight, Macro, Rekomendasi.
//  Tidak boleh import SwiftUI. Tidak boleh menyentuh network atau persistence.
//

import Foundation

enum PortfolioMapper {

    // MARK: - AIMarketInsightDTO → AIInsight

    static func toInsight(_ dto: AIMarketInsightDTO, label: String) -> AIInsight {
        AIInsight(
            label:     label,
            text:      dto.text,
            updatedAt: nil
        )
    }

    // MARK: - MakroIndicatorDTO → MacroIndicator

    static func toMacroIndicator(key: String, dto: MakroIndicatorDTO) -> MacroIndicator {
        MacroIndicator(
            key:    key,
            value:  dto.nilai,
            unit:   dto.satuan,
            date:   dto.tanggal,
            source: dto.sumber
        )
    }

    static func toMacroIndicators(_ dict: [String: MakroIndicatorDTO]) -> [MacroIndicator] {
        dict.map { key, val in toMacroIndicator(key: key, dto: val) }
    }

    // MARK: - RekomendasiItemDTO → StockRecommendation

    static func toRecommendation(_ dto: RekomendasiItemDTO) -> StockRecommendation {
        StockRecommendation(
            rank:           dto.rank,
            symbol:         dto.kode_saham,
            companyName:    dto.nama_perusahaan,
            sector:         dto.sektor,
            recommendation: dto.rekomendasi,
            reason:         dto.alasan
        )
    }

    static func toRecommendations(_ dtos: [RekomendasiItemDTO]) -> [StockRecommendation] {
        dtos.map { toRecommendation($0) }
    }
}
