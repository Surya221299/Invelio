//
//  SearchMapper.swift
//  SahamIndo
//
//  Tanggung jawab tunggal: DTO → Domain Entity untuk Search & Analyze.
//  Tidak import SwiftUI. Tidak menyentuh network/persistence.
//

import Foundation

enum SearchMapper {

    // MARK: - SimbolReferensiDTO → SymbolSearchResult

    static func toSearchResult(_ dto: SimbolReferensiDTO) -> SymbolSearchResult {
        SymbolSearchResult(
            id:          dto.kode,
            kode:        dto.kode,
            nama:        dto.nama,
            market:      Market.from(dto.market),
            tipe:        dto.tipe,
            exchange:    dto.exchange,
            isWatchlist: dto.is_watchlist
        )
    }

    static func toSearchResults(_ dtos: [SimbolReferensiDTO]) -> [SymbolSearchResult] {
        dtos.map { toSearchResult($0) }
    }

    // MARK: - AnalyzeResultDTO → AnalyzeResult

    static func toAnalyzeResult(_ dto: AnalyzeResultDTO) -> AnalyzeResult {
        let hasil = dto.hasil
        return AnalyzeResult(
            kode:            dto.kode,
            market:          Market.from(dto.market),
            isWatchlist:     dto.is_watchlist,
            skorTotal:       hasil?.skor_total,
            rekomendasi:     hasil?.rekomendasi,
            alasan:          hasil?.alasan,
            skorFundamental: hasil?.skor_fundamental,
            skorSentimen:    hasil?.skor_sentimen,
            skorTeknikal:    hasil?.skor_teknikal,
            skorRisiko:      hasil?.skor_risiko
        )
    }
}
