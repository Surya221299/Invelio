//
//  ColorExtensions.swift
//  StockAppTryNew
//
//  Created by Surya on 16/06/26.
//
//  Single source of truth for every color used in the app.
//  Feature code should never write `Color(hex:)` or a raw system color
//  (e.g. `Color.blue`) directly — it should reference one of the static
//  lets defined here instead.
//

import SwiftUI

extension Color {

    // MARK: App Background (asset-backed)
    static let DarkPurpleAppBackground = Color("DarkPurpleAppBackground")

    // MARK: Gain Green (asset-backed) — used for any "profit / positive" indicator
    static let ProfitGreen = Color("ProfitGreen")

    // MARK: Loss Red (asset-backed) — used for any "loss / negative" indicator
    static let LossRed = Color("LossRed")

    // MARK: Primary Accent (asset-backed) — the app's primary brand/accent color
    // (tab tint, CTA buttons, AI badges, segmented control tint, etc.)
    static let PrimaryYellow = Color("PrimaryYellow")

    // MARK: Surface White (asset-backed) — pure white surfaces/text on dark backgrounds
    static let SurfaceWhite = Color("SurfaceWhite")

    // MARK: Secondary Accents (no dedicated asset yet — defined once, here)
    static let AccentGold   = Color(hex: "EAB308") // neutral sentiment / baseline markers
    static let AccentIndigo = Color(hex: "818CF8") // AI / "new" info badges

    // MARK: Stock Avatar Gradient Palette
    // Deterministic decorative gradients used by StockAvatarView when no logo image exists.
    static let avatarGradientPalette: [[Color]] = [
        [Color(hex: "3B82F6"), Color(hex: "1D4ED8")],
        [Color(hex: "EC4899"), Color(hex: "BE185D")],
        [Color(hex: "8B5CF6"), Color(hex: "6D28D9")],
        [Color(hex: "10B981"), Color(hex: "047857")],
        [Color(hex: "F59E0B"), Color(hex: "D97706")],
        [Color(hex: "EF4444"), Color(hex: "B91C1C")],
        [Color(hex: "06B6D4"), Color(hex: "0891B2")]
    ]

    /// Internal helper used only to define the tokens above — feature code should not call this directly.
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hex.count {
        case 6: (r, g, b) = ((int >> 16) & 0xff, (int >> 8) & 0xff, int & 0xff)
        default: (r, g, b) = (1, 1, 1)
        }
        self.init(.sRGB, red: Double(r)/255, green: Double(g)/255, blue: Double(b)/255, opacity: 1)
    }

//    static let appBackground = Color(UIColor { tc in
//        tc.userInterfaceStyle == .dark
//            ? UIColor(red: 18/255, green: 17/255, blue: 46/255, alpha: 1)
//            : .systemBackground
//    })

    static let appCardBackground = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 28/255, green: 27/255, blue: 53/255, alpha: 1)
            : .secondarySystemBackground
    })

    static let appElevatedBackground = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 30/255, green: 29/255, blue: 64/255, alpha: 1)
            : .tertiarySystemBackground
    })
}

extension SentimentType {
    /// Maps each sentiment to its Design System color token (no hex parsing involved).
    var color: Color {
        switch self {
        case .recommended: return .ProfitGreen
        case .neutral:      return .AccentGold
        case .caution:      return .LossRed
        }
    }
}
