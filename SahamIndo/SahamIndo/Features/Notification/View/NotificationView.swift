//
//  NotificationView.swift
//  StockAppTryNew
//
//  Refactored: MVVM + Clean Architecture, Separation of Concerns, SOLID
//  View is purely declarative — all logic delegated to NotificationViewModel.
//

import SwiftUI

// MARK: - NotificationView

struct NotificationView: View {

    @EnvironmentObject private var notifVM:   NotificationViewModel
    @EnvironmentObject private var router:    Router
    @EnvironmentObject private var chatVM:    ChatViewModel

    @State private var selectedAlert: StockAlert? = nil

    var body: some View {
        Group {
            if notifVM.isChecking && notifVM.alerts.isEmpty {
                NotificationLoadingStateView()
            } else if notifVM.alerts.isEmpty {
                NotificationEmptyStateView(isChecking: notifVM.isChecking)
            } else {
                NotificationAlertsListView(
                    alerts:         notifVM.alerts,
                    isChecking:     notifVM.isChecking,
                    onTapAlert:     { alert in
                        notifVM.markRead(alert.id)
                        selectedAlert = alert
                    }
                )
            }
        }
        .background(Color.DarkPurpleAppBackground.ignoresSafeArea())
        .navigationTitle("Notifikasi Sinyal")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !notifVM.alerts.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    NotificationMenuView(
                        onMarkAllRead: { notifVM.markAllRead() },
                        onClearAll:    { notifVM.clearAll() }
                    )
                }
            }
        }
        .sheet(item: $selectedAlert) { alert in
            NotificationDetailView(alert: alert)
                .environmentObject(router)
                .environmentObject(chatVM)
        }
        .task { await notifVM.checkForAlerts() }
    }
}

// MARK: - Notification Menu

private struct NotificationMenuView: View {

    let onMarkAllRead: () -> Void
    let onClearAll:    () -> Void

    var body: some View {
        Menu {
            Button(action: onMarkAllRead) {
                Label("Tandai Semua Dibaca", systemImage: "checkmark.circle")
            }
            Button(role: .destructive, action: onClearAll) {
                Label("Hapus Semua", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle").foregroundColor(.primary)
        }
    }
}

// MARK: - Loading State

struct NotificationLoadingStateView: View {

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(Color.PrimaryYellow)
                .scaleEffect(1.2)
            Text("Memeriksa sinyal pasar dari database…")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Empty State

struct NotificationEmptyStateView: View {

    let isChecking: Bool

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "bell.slash")
                .font(.system(size: 44))
                .foregroundColor(.secondary)
                .padding(.bottom, 4)

            Text("Belum Ada Sinyal")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.primary)

            Text("Sistem memantau sentimen \(isChecking ? "saat ini…" : "setiap jam"). Notifikasi akan muncul ketika ada sinyal bullish/bearish kuat, jadwal rilis laporan keuangan mendekat, atau rally streak (hijau berturut-turut).")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Alerts List

struct NotificationAlertsListView: View {

    let alerts:     [StockAlert]
    let isChecking: Bool
    let onTapAlert: (StockAlert) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if isChecking {
                    HStack(spacing: 8) {
                        ProgressView().scaleEffect(0.75).tint(.secondary)
                        Text("Memperbarui dari database…")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 10)
                }

                VStack(spacing: 8) {
                    ForEach(alerts) { alert in
                        AlertRowView(alert: alert)
                            .onTapGesture { onTapAlert(alert) }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
    }
}

// MARK: - Alert Row

struct AlertRowView: View {

    let alert: StockAlert

    private let green  = Color.ProfitGreen
    private let red    = Color.LossRed
    private let indigo = Color.AccentIndigo
    private let cardBg = Color.appCardBackground

    private var signalColor: Color { alert.alertType.color(green: green, red: red, indigo: indigo) }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            signalIcon

            VStack(alignment: .leading, spacing: 4) {
                alertHeader
                stockNameRow
                summaryPreview
                dateRow
            }

            unreadDot
        }
        .padding(12)
        .background(cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    alert.isRead ? Color.primary.opacity(0.06) : signalColor.opacity(0.3),
                    lineWidth: 1
                )
        )
        .opacity(alert.isRead ? 0.75 : 1.0)
    }

    // MARK: Sub-views

    private var signalIcon: some View {
        Image(systemName: alert.alertType.iconName)
            .font(.system(size: 30))
            .foregroundColor(signalColor)
    }

