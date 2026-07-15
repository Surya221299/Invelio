//
//  IDXTradingCalendar.swift
//  SahamIndo
//
//  ⚠️  SINGLE SOURCE OF TRUTH — Semua logika hari libur bursa IDX ada di sini.
//  Jangan buat logika `isTradingDay` / `isWeekend` / `holiday` di tempat lain.
//  Sumber resmi: https://www.idx.co.id/id/tentang-idx/hari-libur/
//

import Foundation

// MARK: - IDX Trading Calendar

/// Kalender hari bursa Bursa Efek Indonesia (BEI / IDX).
/// Mencakup akhir pekan (Sabtu–Minggu) **dan** tanggal merah resmi + cuti bersama
/// sejak 1 Januari 2021.
///
/// ### Cara pakai
/// ```swift
/// // Cek hari ini
/// IDXTradingCalendar.isTradingDay(Date())          // → Bool
/// IDXTradingCalendar.isHoliday(Date())             // → Bool (tanggal merah saja)
/// IDXTradingCalendar.isWeekend(Date())             // → Bool
///
/// // Cari hari bursa terdekat sebelumnya
/// IDXTradingCalendar.previousTradingDay(before: someDate)
///
/// // Cari hari bursa terdekat ke depan
/// IDXTradingCalendar.nextTradingDay(after: someDate)
/// ```
enum IDXTradingCalendar {

    // MARK: - Jakarta Calendar (shared)

