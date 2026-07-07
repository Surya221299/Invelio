//
//  NotificationViewModel.swift
//  StockAppTryNew
//
//  Created by Surya on 16/06/26.
//

import SwiftUI
import UserNotifications
import Combine

@MainActor
final class NotificationViewModel: ObservableObject {

    @Published private(set) var alerts:     [StockAlert] = []
    @Published private(set) var isChecking: Bool         = false

    var unreadCount: Int { alerts.filter { !$0.isRead }.count }

    private let detailRepository: StockDetailRepositoryProtocol
    private let alertRepository:  AlertRepositoryProtocol
    private let persistence       = UserDefaultsAlertStore()

    private static let watchSymbols = [
        "BBCA","BBRI","BMRI","BBNI","TLKM",
        "ASII","UNVR","ADRO","GGRM","KLBF",
        "ANTM","PGAS","ICBP","INDF","UNTR",
        "PTBA","MEDC","BRIS","AMRT","MDKA"
    ]
    private let bullishThreshold: Double = 75.0
    private let bearishThreshold: Double = 30.0

    init(detailRepository: StockDetailRepositoryProtocol,
         alertRepository:  AlertRepositoryProtocol) {
        self.detailRepository = detailRepository
        self.alertRepository  = alertRepository
        alerts = persistence.load()
    }

    func checkForAlerts() async {
        guard !isChecking else { return }
        if let lastCheck = persistence.lastCheckDate(),
           Date().timeIntervalSince(lastCheck) < 3600 { return }

        isChecking = true
        await requestPermission()

        // --- 1. Sinyal sentimen (strongBuy/strongSell) — dicek langsung dari
        //        detailRepository untuk watchlist tetap, seperti sebelumnya. ---
        let alertedToday = Set(alerts.filter { Calendar.current.isDateInToday($0.date) }.map { $0.symbol })

        for symbol in Self.watchSymbols where !alertedToday.contains(symbol) {
            guard let detail = try? await detailRepository.fetchDetail(symbol: symbol) else { continue }
            let isBuy  = detail.sentimentScore >= bullishThreshold && detail.sentiment == .recommended
            let isSell = detail.sentimentScore <= bearishThreshold && detail.sentiment == .caution
            guard isBuy || isSell else { continue }

            let alert = StockAlert(date: Date(), symbol: detail.symbol, stockName: detail.name,
                                   sector: detail.sector, alertType: isBuy ? .strongBuy : .strongSell,
                                   score: detail.sentimentScore, aiSummary: detail.aiSummary)
            alerts.insert(alert, at: 0)
            await schedulePush(for: alert)
        }

        // --- 2. Jadwal earnings & rally streak — ditarik dari tabel `alert`
        //        backend (dibuat oleh job harian check_earnings_and_rally_job,
        //        jenis='earnings' / 'rally_streak'). Dedup pakai remote id
        //        supaya alert yang sama tidak masuk berkali-kali. ---
        await ingestRemoteEarningsAndRallyAlerts()

        if alerts.count > 50 { alerts = Array(alerts.prefix(50)) }
        persistence.save(alerts)
        persistence.setLastCheckDate(Date())
        isChecking = false
    }

    /// Menarik alert `earnings` & `rally_streak` dari backend (tabel `alert`,
    /// endpoint `/alerts`) dan mengonversinya jadi StockAlert lokal + push
    /// notification, kalau belum pernah di-ingest sebelumnya.
    private func ingestRemoteEarningsAndRallyAlerts() async {
        guard let remoteAlerts = try? await alertRepository.fetchRemoteAlerts() else { return }

        var seenIds = persistence.loadIngestedRemoteIds()
        let relevant = remoteAlerts.filter { $0.jenis == "earnings" || $0.jenis == "rally_streak" }

        for remote in relevant where !seenIds.contains(remote.id) {
            let alertType: StockAlert.AlertType = remote.jenis == "earnings" ? .earningsReminder : .rallyStreak
            let date = StockMapper.parseFlexibleDate(remote.date) ?? Date()

            let newAlert = StockAlert(
                date: date,
                symbol: remote.symbol,
                stockName: nil,
                sector: nil,
                alertType: alertType,
                score: 0,
                aiSummary: remote.message
            )
            alerts.insert(newAlert, at: 0)
            seenIds.insert(remote.id)
            await schedulePush(for: newAlert)
        }

        persistence.saveIngestedRemoteIds(seenIds)
    }

