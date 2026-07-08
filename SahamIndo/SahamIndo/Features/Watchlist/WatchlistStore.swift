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
        WatchlistTab(id: "all",   name: "Semua"),
        WatchlistTab(id: "idx",   name: "IDX"),
        WatchlistTab(id: "us",    name: "US"),
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
        let loadedTabs: [WatchlistTab]
        if let data = UserDefaults.standard.data(forKey: "watchlist_tabs_v1"),
           let saved = try? JSONDecoder().decode([WatchlistTab].self, from: data),
           !saved.isEmpty {
            loadedTabs = saved
        } else {
            loadedTabs = WatchlistTab.defaultTabs
        }
        tabs = loadedTabs

        // Restore tab terakhir yang aktif dari UserDefaults (kalau ada dan
        // masih valid — id-nya masih ada di daftar tabs saat ini). Kalau
        // belum pernah pilih apa-apa (install baru) atau tab yang terakhir
        // dipilih sudah dihapus, fallback ke tab "Semua".
        let savedActive = UserDefaults.standard.string(forKey: activeKey)
        let validActive = savedActive.flatMap { id in loadedTabs.first { $0.id == id }?.id }
        activeID = validActive ?? (loadedTabs.first { $0.id == "all" }?.id ?? loadedTabs[0].id)
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
