//
//  SearchView.swift
//  SahamIndo
//
//  Fitur search seluruh universe saham (NASDAQ/ETF/IDX), tombol Analyze
//  on-demand, dan toggle watchlist — tanpa membebani job terjadwal backend.
//

import SwiftUI

struct SearchView: View {

    @StateObject private var vm: SearchViewModel
    @EnvironmentObject private var router: Router

    init(vm: SearchViewModel) {
        _vm = StateObject(wrappedValue: vm)
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar

            if vm.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                emptyPrompt
            } else if vm.isSearching {
                searchingIndicator
            } else if vm.results.isEmpty {
                noResultsView
            } else {
                resultsList
            }
        }
        .background(Color.DarkPurpleAppBackground.ignoresSafeArea())
        .navigationTitle("Cari Saham")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $vm.analyzeResult) { result in
            AnalyzeResultSheet(result: result) { kode, add in
                Task {
                    if add { await vm.addToWatchlist(kode: kode) }
                    else   { await vm.removeFromWatchlist(kode: kode) }
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let msg = vm.errorMessage {
                ErrorSnackbar(message: msg)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 16)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            vm.errorMessage = nil
                        }
                    }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: vm.errorMessage)
    }

    // MARK: - Sub-views

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)

            TextField("Cari simbol atau nama (misal SNPS, QQQ, BBCA...)", text: $vm.query)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .foregroundColor(.primary)
                .submitLabel(.search)

            if !vm.query.isEmpty {
                Button { vm.query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                }
            }
        }
        .padding(10)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    private var emptyPrompt: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "globe.americas.fill")
                .font(.system(size: 52))
                .foregroundColor(Color.PrimaryYellow.opacity(0.6))
            Text("Cari dari ribuan saham NASDAQ, ETF, dan IDX")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
    }

    private var searchingIndicator: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView()
                .tint(Color.PrimaryYellow)
            Text("Mencari...").font(.caption).foregroundColor(.secondary)
            Spacer()
        }
    }

    private var noResultsView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "magnifyingglass").font(.largeTitle).foregroundColor(.secondary)
            Text("Tidak ditemukan untuk \"\(vm.query)\"")
                .font(.subheadline).foregroundColor(.secondary)
            Spacer()
        }
    }

    private var resultsList: some View {
        List(vm.results) { result in
            SearchResultRow(
                result:      result,
                isAnalyzing: vm.analyzingKode == result.kode,
                anyAnalyzing: vm.analyzingKode != nil
            ) {
                Task { await vm.analyze(kode: result.kode, market: result.market, nama: result.nama) }
            } onToggleWatchlist: {
                Task {
                    if result.isWatchlist { await vm.removeFromWatchlist(kode: result.kode) }
                    else                  { await vm.addToWatchlist(kode: result.kode) }
                }
            } onOpenDetail: {
                router.push(.stockDetail(portfolioItem(from: result)))
            }
            .listRowBackground(Color.DarkPurpleAppBackground)
            .listRowSeparatorTint(Color.white.opacity(0.07))
        }
        .listStyle(.plain)
        .scrollDismissesKeyboard(.immediately)
    }

    /// PortfolioItem minimal dari hasil search — cukup untuk membuka
    /// StockDetailView tanpa perlu masuk watchlist dulu. Detail & chart
    /// di-fetch ulang oleh StockDetailViewModel berdasarkan `symbol`,
    /// jadi price/quantity awal boleh nol.
    private func portfolioItem(from result: SymbolSearchResult) -> PortfolioItem {
        PortfolioItem(
            symbol:        result.kode,
            name:          result.nama,
            price:         0,
            change:        0,
            percentChange: 0,
            quantity:      0,
            sentiment:     Sentiment.estimated(percentChange: 0),
            market:        result.market.rawValue
        )
    }
}

// MARK: - SearchResultRow

private struct SearchResultRow: View {
    let result:         SymbolSearchResult
    let isAnalyzing:    Bool
    let anyAnalyzing:   Bool
    let onAnalyze:      () -> Void
    let onToggleWatchlist: () -> Void
    let onOpenDetail:   () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Market badge + Symbol + name — tap untuk buka StockDetailView
            HStack(spacing: 12) {
                MarketBadge(market: result.market)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(result.kode)
                            .font(.system(.subheadline, design: .monospaced, weight: .bold))
                            .foregroundColor(.primary)
                        if result.tipe == "ETF" {
                            Text("ETF")
                                .font(.caption2).fontWeight(.semibold)
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(Color.purple.opacity(0.25))
                                .foregroundColor(.purple)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }
                    Text(result.nama)
                        .font(.caption).foregroundColor(.secondary)
                        .lineLimit(1)
                    if let exchange = result.exchange {
                        Text(exchange).font(.caption2).foregroundColor(.primary)
                    }
                }

                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpenDetail)

            // Watchlist star
            Button(action: onToggleWatchlist) {
                Image(systemName: result.isWatchlist ? "star.fill" : "star")
                    .foregroundColor(result.isWatchlist ? Color.PrimaryYellow : .secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)

            // Analyze button
            Button(action: onAnalyze) {
                if isAnalyzing {
                    ProgressView()
                        .tint(Color.PrimaryYellow)
                        .frame(width: 60, height: 32)
                } else {
                    Text("Analyze")
                        .font(.caption).fontWeight(.semibold)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(
                            anyAnalyzing
                                ? Color(.systemGray4)
                                : Color.PrimaryYellow
                        )
                        .foregroundColor(anyAnalyzing ? .secondary : .black)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .buttonStyle(.plain)
            .disabled(anyAnalyzing)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

// MARK: - MarketBadge

struct MarketBadge: View {
    let market: Market

    private var color: Color {
        switch market {
        case .idx:    return Color(red: 0.12, green: 0.55, blue: 0.95)
        case .nasdaq: return Color(red: 0.20, green: 0.80, blue: 0.45)
        case .nyse:   return Color(red: 0.90, green: 0.55, blue: 0.10)
        case .etf:    return Color.purple
        }
    }

    var body: some View {
        Text(market.label)
            .font(.system(size: 9, weight: .bold))
            .padding(.horizontal, 5).padding(.vertical, 3)
            .background(color.opacity(0.20))
            .foregroundColor(color)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .frame(width: 52)
    }
}

// MARK: - ErrorSnackbar

private struct ErrorSnackbar: View {
    let message: String
    var body: some View {
        Text(message)
            .font(.caption)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(.systemGray5))
            .clipShape(Capsule())
            .shadow(radius: 4)
    }
}
