//
//  ChatbotView.swift
//  StockAppTryNew
//
//  Created by Surya on 16/06/26.
//

import SwiftUI

struct ChatbotView: View {

    @EnvironmentObject private var vm: ChatViewModel

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                messageList
                inputBar
            }
            .background(Color.DarkPurpleAppBackground.ignoresSafeArea())
            .navigationTitle("AI Assistant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Hapus", action: vm.clear)
                        .font(Font.footnote).foregroundColor(Color.PrimaryYellow)
                }
            }
        }
    }

    // MARK: - Sub-views

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(vm.messages) { msg in
                        MessageBubble(message: msg)
                            .id(msg.id)
                    }
                    if vm.isLoading {
                        TypingIndicator()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .onChange(of: vm.messages.count) { _, _ in
                if let last = vm.messages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Tanya tentang saham IDX...", text: $vm.inputText, axis: .vertical)
                .font(Font.subheadline)
                .lineLimit(1...4)
                .padding(10)
                .background(Color.appCardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            Button {
                let text = vm.inputText
                vm.inputText = ""
                Task { await vm.send(text) }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(vm.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                     ? Color.secondary : Color.PrimaryYellow)
            }
            .disabled(vm.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || vm.isLoading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.DarkPurpleAppBackground)
        .overlay(Divider(), alignment: .top)
    }
}

// MARK: - MessageBubble

private struct MessageBubble: View {
    let message: ChatMessage
    private var isUser: Bool { message.role == .user }
    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 40) }
            Text(message.content)
                .font(Font.footnote)
                .foregroundColor(isUser ? .SurfaceWhite : .primary)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(isUser ? Color.PrimaryYellow : Color.appCardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            if !isUser { Spacer(minLength: 40) }
        }
    }
}

// MARK: - TypingIndicator

private struct TypingIndicator: View {
    @State private var animating = false
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { i in
                Circle().fill(Color.PrimaryYellow).frame(width: 6, height: 6)
                    .scaleEffect(animating ? 1.2 : 0.8)
                    .animation(.easeInOut(duration: 0.6).repeatForever().delay(Double(i) * 0.2), value: animating)
            }
        }
        .padding(10).background(Color.appCardBackground).clipShape(Capsule())
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { animating = true }
    }
}
