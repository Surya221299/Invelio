//
//  AIInsightCardView.swift
//  StockAppTryNew
//
//  Created by Surya on 16/06/26.
//

import SwiftUI

struct AIInsightCardView: View {

    let chips: [InsightChip]

    private let accent = Color.PrimaryYellow
    private let readMoreThreshold = 30

    @State private var selectedIndex: Int    = 0
    @State private var isPulsing:     Bool   = false
    @State private var wordIndex:     Int    = 0
    @State private var targetWords:   [String] = []
    @State private var timer:         Timer? = nil
    @State private var isExpanded:    Bool   = false
    @State private var showReadMore:  Bool   = false
    @State private var hasStarted:    Bool   = false

    private var selectedChip: InsightChip? { chips.indices.contains(selectedIndex) ? chips[selectedIndex] : nil }
    private var displayedText: String { targetWords.prefix(wordIndex).joined(separator: " ") }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                // Header
                HStack {
                    liveBadge
                    Spacer()
                }

                // Animated insight text
                let isLong = targetWords.count > readMoreThreshold
                let lineLimit: Int? = (isLong && !isExpanded) ? 3 : nil
                let mask: AnyView = (isLong && !isExpanded) ? fadeMask.eraseToAnyView() : Color.black.eraseToAnyView()
                let insightText = buildAttributedText(from: displayedText)
                VStack(alignment: .leading, spacing: 8) {
                    insightText
                        .font(Font.subheadline)
                        .foregroundColor(Color.primary.opacity(0.85))
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(lineLimit)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .transaction { $0.animation = nil }
                        .mask(mask)

                    if isLong && showReadMore {
                        Button {
                            withAnimation(.easeInOut(duration: 0.25)) { isExpanded.toggle() }
                        } label: {
                            HStack(spacing: 4) {
                                Text(isExpanded ? "Sembunyikan" : "Baca selengkapnya")
                                    .font(.system(size: 11, weight: .semibold))
                                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 9, weight: .bold))
                            }
                            .foregroundColor(accent)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        .buttonStyle(.plain)
                        .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
            }
            .padding(12)

            // Chip selector
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(chips.enumerated()), id: \.element.id) { index, chip in
                        InsightChipButton(
                            label:    chip.label,
                            isActive: selectedIndex == index,
                            accent:   accent
                        ) {
                            selectedIndex = index
                            isExpanded    = false
                            startTyping(text: chip.text)
                        }
                    }
                }
                .padding(.horizontal, 12)
            }
            .padding(.bottom, 10)
        }
        .frame(minHeight: 150, alignment: .top)
        .background(Color.AICardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
        .padding(.horizontal, 16)
        .onAppear {
            isPulsing = true
            if !hasStarted, let chip = selectedChip {
                hasStarted = true
                startTyping(text: chip.text)
            }
        }
        .onChange(of: chips) { _, newChips in
            if let chip = newChips.indices.contains(selectedIndex) ? newChips[selectedIndex] : newChips.first {
                startTyping(text: chip.text)
            }
        }
        .onDisappear { stopTimer() }
    }

    // MARK: - Sub-views

    private var liveBadge: some View {
        HStack(spacing: 6) {
            Circle().fill(accent).frame(width: 7, height: 7)
                .scaleEffect(isPulsing ? 0.7 : 1.0)
                .animation(.easeInOut(duration: 1).repeatForever(), value: isPulsing)
            Text("AI Insight")
                .font(Font.caption2)
                .foregroundColor(accent).kerning(0.8)
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(accent.opacity(0.12)).clipShape(Capsule())
        .overlay(Capsule().strokeBorder(accent.opacity(0.35), lineWidth: 0.5))
    }

    private var fadeMask: some View {
        LinearGradient(
            stops: [.init(color: .black, location: 0.0),
                    .init(color: .black, location: 0.45),
                    .init(color: .clear, location: 1.0)],
            startPoint: .top, endPoint: .bottom
        )
    }

    // MARK: - Typing Engine

    private func startTyping(text: String) {
        stopTimer()
        showReadMore = false
        isExpanded   = false
        targetWords  = text.components(separatedBy: " ")
        wordIndex    = 0

        timer = Timer.scheduledTimer(withTimeInterval: 0.07, repeats: true) { t in
            if wordIndex < targetWords.count {
                wordIndex += 1
                if wordIndex == readMoreThreshold && !showReadMore {
                    DispatchQueue.main.async {
                        withAnimation(.easeIn(duration: 0.3)) { showReadMore = true }
                    }
                }
            } else {
                if !showReadMore {
                    DispatchQueue.main.async {
                        withAnimation(.easeIn(duration: 0.3)) { showReadMore = true }
                    }
                }
                t.invalidate(); timer = nil
            }
        }
    }

    private func stopTimer() { timer?.invalidate(); timer = nil }

    // MARK: - Bold Markdown Text

    private func buildAttributedText(from raw: String) -> Text {
        var attrStr = AttributedString("")
        let parts   = raw.components(separatedBy: "**")
        for (i, part) in parts.enumerated() {
            var temp = AttributedString(part)
            if i % 2 == 1 {
                temp.font            = .system(size: 14).weight(.semibold)
                temp.foregroundColor = accent
            } else {
                temp.font            = .system(size: 14)
                temp.foregroundColor = Color.primary.opacity(0.85)
            }
            attrStr.append(temp)
        }
        return Text(attrStr)
    }
}

// MARK: - InsightChipButton

private struct InsightChipButton: View {
    let label:    String
    let isActive: Bool
    let accent:   Color
    let onTap:    () -> Void
    var body: some View {
        Button(action: onTap) {
            Text(label)
                .font(Font.caption2)
                .foregroundColor(isActive ? accent : .secondary)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(isActive ? accent.opacity(0.12) : Color.primary.opacity(0.05))
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(
                    isActive ? accent.opacity(0.45) : Color.primary.opacity(0.1), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - View eraseToAnyView helper

extension View {
    func eraseToAnyView() -> AnyView { AnyView(self) }
}
