//
//  FedWatchRepository.swift
//  SahamIndo
//
//  Mengambil probabilitas CME FedWatch dari backend (endpoint /makro/fedwatch).
//
//  CATATAN PENTING soal sumber data:
//  Halaman publik cmegroup.com me-render angka lewat JavaScript (widget
//  QuikStrike) dan API resmi FedWatch butuh OAuth2 + lisensi berbayar. Karena
//  itu app TIDAK boleh scrape langsung dari device. Tempat yang benar untuk
//  mengambil/menghitung data ini adalah backend (`/makro/fedwatch`), yang bisa
//  memakai API resmi, sumber gratis pihak ketiga, atau menghitung sendiri dari
//  harga 30-Day Fed Funds futures (ZQ) lalu meng-cache hasilnya. Selama
//  endpoint itu belum ada, repository ini fallback ke snapshot contoh yang
//  ditandai `.placeholder`.
//

import Foundation

// MARK: - Protocol

protocol FedWatchRepositoryProtocol {
    /// Selalu mengembalikan snapshot (fallback placeholder kalau backend
    /// belum siap) supaya layer background tidak pernah kosong.
    func fetchSnapshot() async -> FedWatchSnapshot
}

// MARK: - DTO (bentuk yang diharapkan dari backend)

private struct FedWatchResponseDTO: Decodable {
    let meeting_label: String?
    // Tanggal dibiarkan String lalu diparse manual — backend kirim date-only
    // ("2026-07-29") yang tidak cocok dengan JSONDecoder.dateStrategy ISO8601
    // default APIClient (butuh datetime penuh), jadi kalau diketik `Date`
    // seluruh decode akan gagal.
    let meeting_date: String?
    let as_of: String?
    let outcomes: [OutcomeDTO]

    struct OutcomeDTO: Decodable {
        let range_label: String
        let probability: Double   // boleh 0..1 atau 0..100; dinormalisasi di mapper
    }
}

// MARK: - Repository

final class FedWatchRepository: FedWatchRepositoryProtocol {

    func fetchSnapshot() async -> FedWatchSnapshot {
        do {
            let dto = try await APIClient.get(.fedwatch, as: FedWatchResponseDTO.self)
            return Self.map(dto)
        } catch {
            print("[FedWatchRepository] pakai placeholder:", error.localizedDescription)
            return .placeholder
        }
    }

    // MARK: - Mapping

    private static func map(_ dto: FedWatchResponseDTO) -> FedWatchSnapshot {
        // Backend bisa mengirim probabilitas sebagai persen (0..100) atau
        // fraksi (0..1). Deteksi dari total lalu normalisasi ke 0..1.
        let raw = dto.outcomes.map(\.probability)
        let looksLikePercent = (raw.max() ?? 0) > 1.5
        let outcomes = dto.outcomes
            .map { o in
                FedWatchOutcome(
                    rangeLabel: o.range_label,
                    probability: max(0, looksLikePercent ? o.probability / 100 : o.probability)
                )
            }
            .sorted { lowerBound($0.rangeLabel) < lowerBound($1.rangeLabel) }

        guard !outcomes.isEmpty else { return .placeholder }

        return FedWatchSnapshot(
            meetingLabel: dto.meeting_label ?? "Rapat FOMC",
            meetingDate: parseDate(dto.meeting_date),
            outcomes: outcomes,
            asOf: parseDate(dto.as_of),
            source: .live
        )
    }

    /// Parser toleran: dukung date-only "yyyy-MM-dd" maupun ISO8601 datetime.
    private static func parseDate(_ str: String?) -> Date? {
        guard let str, !str.isEmpty else { return nil }
        let dateOnly = DateFormatter()
        dateOnly.locale = Locale(identifier: "en_US_POSIX")
        dateOnly.timeZone = TimeZone(identifier: "America/New_York")
        dateOnly.dateFormat = "yyyy-MM-dd"
        if let d = dateOnly.date(from: str) { return d }
        let iso = ISO8601DateFormatter()
        return iso.date(from: str)
    }

    /// Ekstrak batas bawah range dari label ("4,25–4,50%" -> 4.25) untuk sorting.
    private static func lowerBound(_ label: String) -> Double {
        let firstToken = label.split(whereSeparator: { "–-—".contains($0) }).first ?? ""
        let cleaned = firstToken
            .replacingOccurrences(of: ",", with: ".")
            .filter { $0.isNumber || $0 == "." }
        return Double(cleaned) ?? .greatestFiniteMagnitude
    }
}
