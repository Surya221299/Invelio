//
//  WatchlistStore.swift
//  SahamIndo
//

import SwiftUI
import Combine

// MARK: - Model

struct WatchlistTab: Identifiable, Codable, Equatable {
    var id:   String
    var name: String

    static let defaultTabs: [WatchlistTab] = [
        WatchlistTab(id: "all",    name: "Semua"),
        WatchlistTab(id: "idx",    name: "IDX"),
        WatchlistTab(id: "us",     name: "US"),
        WatchlistTab(id: "crypto", name: "Crypto"),
    ]
}

// MARK: - Store

@MainActor
final class WatchlistStore: ObservableObject {

    @Published private(set) var tabs:      [WatchlistTab]
    @Published              var activeID:  String {
        didSet {
            // Auto-persist tiap kali activeID berubah — termasuk pas user
            // cuma TAP tab yang sudah ada (bukan cuma addTab/deleteTab).
            // Tanpa ini, "ingat tab terakhir" tidak akan pernah benar-benar
            // jalan untuk kasus tap biasa.
            guard oldValue != activeID else { return }
            persist()
        }
    }

    private let tabsKey   = "watchlist_tabs_v1"
    private let activeKey = "watchlist_active_v1"

    init() {
        var loadedTabs: [WatchlistTab]
        if let data = UserDefaults.standard.data(forKey: "watchlist_tabs_v1"),
           let saved = try? JSONDecoder().decode([WatchlistTab].self, from: data),
           !saved.isEmpty {
            loadedTabs = saved
        } else {
            loadedTabs = WatchlistTab.defaultTabs
        }

        // Migrasi 1: hapus tab custom LAMA yang namanya "Crypto" tapi id-nya
        // BUKAN "crypto" (id acak/UUID) — ini sisa dari sebelum fitur tab
        // Crypto spesial ini ada, waktu user bikin watchlist custom manual
        // bernama "Crypto". Sekarang jadi duplikat, jadi yang lama dibuang,
        // cukup simpan satu-satunya yang id-nya "crypto".
        loadedTabs.removeAll { $0.name.caseInsensitiveCompare("Crypto") == .orderedSame && $0.id != "crypto" }

        // Migrasi 2: user yang sudah pernah pakai app SEBELUM fitur tab
        // "Crypto" spesial ini ada, tab tersimpannya tidak akan otomatis
        // include tab ini (karena fallback ke defaultTabs cuma kepakai kalau
        // BELUM ADA data tersimpan sama sekali). Jadi di-insert manual kalau
        // belum ada (misal karena baru saja dihapus oleh migrasi 1 di atas,
        // atau memang belum pernah ada sama sekali).
        if !loadedTabs.contains(where: { $0.id == "crypto" }) {
            loadedTabs.append(WatchlistTab(id: "crypto", name: "Crypto"))
        }
        tabs = loadedTabs

        // Restore tab terakhir yang aktif dari UserDefaults (kalau ada dan
        // masih valid — id-nya masih ada di daftar tabs saat ini). Kalau
        // belum pernah pilih apa-apa (install baru) atau tab yang terakhir
        // dipilih sudah dihapus, fallback ke tab "Semua".
        let savedActive = UserDefaults.standard.string(forKey: activeKey)
        let validActive = savedActive.flatMap { id in loadedTabs.first { $0.id == id }?.id }
        activeID = validActive ?? (loadedTabs.first { $0.id == "all" }?.id ?? loadedTabs[0].id)

        persist() // simpan hasil migrasi di atas (hapus duplikat &/atau tambah tab crypto)
    }

    func addTab(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let newTab = WatchlistTab(id: UUID().uuidString, name: trimmed)
        tabs.append(newTab)
        activeID = newTab.id
        persist()
    }

    func deleteTab(id: String) {
        // Tidak boleh hapus jika hanya tersisa 1
        guard tabs.count > 1 else { return }
        tabs.removeAll { $0.id == id }
        if activeID == id { activeID = tabs[0].id }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(tabs) {
            UserDefaults.standard.set(data, forKey: tabsKey)
        }
        UserDefaults.standard.set(activeID, forKey: activeKey)
    }
}
