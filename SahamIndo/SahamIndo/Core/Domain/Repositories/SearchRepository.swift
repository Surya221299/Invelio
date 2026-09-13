//
//  SearchRepository.swift
//  SahamIndo
//
//  Protokol + implementasi untuk fitur search universe & analyze on-demand.
//

import Foundation

// MARK: - Protocol

protocol SearchRepositoryProtocol {
    /// Search universe simbol (ribuan NASDAQ/ETF/IDX) — ringan, tidak menyentuh watchlist.
    func searchSymbols(query: String, limit: Int) async throws -> [SymbolSearchResult]

    /// Jalankan analisis AI on-demand untuk 1 saham. LLM lokal (Ollama) —
    /// timeout set panjang (5 menit) karena backend bisa butuh waktu.
    ///
    /// PENTING: selalu kirim `market` dari hasil search (SymbolSearchResult
    /// yang user tap) — JANGAN andalkan backend menebak ulang dari tabel
    /// referensi. Kalau kode kebetulan tidak ada di situ, backend akan
    /// default ke IDX yang bisa salah permanen untuk saham non-IDX (lihat
    /// catatan panjang di analyze.py soal kasus "MU").
    func analyzeSaham(kode: String, market: String?, nama: String?) async throws -> AnalyzeResult

    /// Tambahkan saham ke watchlist aktif scheduler.
    func addToWatchlist(kode: String) async throws -> Bool

    /// Hapus saham dari watchlist aktif scheduler.
    func removeFromWatchlist(kode: String) async throws -> Bool

    /// Cek status apakah saham ada di watchlist.
    func getWatchlistStatus(kode: String) async throws -> Bool
}

// MARK: - Implementation

final class SearchRepository: SearchRepositoryProtocol {

    func searchSymbols(query: String, limit: Int = 20) async throws -> [SymbolSearchResult] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        let dtos = try await APIClient.get(
            .searchSymbols(query: q, limit: limit),
            as: [SimbolReferensiDTO].self
        )
        return SearchMapper.toSearchResults(dtos)
    }

    func analyzeSaham(kode: String, market: String?, nama: String?) async throws -> AnalyzeResult {
        let dto = try await APIClient.request(
            .analyzeSaham(kode: kode, market: market, nama: nama),
            as: AnalyzeResultDTO.self
        )
        return SearchMapper.toAnalyzeResult(dto)
    }

    func addToWatchlist(kode: String) async throws -> Bool {
        let dto = try await APIClient.request(
            .addWatchlist(kode: kode),
            as: WatchlistStatusDTO.self
        )
        return dto.is_watchlist
    }

    func removeFromWatchlist(kode: String) async throws -> Bool {
        let dto = try await APIClient.request(
            .removeWatchlist(kode: kode),
            as: WatchlistStatusDTO.self
        )
        return !dto.is_watchlist  // false = berhasil dikeluarkan
    }

    func getWatchlistStatus(kode: String) async throws -> Bool {
        let dto = try await APIClient.request(
            .watchlistStatus(kode: kode),
            as: WatchlistStatusDTO.self
        )
        return dto.is_watchlist
    }
}
