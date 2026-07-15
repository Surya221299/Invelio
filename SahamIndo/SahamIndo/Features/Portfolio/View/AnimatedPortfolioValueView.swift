//
//  AnimatedPortfolioValueView.swift
//  SahamIndo
//
//  Menampilkan nilai saham portfolio dengan:
//  - Angka cached dari UserDefaults muncul langsung saat app buka
//  - Saat nilai server tiba (setelah 2 detik), angka roll/speedometer ke nilai baru
//  - Flash merah 1 detik jika nilai turun, flash hijau 1 detik jika naik
//

import SwiftUI

// MARK: - Animated Value View

struct AnimatedPortfolioValueView: View {

    /// Nilai yang ditampilkan — di-drive dari luar via withAnimation
    let displayValue: Double
    /// Flash state di-drive dari luar
    let flashState:   FlashState

    enum FlashState { case none, up, down }

    private let green = Color.ProfitGreen
    private let red   = Color.LossRed

    private var flashColor: Color? {
        switch flashState {
        case .up:   return green
        case .down: return red
        case .none: return nil
        }
    }

    var body: some View {
        RollingNumberText(value: displayValue)
            .overlay(
                flashColor.map { color in
                    AnyView(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(color.opacity(0.18))
                            .allowsHitTesting(false)
                    )
                } ?? AnyView(EmptyView())
            )
            .animation(.easeOut(duration: 0.3), value: flashState == .none)
    }
}

// MARK: - Rolling Number Text
// Tiap digit di-animate secara independen (speedometer style).

struct RollingNumberText: View {

    let value: Double

    private var formatted: String { formatIDR(value) }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(formatted.enumerated()), id: \.offset) { idx, char in
                if let digit = char.wholeNumberValue {
                    RollingDigit(digit: digit)
                } else {
                    Text(String(char))
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                }
            }
        }
    }
}

// MARK: - Rolling Digit

private struct RollingDigit: View {
    let digit: Int
    @State private var displayDigit: Int = 0

    var body: some View {
        Text("\(displayDigit)")
            .font(.system(size: 30, weight: .bold, design: .rounded))
            .foregroundColor(.primary)
            .contentTransition(.numericText(value: Double(displayDigit)))
            .onAppear { displayDigit = digit }
            .onChange(of: digit) { _, newVal in
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                    displayDigit = newVal
                }
            }
    }
}

// MARK: - Container that manages flash + animate timing

struct PortfolioValueAnimator: View {

    @EnvironmentObject private var portfolioVM: PortfolioViewModel

    @State private var displayValue: Double = 0
    @State private var flashState:   AnimatedPortfolioValueView.FlashState = .none
    @State private var hasLoaded:    Bool = false

    var body: some View {
        AnimatedPortfolioValueView(displayValue: displayValue, flashState: flashState)
            .onAppear {
                guard !hasLoaded else { return }
                hasLoaded    = true
                displayValue = portfolioVM.cachedStockValue
            }
            .onChange(of: portfolioVM.serverStockValue) { _, serverVal in
                // >= 0: izinkan animasi turun ke 0 saat semua saham terjual.
                guard let serverVal, serverVal >= 0 else { return }
                let prev = displayValue
                // Delay 2 detik untuk efek "loading from cache then update"
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    let direction: AnimatedPortfolioValueView.FlashState =
                        serverVal > prev ? .up : serverVal < prev ? .down : .none

                    withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                        displayValue = serverVal
                    }
                    if direction != .none {
                        flashState = direction
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            withAnimation(.easeOut(duration: 0.4)) { flashState = .none }
                        }
                    }
                }
            }
    }
}

// MARK: - IDR Formatter (mirrors formatIDR in rest of app)

private func formatIDR(_ value: Double) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle       = .currency
    formatter.currencyCode      = "IDR"
    formatter.currencySymbol    = "Rp "
    formatter.maximumFractionDigits = 0
    formatter.minimumFractionDigits = 0
    return formatter.string(from: NSNumber(value: value)) ?? "Rp 0"
}