    /// Backend mengirim tanggal alert sebagai string (lihat AlertDTO.tanggal);
    /// parsing fleksibel dilakukan lewat StockMapper.parseFlexibleDate (dipakai
    /// juga untuk tanggal earnings, format sumbernya serupa).

    func markRead(_ id: UUID) {
        guard let idx = alerts.firstIndex(where: { $0.id == id }) else { return }
        alerts[idx].isRead = true
        persistence.save(alerts)
    }

    func markAllRead() {
        alerts = alerts.map { var a = $0; a.isRead = true; return a }
        persistence.save(alerts)
    }

    func clearAll() {
        alerts = []
        persistence.save(alerts)
    }

    private func requestPermission() async {
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .badge, .sound])
    }

    private func schedulePush(for alert: StockAlert) async {
        let content = UNMutableNotificationContent()
        let name    = alert.stockName ?? alert.symbol

        switch alert.alertType {
        case .strongBuy:
            content.title = "📈 Sinyal Bullish Kuat"
            content.body  = "\(alert.symbol) (\(name)) — Score \(Int(alert.score))\n\(String(alert.aiSummary.prefix(100)))…"
        case .strongSell:
            content.title = "📉 Sinyal Bearish Kuat"
            content.body  = "\(alert.symbol) (\(name)) — Score \(Int(alert.score))\n\(String(alert.aiSummary.prefix(100)))…"
        case .earningsReminder:
            content.title = "🗓️ Jadwal Rilis Laporan Keuangan"
            content.body  = "\(alert.symbol): \(String(alert.aiSummary.prefix(120)))…"
        case .rallyStreak:
            content.title = "🔥 Rally Streak"
            content.body  = "\(alert.symbol): \(String(alert.aiSummary.prefix(120)))…"
        }

        content.sound = .default
        let trigger   = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request   = UNNotificationRequest(identifier: alert.id.uuidString, content: content, trigger: trigger)
        try? await UNUserNotificationCenter.current().add(request)
    }
}

// MARK: - UserDefaultsAlertStore (private persistence helper)

private struct UserDefaultsAlertStore {
    private let alertsKey       = "stock_alerts_v1"
    private let lastCheckKey    = "stock_alerts_last_check"
    private let ingestedIdsKey  = "stock_alerts_ingested_remote_ids"
    private let defaults        = UserDefaults.standard

    func load() -> [StockAlert] {
        guard let data    = defaults.data(forKey: alertsKey),
              let decoded = try? JSONDecoder().decode([StockAlert].self, from: data) else { return [] }
        return decoded
    }

    func save(_ alerts: [StockAlert]) {
        guard let data = try? JSONEncoder().encode(alerts) else { return }
        defaults.set(data, forKey: alertsKey)
    }

    func lastCheckDate() -> Date? { defaults.object(forKey: lastCheckKey) as? Date }
    func setLastCheckDate(_ date: Date) { defaults.set(date, forKey: lastCheckKey) }

    /// ID alert backend (tabel `alert`) yang jenisnya earnings/rally_streak dan
    /// sudah pernah dikonversi jadi StockAlert lokal — supaya tidak diulang.
    func loadIngestedRemoteIds() -> Set<Int> {
        guard let arr = defaults.array(forKey: ingestedIdsKey) as? [Int] else { return [] }
        return Set(arr)
    }

    func saveIngestedRemoteIds(_ ids: Set<Int>) {
        // Batasi ukuran supaya tidak tumbuh tak terbatas — cukup simpan 500 ID terakhir.
        let capped = ids.count > 500 ? Set(ids.sorted(by: >).prefix(500)) : ids
        defaults.set(Array(capped), forKey: ingestedIdsKey)
    }
}
