//
//  ReleaseView.swift
//  SahamIndo
//
//  Tab "Release": tampilan ala CME FedWatch — tanggal rapat FOMC berikutnya,
//  countdown, dan histogram probabilitas target range suku bunga Fed (bps).
//

import SwiftUI

struct ReleaseView: View {

    @StateObject private var vm = DIContainer.shared.makeReleaseViewModel()

    /// Instans keputusan FOMC ≈ 14:00 waktu New York (rilis statement 2pm ET).
    /// meetingDate diparse sebagai tengah malam ET, jadi +14 jam.
    private var announcement: Date? {
        vm.fedWatch.meetingDate.map { $0.addingTimeInterval(14 * 3600) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                meetingCard
                chartCard
                caption
                macroSection
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.DarkPurpleAppBackground.ignoresSafeArea())
        .task { await vm.load() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Text("CME FedWatch")
                .font(.title2).fontWeight(.bold)
                .foregroundColor(.primary)
            if vm.fedWatch.source == .placeholder {
                Text("contoh")
                    .font(.caption2).fontWeight(.semibold)
                    .foregroundColor(.black)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.PrimaryYellow)
                    .clipShape(Capsule())
            }
        }
    }

    // MARK: - Next FOMC Meeting + Countdown

    private var meetingCard: some View {
        VStack(spacing: 12) {
            Text("RAPAT FOMC BERIKUTNYA")
                .font(.caption2).fontWeight(.heavy)
                .tracking(1.5)
                .foregroundColor(.secondary)

            Text(meetingDateString)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(Color.PrimaryYellow)

            if let announcement {
                CountdownView(target: announcement)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var meetingDateString: String {
        guard let date = vm.fedWatch.meetingDate else { return "—" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "id_ID")
        f.timeZone = TimeZone(identifier: "America/New_York")
        f.dateFormat = "EEEE, d MMMM yyyy"
        return f.string(from: date)
    }

    // MARK: - Chart

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Probabilitas Target Range (bps)")
                .font(.subheadline).fontWeight(.semibold)
                .foregroundColor(.primary)

            FedWatchChart(snapshot: vm.fedWatch)
                .frame(height: 260)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var caption: some View {
        Text("Probabilitas tersirat dari harga 30-Day Fed Funds futures (ZQ). Sumber diproses backend.")
            .font(.caption)
            .foregroundColor(.secondary)
    }

    // MARK: - Faktor Makro (di bawah chart FedWatch)

    private var macroSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Text("Faktor Makro Pemerintah AS")
                    .font(.title3).fontWeight(.bold)
                    .foregroundColor(.primary)
                if vm.macroCalendar.source == .placeholder {
                    Text("contoh")
                        .font(.caption2).fontWeight(.semibold)
                        .foregroundColor(.black)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.PrimaryYellow)
                        .clipShape(Capsule())
                }
            }

            if let t = vm.macroCalendar.treasury10Y {
                TreasuryYieldCard(yield: t)
            }

            ForEach(vm.macroCalendar.categories) { category in
                MacroCategoryCard(category: category)
            }

            Text("Tanggal rilis adalah perkiraan terjadwal (mis. NFP = Jumat pertama, jobless claims = tiap Kamis) — verifikasi dengan kalender resmi BLS/BEA. Yield UST 10Y diambil live dari pasar.")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - TreasuryYieldCard

/// Kartu yield US Treasury 10Y (satu-satunya angka live di section makro).
struct TreasuryYieldCard: View {

    let yield: TreasuryYield

    private var changeColor: Color { yield.isUp ? .green : .red }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "dollarsign.circle.fill")
                .font(.system(size: 30))
                .foregroundColor(Color.PrimaryYellow)

            VStack(alignment: .leading, spacing: 2) {
                Text("Yield US Treasury 10 Tahun")
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundColor(.primary)
                Text("Yield naik tajam → saham (terutama tech) tertekan.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "%.2f%%", yield.value))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                HStack(spacing: 2) {
                    Image(systemName: yield.isUp ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 10, weight: .bold))
                    Text(String(format: "%+.2f", yield.change))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                }
                .foregroundColor(changeColor)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - MacroCategoryCard

/// Kartu satu kategori faktor makro (mis. "Data Inflasi") berisi daftar
/// indikator + jadwal rilis + penjelasan dampak ke pasar.
struct MacroCategoryCard: View {

    let category: MacroCategory

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: category.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Color.PrimaryYellow)
                Text(category.title)
                    .font(.subheadline).fontWeight(.bold)
                    .foregroundColor(.primary)
            }

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(category.items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 {
                        Divider().overlay(Color.white.opacity(0.08))
                            .padding(.vertical, 10)
                    }
                    MacroIndicatorRow(item: item)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - MacroIndicatorRow

struct MacroIndicatorRow: View {

    let item: MacroCalendarItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(item.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)
                Spacer(minLength: 8)
                if let rel = relativeLabel {
                    Text(rel)
                        .font(.caption2).fontWeight(.semibold)
                        .foregroundColor(.black)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Color.PrimaryYellow.opacity(0.9))
                        .clipShape(Capsule())
                }
            }

            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.system(size: 10))
                Text(scheduleText)
                    .font(.caption)
            }
            .foregroundColor(.secondary)

            Text(item.impact)
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Baris jadwal: tanggal rilis (ET) kalau ada, jika tidak pakai label jadwal.
    private var scheduleText: String {
        guard let date = item.nextRelease else { return item.scheduleLabel }
        let f = DateFormatter()
        f.locale = Locale(identifier: "id_ID")
        f.timeZone = TimeZone(identifier: "America/New_York")
        f.dateFormat = "EEE, d MMM yyyy · HH:mm"
        let prefix = item.isEstimate ? "≈ " : ""
        return "\(prefix)\(f.string(from: date)) ET"
    }

    /// Badge "N hari lagi" / "hari ini" untuk rilis mendatang.
    private var relativeLabel: String? {
        guard let date = item.nextRelease else { return nil }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: date).day ?? 0
        if days < 0 { return nil }
        if days == 0 { return "hari ini" }
        if days == 1 { return "besok" }
        return "\(days) hari lagi"
    }
}

