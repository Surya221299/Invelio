//
//  WatchlistTabSelectorView.swift
//  SahamIndo
//

import SwiftUI

// MARK: - Tab Selector

struct WatchlistTabSelectorView: View {

    @ObservedObject var store: WatchlistStore
    @State private var showCreateSheet = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(store.tabs) { tab in
                        TabItemView(
                            name:     tab.name,
                            isActive: tab.id == store.activeID
                        )
                        .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { store.activeID = tab.id } }
                    }
                }
                .padding(.leading, 16)
            }

            // Divider tipis sebelum tombol +
            Rectangle()
                .fill(Color.white.opacity(0.15))
                .frame(width: 1, height: 28)
                .padding(.bottom, 4)

            Button {
                showCreateSheet = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .padding(.trailing, 4)
        }
        .sheet(isPresented: $showCreateSheet) {
            CreateWatchlistSheet { name in
                store.addTab(name: name)
            }
            .presentationDetents([.height(220)])
            .presentationDragIndicator(.visible)
            .presentationBackground(Color(UIColor.systemBackground).opacity(0.97))
        }
    }
}

// MARK: - Single Tab Item

private struct TabItemView: View {
    let name:     String
    let isActive: Bool

    private let yellow = Color.PrimaryYellow

    var body: some View {
        VStack(spacing: 0) {
            Text(name)
                .font(.system(size: 14, weight: isActive ? .bold : .regular))
                .foregroundColor(isActive ? yellow : .white.opacity(0.6))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

            // Underline
            Rectangle()
                .fill(isActive ? yellow : Color.clear)
                .frame(height: 2)
                .cornerRadius(1)
        }
        .animation(.easeInOut(duration: 0.2), value: isActive)
    }
}

// MARK: - Create Watchlist Sheet

struct CreateWatchlistSheet: View {

    let onCreate: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Buat Watchlist Baru")
                .font(.system(size: 17, weight: .bold))
                .padding(.top, 8)

            VStack(alignment: .leading, spacing: 6) {
                Text("Nama Watchlist")
                    .font(.caption)
                    .foregroundColor(.secondary)

                TextField("Contoh: Dividen, Growth...", text: $name)
                    .focused($focused)
                    .font(.system(size: 15))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(10)
                    .onSubmit { submit() }
            }

            Button(action: submit) {
                Text("Buat")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(name.trimmingCharacters(in: .whitespaces).isEmpty ? .secondary : Color.PrimaryYellow)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(name.trimmingCharacters(in: .whitespaces).isEmpty
                                  ? Color(UIColor.tertiarySystemBackground)
                                  : Color.PrimaryYellow.opacity(0.15))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(name.trimmingCharacters(in: .whitespaces).isEmpty
                                    ? Color.clear
                                    : Color.PrimaryYellow.opacity(0.4), lineWidth: 1)
                    )
            }
            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)

            Spacer()
        }
        .padding(.horizontal, 24)
        .onAppear { focused = true }
    }

    private func submit() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        onCreate(trimmed)
        dismiss()
    }
}
