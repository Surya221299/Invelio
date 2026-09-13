//
//  ChatbotView.swift
//  StockAppTryNew
//
//  Created by Surya on 16/06/26.
//

import SwiftUI

struct ChatbotView: View {

    @EnvironmentObject private var vm: ChatViewModel
    @EnvironmentObject private var router: Router
    @FocusState private var isInputFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if vm.messages.isEmpty {
                    welcomeView
                } else {
                    messageList
                }
                inputBar
            }
            .animation(.easeInOut(duration: 0.3), value: vm.messages.isEmpty)
            .background(Color.DarkPurpleAppBackground.ignoresSafeArea())
            .navigationTitle("AI Assistant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if !vm.messages.isEmpty {
                        Button("Hapus", action: vm.clear)
                            .font(Font.footnote).foregroundColor(Color.PrimaryYellow)
                    }
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    isInputFocused = true
                }
            }
            .onChange(of: router.selectedTab) { _, newTab in
                if newTab == "chatbot" {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        isInputFocused = true
                    }
                } else {
                    isInputFocused = false
                }
            }
        }
    }

    // MARK: - Sub-views

    private var welcomeView: some View {
        VStack {
            Spacer()
            Text("How can I help you\nwith your investments today?")
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(Color.SurfaceWhite)
                .multilineTextAlignment(.center)
                .lineSpacing(6)
                .padding(.horizontal, 24)
                .padding(.bottom, 28)
                .opacity(vm.inputText.isEmpty ? 1 : 0)
                .scaleEffect(vm.inputText.isEmpty ? 1.0 : 0.95)
                .animation(.easeInOut(duration: 0.25), value: vm.inputText.isEmpty)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            isInputFocused = false
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(vm.messages) { msg in
                        if !msg.content.isEmpty {
                            MessageBubble(message: msg)
                                .id(msg.id)
                        }
                    }
                    if vm.isLoading && (vm.messages.last?.content.isEmpty ?? true) {
                        TypingIndicator()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.interactively)
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
                .focused($isInputFocused)
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

    private let userBubbleGradient = LinearGradient(
        colors: [Color(hex: "665EBF"), Color(hex: "3D3788")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    var body: some View {
        if !message.content.isEmpty {
            HStack {
                if isUser { Spacer(minLength: 40) }
                Text(message.content)
                    .font(Font.footnote)
                    .foregroundColor(isUser ? .SurfaceWhite : .primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background {
                        if isUser {
                            userBubbleGradient
                        } else {
                            Color.appCardBackground
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(isUser ? Color.white.opacity(0.15) : Color.clear, lineWidth: 1)
                    )
                if !isUser { Spacer(minLength: 40) }
            }
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