    private var alertHeader: some View {
        HStack(spacing: 6) {
            Text(alert.symbol)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.primary)

            AlertTypeBadgeView(label: alert.alertType.displayLabel, textColor: badgeTextColor, bgColor: signalColor)

            Spacer()

            if alert.alertType.isSentimentBased {
                Text("Score \(Int(alert.score))")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(signalColor)
            }
        }
    }

    private var badgeTextColor: Color {
        alert.alertType == .strongBuy || alert.alertType == .rallyStreak ? .black : .SurfaceWhite
    }

    @ViewBuilder
    private var stockNameRow: some View {
        if let name = alert.stockName {
            Text(name)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
    }

    private var summaryPreview: some View {
        Text(String(alert.aiSummary.prefix(100)) + "…")
            .font(.system(size: 11))
            .foregroundColor(Color.primary.opacity(0.7))
            .lineLimit(2)
    }

    private var dateRow: some View {
        Text(relativeDate(alert.date))
            .font(.system(size: 9))
            .foregroundColor(.secondary)
            .padding(.top, 1)
    }

    @ViewBuilder
    private var unreadDot: some View {
        if !alert.isRead {
            Circle().fill(Color.AccentIndigo)
                .frame(width: 8, height: 8)
                .padding(.top, 6)
        }
    }

    // MARK: Helper

    private func relativeDate(_ date: Date) -> String {
        let diff = Date().timeIntervalSince(date)
        if diff < 60    { return "Baru saja" }
        if diff < 3600  { return "\(Int(diff / 60)) menit lalu" }
        if diff < 86400 { return "\(Int(diff / 3600)) jam lalu" }
        let f = DateFormatter()
        f.dateFormat = "d MMM yyyy, HH:mm"
        f.locale = Locale(identifier: "id_ID")
        return f.string(from: date)
    }
}

// MARK: - Alert Type Badge

struct AlertTypeBadgeView: View {

    let label:     String
    let textColor: Color
    let bgColor:   Color

    var body: some View {
        Text(label)
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(textColor)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(bgColor)
            .clipShape(Capsule())
    }
}

// MARK: - Notification Detail View

struct NotificationDetailView: View {

    let alert: StockAlert

    @EnvironmentObject private var router:  Router
    @EnvironmentObject private var chatVM:  ChatViewModel
    @Environment(\.dismiss) private var dismiss

    private let green   = Color.ProfitGreen
    private let red     = Color.LossRed
    private let accent  = Color.PrimaryYellow
    private let indigo  = Color.AccentIndigo
    private let cardBg  = Color.appCardBackground
    //private let bgColor = Color.appBackground

    private var signalColor: Color { alert.alertType.color(green: green, red: red, indigo: indigo) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    NotificationDetailHeaderCard(alert: alert, signalColor: signalColor)
                    if alert.alertType.isSentimentBased {
                        NotificationScoreCard(alert: alert, signalColor: signalColor, green: green, red: red)
                    }
                    NotificationAISummaryCard(alert: alert, indigo: indigo)
                    NotificationAskAgentButton(accent: accent, onTap: askAIAgent)
                }
                .padding(16)
                .padding(.bottom, 32)
            }
            .background(Color.DarkPurpleAppBackground.ignoresSafeArea())
            .navigationTitle(alert.symbol)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Tutup") { dismiss() }.foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Ask AI Agent

    private func askAIAgent() {
        let sectorPart = alert.sector.map { " di sektor \($0)" } ?? ""
        let namePart   = alert.stockName.map { " (\($0))" } ?? ""

        let pertanyaan: String
        switch alert.alertType {
        case .strongBuy, .strongSell:
            let signalType = alert.alertType == .strongBuy
                ? "bullish kuat (Strong Buy)"
                : "bearish kuat (Strong Sell)"
            pertanyaan = """
            Berikan analisis mendalam tentang saham \(alert.symbol)\(namePart)\(sectorPart) yang memiliki sinyal \(signalType) dengan skor sentimen \(Int(alert.score))/100. \
            Jelaskan: (1) faktor utama yang mendorong sinyal ini, (2) risiko yang perlu diperhatikan, \
            (3) potensi target harga jangka pendek & menengah, dan (4) rekomendasi tindakan konkret dengan sumber referensinya.
            """
        case .earningsReminder:
            pertanyaan = """
            Saham \(alert.symbol)\(namePart)\(sectorPart) akan segera merilis laporan keuangan. \
            Konteks: "\(alert.aiSummary)". \
            Jelaskan: (1) apa yang perlu diperhatikan investor menjelang rilis ini, (2) ekspektasi pasar saat ini, \
            (3) bagaimana histori reaksi harga saham ini terhadap rilis laporan keuangan sebelumnya (kalau ada datanya), \
            dan (4) risiko volatilitas menjelang & sesudah rilis.
            """
        case .rallyStreak:
            pertanyaan = """
            Saham \(alert.symbol)\(namePart)\(sectorPart) sedang mengalami rally streak (harga hijau beberapa hari berturut-turut). \
            Konteks: "\(alert.aiSummary)". \
            Jelaskan: (1) apa yang mendorong momentum kenaikan ini, (2) apakah rally ini didukung fundamental/berita atau murni teknikal, \
            (3) risiko koreksi/profit taking setelah rally beruntun, dan (4) rekomendasi sikap untuk investor yang belum/sudah memegang saham ini.
            """
        }

        chatVM.inputText = pertanyaan
        router.selectedTab = "chatbot"
        dismiss()
    }
}

