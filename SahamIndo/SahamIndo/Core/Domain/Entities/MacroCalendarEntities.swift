//
//  MacroCalendarEntities.swift
//  SahamIndo
//
//  Domain model untuk "Faktor Makro" — kalender faktor makroekonomi AS yang
//  menggerakkan pasar saham (inflasi, tenaga kerja, data ekonomi lain,
//  fiskal/politik) plus yield US Treasury 10Y. Ditampilkan di bawah chart
//  CME FedWatch pada tab Release.
//
//  Tanggal rilis adalah PERKIRAAN terjadwal (mis. NFP = Jumat pertama), bukan
//  angka yang di-scrape — item bertanda `isEstimate` supaya UI bisa menandai.
//

import Foundation

// MARK: - MacroCalendar

struct MacroCalendar: Equatable {

    /// Yield US Treasury 10Y (satu-satunya angka live). Nil kalau backend gagal
    /// mengambilnya.
    let treasury10Y: TreasuryYield?

    /// Kategori faktor makro, urutan sesuai backend.
    let categories: [MacroCategory]

    /// Kapan snapshot ini dibuat backend.
    let asOf: Date?

    /// Asal data — membedakan snapshot live dari contoh (placeholder).
    let source: Source

    enum Source: Equatable { case live, placeholder }
}

// MARK: - TreasuryYield

struct TreasuryYield: Equatable {
    /// Yield dalam persen, mis. 4.54.
    let value: Double
    /// Perubahan dari penutupan sebelumnya (persen point), mis. -0.03.
    let change: Double

    var isUp: Bool { change >= 0 }
}

// MARK: - MacroCategory

struct MacroCategory: Identifiable, Equatable {
    let id = UUID()

    /// Kunci stabil dari backend (mis. "inflasi").
    let key: String
    /// Judul tampil, mis. "Data Inflasi".
    let title: String
    /// Nama SF Symbol untuk ikon kategori.
    let icon: String
    let items: [MacroCalendarItem]

    static func == (lhs: MacroCategory, rhs: MacroCategory) -> Bool {
        lhs.key == rhs.key && lhs.title == rhs.title
            && lhs.icon == rhs.icon && lhs.items == rhs.items
    }
}

// MARK: - MacroCalendarItem

struct MacroCalendarItem: Identifiable, Equatable {
    let id = UUID()

    let key: String
    /// Nama indikator, mis. "CPI (Consumer Price Index)".
    let name: String
    /// Ringkasan jadwal, mis. "Bulanan · ~tgl 10–15 · 08:30 ET".
    let scheduleLabel: String
    /// Tanggal+jam rilis berikutnya (ET). Nil untuk item tak terjadwal
    /// (fiskal/politik).
    let nextRelease: Date?
    /// True kalau `nextRelease` adalah perkiraan terjadwal, bukan tanggal resmi.
    let isEstimate: Bool
    /// Penjelasan makna & dampak ke pasar.
    let impact: String

    static func == (lhs: MacroCalendarItem, rhs: MacroCalendarItem) -> Bool {
        lhs.key == rhs.key && lhs.name == rhs.name
            && lhs.scheduleLabel == rhs.scheduleLabel
            && lhs.nextRelease == rhs.nextRelease
            && lhs.isEstimate == rhs.isEstimate && lhs.impact == rhs.impact
    }
}

// MARK: - Placeholder

extension MacroCalendar {

    /// Snapshot contoh saat backend belum tersedia — SENGAJA ditandai
    /// `.placeholder`. Yield dikosongkan supaya tidak menampilkan angka palsu.
    static var placeholder: MacroCalendar {
        MacroCalendar(
            treasury10Y: nil,
            categories: [
                MacroCategory(
                    key: "inflasi", title: "Data Inflasi",
                    icon: "chart.line.uptrend.xyaxis",
                    items: [
                        MacroCalendarItem(
                            key: "cpi", name: "CPI (Consumer Price Index)",
                            scheduleLabel: "Bulanan · ~tgl 10–15 · 08:30 ET",
                            nextRelease: nil, isEstimate: true,
                            impact: "Inflasi lebih tinggi dari ekspektasi → Fed hawkish → saham cenderung turun."
                        )
                    ]
                )
            ],
            asOf: nil,
            source: .placeholder
        )
    }
}
