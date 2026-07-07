//
//  StockAvatarView.swift
//  SahamIndo
//
//  Created by Surya on 17/06/26.
//

import SwiftUI

// MARK: - StockAvatarView
struct StockAvatarView: View {
    let symbol: String
    private var gradientColors: [Color] {
        let hash = abs(symbol.hashValue)
        return Color.avatarGradientPalette[hash % Color.avatarGradientPalette.count]
    }
    var body: some View {
        if UIImage(named: symbol) != nil {
            Image(symbol).resizable().scaledToFit()
                .frame(width: DesignSize.avatarS, height: DesignSize.avatarS).clipShape(Circle())
        } else {
            Circle()
                .fill(LinearGradient(colors: gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: DesignSize.avatarS, height: DesignSize.avatarS)
                .overlay(Text(String(symbol.prefix(2)))
                    .font(.system(size: 14, weight: .bold, design: .rounded)).foregroundColor(.SurfaceWhite))
                .shadow(color: Color.black.opacity(0.15), radius: 3, x: 0, y: 1)
        }
    }
}
