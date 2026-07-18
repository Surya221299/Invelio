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
