//
//  NotificationEntities.swift
//  StockAppTryNew
//
//  Created by Surya on 16/06/26.
//

import Foundation
import SwiftUI

// MARK: - StockAlert (persisted)

struct StockAlert: Identifiable, Codable {
    var id: UUID = UUID()
    var date: Date
    var symbol: String
    var stockName: String?
    var sector: String?
    var alertType: AlertType
    var score: Double
    var aiSummary: String
    var isRead: Bool = false

    enum AlertType: String, Codable {
        case strongBuy         = "strongBuy"
        case strongSell        = "strongSell"
        /// Pengingat jadwal rilis laporan keuangan (H-3 / H-1), dari backend job
        /// check_earnings_and_rally_job (jenis="earnings" di tabel alert).
        case earningsReminder  = "earningsReminder"
        /// Harga hijau (naik) 3+ hari perdagangan berturut-turut, dari backend
        /// job yang sama (jenis="rally_streak").
        case rallyStreak       = "rallyStreak"

        /// True untuk tipe yang punya makna "skor sentimen 0-100" (gauge bar
        /// di layar detail cuma relevan untuk dua tipe ini).
        var isSentimentBased: Bool {
            self == .strongBuy || self == .strongSell
        }

        var displayLabel: String {
            switch self {
            case .strongBuy:        return "STRONG BUY"
            case .strongSell:       return "STRONG SELL"
            case .earningsReminder: return "EARNINGS"
            case .rallyStreak:      return "RALLY STREAK"
            }
        }

        var iconName: String {
            switch self {
            case .strongBuy:        return "arrow.up.circle.fill"
            case .strongSell:       return "exclamationmark.circle.fill"
            case .earningsReminder: return "calendar.badge.clock"
            case .rallyStreak:      return "flame.fill"
            }
        }

        /// Warna utama badge/ikon untuk tipe ini.
        func color(green: Color, red: Color, indigo: Color) -> Color {
            switch self {
            case .strongBuy, .rallyStreak: return green
            case .strongSell:              return red
            case .earningsReminder:        return indigo
            }
        }
    }
}

// MARK: - Chat

enum MessageRole: String, Codable {
    case user      = "user"
    case assistant = "assistant"
}

struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    let role: MessageRole
    var content: String
    let timestamp: Date = Date()
}

struct ChatHistoryItem: Codable {
    let role: String
    let content: String
}

// MARK: - CacheState (UI feedback)

enum CacheState: Equatable {
    case live
    case cached(age: String)
    case noData
}