// MARK: - CountdownView

/// Countdown live (Hari · Jam · Menit · Detik) menuju `target`.
struct CountdownView: View {

    let target: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(0, target.timeIntervalSince(context.date))
            let d = Int(remaining) / 86400
            let h = (Int(remaining) % 86400) / 3600
            let m = (Int(remaining) % 3600) / 60
            let s = Int(remaining) % 60

            HStack(spacing: 10) {
                unit(d, "HARI")
                unit(h, "JAM")
                unit(m, "MENIT")
                unit(s, "DETIK")
            }
        }
    }

    private func unit(_ value: Int, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(String(format: "%02d", value))
                .font(.system(size: 22, weight: .bold, design: .monospaced))
                .foregroundColor(.primary)
                .frame(minWidth: 44)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.25))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - FedWatchChart

/// Histogram vertikal probabilitas FedWatch: persen di atas bar, label range
/// (bps) di bawah. Reusable & self-contained.
struct FedWatchChart: View {

    let snapshot: FedWatchSnapshot

    private var maxProbability: Double {
        max(0.0001, snapshot.outcomes.map(\.probability).max() ?? 0.0001)
    }

    var body: some View {
        GeometryReader { geo in
            HStack(alignment: .bottom, spacing: geo.size.width * 0.06) {
                ForEach(snapshot.outcomes) { outcome in
                    column(outcome, barArea: geo.size.height * 0.74)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }

    private func column(_ outcome: FedWatchOutcome, barArea: CGFloat) -> some View {
        let isTop = outcome == snapshot.mostLikely
        let height = max(8, barArea * CGFloat(outcome.probability / maxProbability))

        return VStack(spacing: 8) {
            Text(percentText(outcome.probability))
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(isTop ? Color.PrimaryYellow : .primary)

            RoundedRectangle(cornerRadius: 6)
                .fill(barColor(for: outcome.probability, highlighted: isTop))
                .frame(height: height)

            Text(outcome.rangeLabel)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    private func barColor(for probability: Double, highlighted: Bool) -> Color {
        let intensity = min(1, probability * (highlighted ? 1.6 : 1.2) + 0.15)
        return Color.PrimaryYellow.opacity(0.35 + 0.6 * intensity)
    }

    private func percentText(_ p: Double) -> String {
        String(format: "%.0f%%", (p * 100).rounded())
    }
}

#Preview {
    ReleaseView()
}