// MARK: - Detail Header Card

struct NotificationDetailHeaderCard: View {

    let alert:       StockAlert
    let signalColor: Color

    private let cardBg = Color.appCardBackground

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: alert.alertType.iconName)
                    .font(.system(size: 40))
                    .foregroundColor(signalColor)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(alert.symbol)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.primary)
                        AlertTypeBadgeView(
                            label: alert.alertType.displayLabel,
                            textColor: (alert.alertType == .strongBuy || alert.alertType == .rallyStreak) ? .black : .SurfaceWhite,
                            bgColor: signalColor
                        )
                    }
                    if let name = alert.stockName {
                        Text(name).font(.system(size: 12)).foregroundColor(.secondary)
                    }
                    if let sector = alert.sector {
                        HStack(spacing: 4) {
                            Image(systemName: "building.2").font(.system(size: 9))
                            Text(sector).font(.system(size: 10))
                        }
                        .foregroundColor(.secondary)
                    }
                }
                Spacer()
            }

            Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)

            HStack {
                HStack(spacing: 4) {
                    Circle().fill(Color.ProfitGreen).frame(width: 6, height: 6)
                    Text("Data live dari database")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text(fullDate(alert.date)).font(.system(size: 10)).foregroundColor(.secondary)
            }
        }
        .padding(16)
        .background(cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(signalColor.opacity(0.3), lineWidth: 1))
    }

    private func fullDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "d MMM yyyy, HH:mm"
        f.locale = Locale(identifier: "id_ID")
        return f.string(from: date)
    }
}

// MARK: - Score Card

struct NotificationScoreCard: View {

    let alert:       StockAlert
    let signalColor: Color
    let green:       Color
    let red:         Color

    private let cardBg = Color.appCardBackground

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Skor Sentimen")
                    .font(.system(size: 14, weight: .bold)).foregroundColor(.primary)
                Spacer()
                Text(String(format: "%.1f / 100", alert.score))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(signalColor)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.primary.opacity(0.08)).frame(height: 10)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(LinearGradient(
                            colors: [signalColor.opacity(0.6), signalColor],
                            startPoint: .leading, endPoint: .trailing))
                        .frame(
                            width: geo.size.width * CGFloat(min(alert.score / 100.0, 1.0)),
                            height: 10
                        )
                }
            }
            .frame(height: 10)

            HStack {
                Text("Bearish Kuat")
                    .font(.system(size: 9, weight: .medium)).foregroundColor(red)
                Spacer()
                Text("Bullish Kuat")
                    .font(.system(size: 9, weight: .medium)).foregroundColor(green)
            }
        }
        .padding(16)
        .background(cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.primary.opacity(0.08), lineWidth: 1))
    }
}

// MARK: - AI Summary Card

struct NotificationAISummaryCard: View {

    let alert:  StockAlert
    let indigo: Color

    private let cardBg = Color.appCardBackground

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(indigo)
                Text("Analisis AI dari Database")
                    .font(.system(size: 14, weight: .bold)).foregroundColor(.primary)
                Spacer()
            }

            Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)

            Text(alert.aiSummary)
                .font(.system(size: 13))
                .foregroundColor(Color.primary.opacity(0.85))
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)

            if let sector = alert.sector {
                Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)
                HStack(spacing: 5) {
                    Image(systemName: "building.2").font(.system(size: 10))
                    Text("Sektor: \(sector)").font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(cardBg)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [indigo.opacity(0.35), indigo.opacity(0.08)],
                                startPoint: .topLeading, endPoint: .bottomTrailing),
                            lineWidth: 1)
                )
        )
    }
}

// MARK: - Ask Agent Button

struct NotificationAskAgentButton: View {

    let accent: Color
    let onTap:  () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 16, weight: .semibold))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Tanya AI Agent")
                        .font(.system(size: 14, weight: .bold))
                    Text("Analisis mendalam + sumber & rekomendasi konkret")
                        .font(.system(size: 10)).opacity(0.82)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundColor(.SurfaceWhite)
            .padding(16)
            .background(accent)
            .cornerRadius(14)
        }
        .buttonStyle(.plain)
    }
}
