//
//  SearchViewModel.swift
//  SahamIndo
//
//  ViewModel untuk SearchView. Mengelola:
//  - Search universe simbol (debounce 350ms)
//  - Status lock saat Analyze sedang berjalan (LLM lokal = satu per satu)
//  - Hasil AnalyzeResult untuk ditampilkan di AnalyzeResultSheet
//  - Toggle watchlist (add/remove) tanpa reload penuh
//

import SwiftUI
import Combine

@MainActor
final class SearchViewModel: ObservableObject {

    // MARK: - State

    @Published var query: String = ""
    @Published private(set) var results: [SymbolSearchResult] = []
    @Published private(set) var isSearching: Bool = false

    /// Saham yang sedang dianalisis (tombol Analyze di-klik)
    @Published private(set) var analyzingKode: String? = nil

    /// Hasil analisis setelah selesai — sheet akan muncul kalau non-nil
    @Published var analyzeResult: AnalyzeResult? = nil

    /// Error message untuk snackbar/alert
    @Published var errorMessage: String? = nil

    // MARK: - Private

    private let repo: SearchRepositoryProtocol
    private var searchTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    init(repo: SearchRepositoryProtocol) {
        self.repo = repo
        setupDebounce()
    }

    // MARK: - Debounce Search

    private func setupDebounce() {
        $query
            .debounce(for: .milliseconds(350), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] q in
                guard let self else { return }
                let trimmed = q.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    self.results = []
                    self.isSearching = false
                } else {
                    Task { await self.performSearch(query: trimmed) }
                }
            }
            .store(in: &cancellables)
    }

    private func performSearch(query: String) async {
        searchTask?.cancel()
        isSearching = true
        searchTask = Task {
            do {
                let res = try await repo.searchSymbols(query: query, limit: 25)
                guard !Task.isCancelled else { return }
                results    = res
                isSearching = false
            } catch {
                guard !Task.isCancelled else { return }
                isSearching = false
                errorMessage = "Gagal mencari simbol: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Analyze

    /// Jalankan analisis AI on-demand untuk satu saham.
    /// Tombol Analyze di-disable selama ini berjalan (backend pakai scoring_lock global).
    ///
    /// `market`/`nama` WAJIB dikirim dari hasil search (`SymbolSearchResult`
    /// yang user tap) — backend tidak lagi menebak ulang market kalau ini
    /// dikirim, supaya tidak salah default ke IDX untuk saham non-IDX.
    func analyze(kode: String, market: Market, nama: String) async {
        guard analyzingKode == nil else {
            errorMessage = "Analisis '\(analyzingKode ?? "")' sedang berjalan. Tunggu sebentar."
            return
        }
        analyzingKode = kode
        errorMessage  = nil

        do {
            let result = try await repo.analyzeSaham(kode: kode, market: market.rawValue, nama: nama)
            analyzeResult = result
            // Update badge is_watchlist di hasil search tanpa fetch ulang
            updateWatchlistBadge(kode: kode, isWatchlist: result.isWatchlist)
        } catch {
            errorMessage = "Gagal menganalisis \(kode): \(error.localizedDescription)"
        }
        analyzingKode = nil
    }

    // MARK: - Watchlist Toggle

    func addToWatchlist(kode: String) async {
        do {
            _ = try await repo.addToWatchlist(kode: kode)
            updateWatchlistBadge(kode: kode, isWatchlist: true)
            if analyzeResult?.kode == kode {
                // Reflect perubahan di sheet yang terbuka
                analyzeResult = analyzeResult.map { r in
                    AnalyzeResult(
                        kode: r.kode, market: r.market, isWatchlist: true,
                        skorTotal: r.skorTotal, rekomendasi: r.rekomendasi,
                        alasan: r.alasan, skorFundamental: r.skorFundamental,
                        skorSentimen: r.skorSentimen, skorTeknikal: r.skorTeknikal,
                        skorRisiko: r.skorRisiko
                    )
                }
            }
        } catch {
            errorMessage = "Gagal tambah watchlist: \(error.localizedDescription)"
        }
    }

    func removeFromWatchlist(kode: String) async {
        do {
            _ = try await repo.removeFromWatchlist(kode: kode)
            updateWatchlistBadge(kode: kode, isWatchlist: false)
        } catch {
            errorMessage = "Gagal hapus watchlist: \(error.localizedDescription)"
        }
    }

    // MARK: - Helpers

    private func updateWatchlistBadge(kode: String, isWatchlist: Bool) {
        results = results.map { r in
            guard r.kode == kode else { return r }
            return SymbolSearchResult(
                id: r.id, kode: r.kode, nama: r.nama,
                market: r.market, tipe: r.tipe, exchange: r.exchange,
                isWatchlist: isWatchlist
            )
        }
    }
}

// MARK: - Optional<AnalyzeResult>.map helper (not in stdlib for structs)
private extension Optional where Wrapped == AnalyzeResult {
    func map(_ transform: (AnalyzeResult) -> AnalyzeResult) -> AnalyzeResult? {
        guard let self else { return nil }
        return transform(self)
    }
}