    static var jakartaCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Jakarta")!
        return cal
    }

    private static let jakartaFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone   = TimeZone(identifier: "Asia/Jakarta")!
        return f
    }()

    // MARK: - Public API

    /// `true` jika `date` adalah hari perdagangan bursa (bukan weekend, bukan libur).
    static func isTradingDay(_ date: Date) -> Bool {
        !isWeekend(date) && !isHoliday(date)
    }

    /// `true` jika `date` jatuh pada Sabtu atau Minggu (WIB).
    static func isWeekend(_ date: Date) -> Bool {
        let wd = jakartaCalendar.component(.weekday, from: date)
        return wd == 1 || wd == 7   // 1 = Minggu, 7 = Sabtu
    }

    /// `true` jika `date` adalah tanggal merah / cuti bersama bursa IDX.
    /// (Weekend **tidak** termasuk di sini — gunakan `isTradingDay` untuk cek keduanya.)
    static func isHoliday(_ date: Date) -> Bool {
        let key = jakartaFormatter.string(from: date)
        return idxHolidays.contains(key)
    }

    /// Hari bursa terakhir **sebelum** `date` (tidak termasuk `date` itu sendiri).
    static func previousTradingDay(before date: Date) -> Date {
        var candidate = jakartaCalendar.date(byAdding: .day, value: -1, to: date)!
        while !isTradingDay(candidate) {
            candidate = jakartaCalendar.date(byAdding: .day, value: -1, to: candidate)!
        }
        return candidate
    }

    /// Hari bursa pertama **setelah** `date` (tidak termasuk `date` itu sendiri).
    static func nextTradingDay(after date: Date) -> Date {
        var candidate = jakartaCalendar.date(byAdding: .day, value: 1, to: date)!
        while !isTradingDay(candidate) {
            candidate = jakartaCalendar.date(byAdding: .day, value: 1, to: candidate)!
        }
        return candidate
    }

    // MARK: - Daftar Hari Libur Bursa IDX
    // Sumber: https://www.idx.co.id/id/tentang-idx/hari-libur/
    // Update setiap awal tahun berdasarkan pengumuman resmi IDX.

    private static let idxHolidays: Set<String> = [

        // ── 2021 ──────────────────────────────────────────────────────────
        "2021-01-01",   // Tahun Baru Masehi
        "2021-02-12",   // Tahun Baru Imlek
        "2021-03-11",   // Isra Mi'raj
        "2021-03-14",   // Hari Raya Nyepi
        "2021-04-02",   // Wafat Isa Al-Masih
        "2021-05-01",   // Hari Buruh
        "2021-05-13",   // Kenaikan Isa Al-Masih
        "2021-05-12",   // Hari Raya Idul Fitri (cuti bersama)
        "2021-05-13",
        "2021-05-14",
        "2021-05-17",
        "2021-05-18",
        "2021-05-26",   // Hari Raya Waisak
        "2021-07-20",   // Idul Adha
        "2021-08-11",   // Tahun Baru Islam
        "2021-08-17",   // HUT Kemerdekaan RI
        "2021-10-19",   // Maulid Nabi Muhammad SAW
        "2021-12-24",   // Cuti Bersama Natal
        "2021-12-27",   // Cuti Bersama Natal

        // ── 2022 ──────────────────────────────────────────────────────────
        "2022-01-01",   // Tahun Baru Masehi
        "2022-02-01",   // Tahun Baru Imlek
        "2022-03-03",   // Isra Mi'raj
        "2022-03-03",
        "2022-04-15",   // Wafat Isa Al-Masih
        "2022-04-29",   // Cuti Bersama Idul Fitri
        "2022-05-02",   // Idul Fitri
        "2022-05-03",
        "2022-05-04",
        "2022-05-05",
        "2022-05-06",   // Cuti Bersama Idul Fitri
        "2022-05-16",   // Hari Raya Nyepi
        "2022-05-26",   // Kenaikan Isa Al-Masih
        "2022-06-01",   // Hari Lahir Pancasila
        "2022-07-09",   // Idul Adha
        "2022-07-30",   // Tahun Baru Islam
        "2022-08-17",   // HUT Kemerdekaan RI
        "2022-10-08",   // Maulid Nabi Muhammad SAW
        "2022-12-26",   // Cuti Bersama Natal

        // ── 2023 ──────────────────────────────────────────────────────────
        "2023-01-01",   // Tahun Baru Masehi
        "2023-01-02",   // Cuti Bersama Tahun Baru
        "2023-01-23",   // Tahun Baru Imlek
        "2023-02-18",   // Isra Mi'raj
        "2023-03-22",   // Hari Raya Nyepi
        "2023-03-23",   // Cuti Bersama Nyepi
        "2023-04-07",   // Wafat Isa Al-Masih
        "2023-04-19",   // Cuti Bersama Idul Fitri
        "2023-04-20",
        "2023-04-21",   // Idul Fitri
        "2023-04-24",
        "2023-04-25",   // Cuti Bersama Idul Fitri
        "2023-05-01",   // Hari Buruh
        "2023-05-18",   // Kenaikan Isa Al-Masih
        "2023-06-01",   // Hari Lahir Pancasila
        "2023-06-02",   // Cuti Bersama Waisak
        "2023-06-04",   // Hari Raya Waisak
        "2023-06-29",   // Idul Adha
        "2023-07-19",   // Tahun Baru Islam
        "2023-08-17",   // HUT Kemerdekaan RI
        "2023-09-28",   // Maulid Nabi Muhammad SAW
        "2023-12-25",   // Natal
        "2023-12-26",   // Cuti Bersama Natal

        // ── 2024 ──────────────────────────────────────────────────────────
        "2024-01-01",   // Tahun Baru Masehi
        "2024-02-08",   // Tahun Baru Imlek
        "2024-02-09",   // Cuti Bersama Imlek
        "2024-03-11",   // Isra Mi'raj
        "2024-03-12",   // Cuti Bersama Isra Mi'raj
        "2024-03-29",   // Wafat Isa Al-Masih
        "2024-04-08",   // Hari Raya Nyepi
        "2024-04-09",
        "2024-04-10",   // Idul Fitri
        "2024-04-11",
        "2024-04-12",
        "2024-04-15",   // Cuti Bersama Idul Fitri
        "2024-05-01",   // Hari Buruh
        "2024-05-09",   // Kenaikan Isa Al-Masih
        "2024-05-23",   // Hari Raya Waisak
        "2024-05-24",   // Cuti Bersama Waisak
        "2024-06-01",   // Hari Lahir Pancasila
        "2024-06-17",   // Idul Adha
        "2024-06-18",   // Cuti Bersama Idul Adha
        "2024-07-07",   // Tahun Baru Islam
        "2024-08-17",   // HUT Kemerdekaan RI
        "2024-09-16",   // Maulid Nabi Muhammad SAW
        "2024-12-25",   // Natal
        "2024-12-26",   // Cuti Bersama Natal

        // ── 2025 ──────────────────────────────────────────────────────────
        "2025-01-01",   // Tahun Baru Masehi
        "2025-01-27",   // Isra Mi'raj
        "2025-01-28",   // Cuti Bersama Tahun Baru Imlek
        "2025-01-29",   // Tahun Baru Imlek
        "2025-03-28",   // Hari Raya Nyepi
        "2025-03-31",   // Cuti Bersama Idul Fitri
        "2025-04-01",   // Idul Fitri
        "2025-04-02",
        "2025-04-03",
        "2025-04-04",
        "2025-04-07",   // Cuti Bersama Idul Fitri
        "2025-04-18",   // Wafat Isa Al-Masih
        "2025-05-01",   // Hari Buruh
        "2025-05-12",   // Hari Raya Waisak
        "2025-05-27",   // Cuti Bersama Kenaikan Isa Al-Masih
        "2025-05-28",   // Cuti Bersama Waisak
        "2025-05-29",   // Kenaikan Isa Al-Masih
        "2025-06-01",   // Hari Lahir Pancasila
        "2025-06-06",   // Idul Adha
        "2025-06-27",   // Tahun Baru Islam
        "2025-08-17",   // HUT Kemerdekaan RI
        "2025-08-18",   // Cuti Bersama HUT RI
        "2025-09-05",   // Maulid Nabi Muhammad SAW
        "2025-12-25",   // Natal
        "2025-12-26",   // Cuti Bersama Natal

        // ── 2026 ──────────────────────────────────────────────────────────
        "2026-01-01",   // Tahun Baru Masehi
        "2026-01-16",   // Tahun Baru Imlek
        "2026-03-18",   // Nyepi
        "2026-03-20",   // Wafat Isa Al-Masih
        "2026-03-23",   // Isra Mi'raj
        "2026-04-01",   // Cuti Bersama Idul Fitri
        "2026-04-02",   // Idul Fitri
        "2026-04-03",
        "2026-04-06",   // Cuti Bersama Idul Fitri
        "2026-05-01",   // Hari Buruh
        "2026-05-16",   // Kenaikan Isa Al-Masih
        "2026-05-27",   // Hari Raya Waisak
        "2026-05-28",   // Joint Holiday for Idul Adha
        "2026-06-01",   // Hari Lahir Pancasila
        "2026-06-16",   // nanana
        "2026-08-17",   // HUT Kemerdekaan RI
    ]
}

