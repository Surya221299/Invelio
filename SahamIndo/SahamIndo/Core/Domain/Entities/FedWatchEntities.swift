//
//  FedWatchEntities.swift
//  SahamIndo
//
//  Domain model untuk data CME FedWatch — probabilitas (implied oleh 30-Day
//  Fed Funds futures) atas target range suku bunga The Fed pada rapat FOMC
//  mendatang. Dipakai sebagai layer background dekoratif di HomeView.
//

import Foundation

// MARK: - FedWatchSnapshot

/// Satu snapshot probabilitas FedWatch untuk satu rapat FOMC.
struct FedWatchSnapshot: Equatable {

    /// Label rapat, mis. "Rapat FOMC · Jul 2026".
    let meetingLabel: String

    /// Tanggal keputusan rapat FOMC berikutnya (untuk countdown). Nil kalau
    /// tidak diketahui.
    let meetingDate: Date?

    /// Distribusi probabilitas per target range, sudah terurut menaik
    /// berdasarkan batas bawah range.
    let outcomes: [FedWatchOutcome]

    /// Kapan data ini dihitung backend (nil kalau placeholder).
    let asOf: Date?

    /// Asal data — membedakan angka live dari contoh, supaya UI bisa memberi
    /// penanda dan kita TIDAK menampilkan angka finansial palsu seolah asli.
    let source: Source

    enum Source: Equatable { case live, cached, placeholder }

    /// Outcome dengan probabilitas tertinggi (untuk highlight).
    var mostLikely: FedWatchOutcome? {
        outcomes.max(by: { $0.probability < $1.probability })
    }
}

// MARK: - FedWatchOutcome

struct FedWatchOutcome: Identifiable, Equatable {
    let id = UUID()

    /// Label range, mis. "4,25–4,50%".
    let rangeLabel: String

    /// Probabilitas 0.0...1.0.
    let probability: Double

    static func == (lhs: FedWatchOutcome, rhs: FedWatchOutcome) -> Bool {
        lhs.rangeLabel == rhs.rangeLabel && lhs.probability == rhs.probability
    }
}

// MARK: - FOMC Schedule

/// Jadwal rapat FOMC (fallback lokal untuk placeholder). Sumber kebenaran tetap
/// backend; ini hanya supaya tanggal & countdown benar sebelum backend live.
/// VERIFIKASI dengan kalender resmi Fed tiap tahun.
enum FOMCSchedule {

    static let etTimeZone = TimeZone(identifier: "America/New_York")!

    /// Tanggal PENGUMUMAN keputusan (hari kedua rapat), tahun 2026.
    private static let announcements2026: [DateComponents] = [
        .init(year: 2026, month: 1,  day: 28),
        .init(year: 2026, month: 3,  day: 18),
        .init(year: 2026, month: 4,  day: 29),
        .init(year: 2026, month: 6,  day: 17),
        .init(year: 2026, month: 7,  day: 29),
        .init(year: 2026, month: 9,  day: 16),
        .init(year: 2026, month: 10, day: 28),
        .init(year: 2026, month: 12, day: 9),
    ]

    /// Tengah malam ET pada tanggal pengumuman FOMC berikutnya yang belum lewat
    /// (pengumuman dianggap pukul 14:00 ET). Nil kalau tak ada di jadwal.
    static func nextMeetingDate(after now: Date = Date()) -> Date? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = etTimeZone
        let midnights = announcements2026.compactMap { comp -> Date? in
            var c = comp; c.hour = 0; c.minute = 0; c.second = 0
            return cal.date(from: c)
        }
        // Simpan yang instans pengumumannya (14:00 ET) masih di masa depan.
        return midnights
            .filter { cal.date(byAdding: .hour, value: 14, to: $0)! >= now }
            .min()
    }
}

// MARK: - Placeholder

extension FedWatchSnapshot {

    /// Snapshot contoh yang dipakai saat backend belum menyediakan endpoint
    /// FedWatch (atau sedang offline). SENGAJA ditandai `.placeholder` supaya
    /// UI menampilkannya sebagai contoh, bukan data pasar sungguhan.
    static var placeholder: FedWatchSnapshot {
        FedWatchSnapshot(
            meetingLabel: "Rapat FOMC (contoh)",
            // Tanggal FOMC asli berikutnya supaya countdown akurat sebelum
            // backend menyediakan data live.
            meetingDate: FOMCSchedule.nextMeetingDate(),
            outcomes: [
                FedWatchOutcome(rangeLabel: "350-375", probability: 0.15),
                FedWatchOutcome(rangeLabel: "375-400", probability: 0.85),
            ],
            asOf: nil,
            source: .placeholder
        )
    }
}
