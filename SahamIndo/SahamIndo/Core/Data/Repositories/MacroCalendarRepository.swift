//
//  MacroCalendarRepository.swift
//  SahamIndo
//
//  Mengambil kalender faktor makro AS dari backend (endpoint /makro/kalender):
//  jadwal rilis + edukasi (inflasi, tenaga kerja, data ekonomi lain,
//  fiskal/politik) plus yield US Treasury 10Y live. Fallback ke snapshot contoh
//  (.placeholder) kalau backend belum siap.
//

import Foundation

// MARK: - Protocol

protocol MacroCalendarRepositoryProtocol {
    /// Selalu mengembalikan snapshot (fallback placeholder kalau backend belum
    /// siap) supaya section makro tidak pernah kosong.
    func fetchCalendar() async -> MacroCalendar
}

// MARK: - DTO (bentuk yang diharapkan dari backend)

private struct MacroCalendarResponseDTO: Decodable {
    let as_of: String?
    let treasury_10y: TreasuryDTO?
    let categories: [CategoryDTO]

    struct TreasuryDTO: Decodable {
        let yield: Double
        let change: Double?
    }

    struct CategoryDTO: Decodable {
        let key: String
        let title: String
        let icon: String?
        let items: [ItemDTO]
    }

    struct ItemDTO: Decodable {
        let key: String
        let name: String
        let schedule_label: String?
        // Datetime ISO8601 dengan offset ET (mis. "2026-08-12T08:30:00-04:00").
        // Dibiarkan String lalu diparse manual supaya kegagalan satu tanggal
        // tidak menggagalkan seluruh decode.
        let next_release: String?
        let is_estimate: Bool?
        let impact: String
        let actual: ActualDTO?
    }

    struct ActualDTO: Decodable {
        let value_text: String
        let unit_label: String?
        let previous_text: String?
        let direction: String?
        let period: String?
    }
}

// MARK: - Repository

final class MacroCalendarRepository: MacroCalendarRepositoryProtocol {

    func fetchCalendar() async -> MacroCalendar {
        do {
            let dto = try await APIClient.get(.macroCalendar, as: MacroCalendarResponseDTO.self)
            return Self.map(dto)
        } catch {
            print("[MacroCalendarRepository] pakai placeholder:", error.localizedDescription)
            return .placeholder
        }
    }

    // MARK: - Mapping

    private static func map(_ dto: MacroCalendarResponseDTO) -> MacroCalendar {
        let treasury = dto.treasury_10y.map {
            TreasuryYield(value: $0.yield, change: $0.change ?? 0)
        }

        let categories = dto.categories.map { cat in
            MacroCategory(
                key: cat.key,
                title: cat.title,
                icon: cat.icon ?? "chart.bar.fill",
                items: cat.items.map { item in
                    MacroCalendarItem(
                        key: item.key,
                        name: item.name,
                        scheduleLabel: item.schedule_label ?? "",
                        nextRelease: parseDateTime(item.next_release),
                        isEstimate: item.is_estimate ?? true,
                        impact: item.impact,
                        actual: item.actual.map {
                            MacroActual(
                                valueText: $0.value_text,
                                unitLabel: $0.unit_label ?? "",
                                previousText: $0.previous_text,
                                direction: MacroActual.Direction(rawValue: $0.direction ?? "flat") ?? .flat,
                                period: $0.period ?? ""
                            )
                        }
                    )
                }
            )
        }

        guard !categories.isEmpty else { return .placeholder }

        return MacroCalendar(
            treasury10Y: treasury,
            categories: categories,
            asOf: parseDate(dto.as_of),
            source: .live
        )
    }

    /// Parser ISO8601 datetime dengan offset (dari `next_release`).
    private static func parseDateTime(_ str: String?) -> Date? {
        guard let str, !str.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: str) { return d }
        // Toleransi bila backend menambah pecahan detik.
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return iso.date(from: str)
    }

    /// Parser date-only "yyyy-MM-dd" (dari `as_of`).
    private static func parseDate(_ str: String?) -> Date? {
        guard let str, !str.isEmpty else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "America/New_York")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: str)
    }
}