// MARK: - BEITradingHours (jam sesi bursa BEI)

/// Jam sesi perdagangan BEI.
/// Tetap terpisah dari `IDXTradingCalendar` karena berkaitan dengan **jam**, bukan **hari**.
extension IDXTradingCalendar {

    /// Hari bursa terakhir yang sudah *selesai* sesinya (atau sedang berjalan jika hari ini).
    /// Berguna untuk chart 1D: jika hari ini libur/weekend, kembalikan Jumat (atau hari bursa terakhir).
    static func lastActiveTradingDay(relativeTo now: Date = Date()) -> Date {
        isTradingDay(now) ? now : previousTradingDay(before: now)
    }

    // MARK: - Jam Sesi & Istirahat (WIB)
    //
    // Jam perdagangan reguler BEI:
    //   Senin–Kamis : Sesi I 09:00–12:00, ISTIRAHAT 12:00–13:30, Sesi II 13:30–15:50
    //   Jumat       : Sesi I 09:00–11:30, ISTIRAHAT 11:30–14:00, Sesi II 14:00–15:50
    // Chart 1D memakai penutupan reguler ~15:50 (konsisten dengan slot penutupan
    // yang dipakai generator data 1D).

    private static let regularCloseMinutes = 15 * 60 + 50   // 15:50 WIB

    private static func minutesOfDay(_ date: Date) -> Int {
        let cal = jakartaCalendar
        return cal.component(.hour, from: date) * 60 + cal.component(.minute, from: date)
    }

    private static func isFriday(_ date: Date) -> Bool {
        jakartaCalendar.component(.weekday, from: date) == 6   // 1=Minggu … 6=Jumat, 7=Sabtu
    }

    /// Menit (sejak tengah malam WIB) saat Sesi I ditutup / istirahat dimulai.
    /// Senin–Kamis 12:00 (720), Jumat 11:30 (690).
    static func session1CloseMinutes(_ date: Date = Date()) -> Int {
        isFriday(date) ? 11 * 60 + 30 : 12 * 60
    }

    /// `true` jika `date` berada di jam istirahat siang bursa (antara Sesi I & II).
    static func isMiddaySessionBreak(_ date: Date = Date()) -> Bool {
        guard isTradingDay(date) else { return false }
        let m = minutesOfDay(date)
        return isFriday(date) ? (m >= 11 * 60 + 30 && m < 14 * 60)
                              : (m >= 12 * 60      && m < 13 * 60 + 30)
    }

    /// `true` jika sesi perdagangan sedang berjalan: hari bursa, sudah buka (≥09:00),
    /// belum tutup (<15:50), dan bukan jam istirahat.
    static func isSessionOpen(_ date: Date = Date()) -> Bool {
        guard isTradingDay(date) else { return false }
        let m = minutesOfDay(date)
        return m >= 9 * 60 && m < regularCloseMinutes && !isMiddaySessionBreak(date)
    }
}
