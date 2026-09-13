//
//  SentimentPillView.swift
//  SahamIndo
//
//  Created by Surya on 17/06/26.
//

import SwiftUI
// MARK: - SentimentPillView

enum SentimentPillSize { case small, medium }

struct SentimentPillView: View {
    let sentiment: Sentiment
    var size: SentimentPillSize = .medium
    private var type: SentimentType { sentiment.type }
    private var fontSize: CGFloat { size == .small ? 10 : 11 }
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: type.sfSymbol)
                .font(.system(size: fontSize - 1, weight: .semibold))
            Text(type.rawValue)
                .font(.system(size: fontSize, weight: .semibold))
        }
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(type.color.opacity(0.15))
            .foregroundColor(type.color)
            .clipShape(Capsule())
    }
}

// MARK: - SentimentBarView
struct SentimentBarView: View {
    let sentiment: Sentiment
    var showPercentage: Bool = false
    private var color: Color { sentiment.type.color }
    var body: some View {
        HStack(spacing: 6) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.primary.opacity(0.12)).frame(width: DesignSize.sentimentBarWidth, height: DesignSize.sentimentBarHeight)
                RoundedRectangle(cornerRadius: 3)
                    .fill(color).frame(width: DesignSize.sentimentBarWidth * CGFloat(sentiment.score / 100.0), height: DesignSize.sentimentBarHeight)
            }
            if showPercentage {
                Text(String(format: "%.1f%%", sentiment.score))
                    .font(.system(size: 10, weight: .bold, design: .rounded)).foregroundColor(color)
            }
        }
    }
}
