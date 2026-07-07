//
//  ChatViewModel.swift
//  StockAppTryNew
//
//  Created by Surya on 16/06/26.
//

import SwiftUI
import Combine

@MainActor
final class ChatViewModel: ObservableObject {

    @Published var messages:     [ChatMessage] = []
    @Published var inputText:    String        = ""
    @Published var isLoading:    Bool          = false
    @Published var errorMessage: String?

    private let chatRepository: ChatRepositoryProtocol
    private let historyLimit = 10

    private static let welcomeMessage = ChatMessage(
        role: .assistant,
        content: "Halo! Saya adalah SahamIndo AI Assistant. Tanyakan apa saja mengenai rekomendasi emiten saham IDX atau analisis makroekonomi."
    )

    init(chatRepository: ChatRepositoryProtocol) {
        self.chatRepository = chatRepository
        messages = [Self.welcomeMessage]
    }

    func send(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        messages.append(ChatMessage(role: .user, content: trimmed))
        isLoading    = true
        errorMessage = nil

        let history = messages
            .suffix(historyLimit)
            .dropLast()  // exclude the just-appended user message from history
            .map { ChatHistoryItem(role: $0.role.rawValue, content: $0.content) }

        let placeholder = ChatMessage(role: .assistant, content: "")
        messages.append(placeholder)
        guard let idx = messages.firstIndex(where: { $0.id == placeholder.id }) else {
            isLoading = false
            return
        }

        do {
            let stream = try await chatRepository.sendMessage(question: trimmed, history: Array(history))
            for try await chunk in stream {
                messages[idx].content += chunk
            }
        } catch {
            errorMessage = error.localizedDescription
            if messages[idx].content.isEmpty { messages.remove(at: idx) }
            messages.append(ChatMessage(
                role: .assistant,
                content: "⚠️ Gagal terhubung ke AI server. Error: \(error.localizedDescription)"
            ))
        }
        isLoading = false
    }

    func clear() {
        messages  = [Self.welcomeMessage]
        inputText = ""
    }
}
