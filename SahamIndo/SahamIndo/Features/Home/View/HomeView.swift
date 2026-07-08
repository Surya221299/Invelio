//
//  HomeView.swift
//  SahamIndo
//
//  Ditambah tombol search (🔍) di top bar yang membawa user ke tab Search
//  untuk mencari saham di luar 20 IDX watchlist (NASDAQ/ETF).
//

//
//  HomeView.swift
//  SahamIndo
//
//  Ditambah tombol search (🔍) di top bar yang membawa user ke tab Search
//  untuk mencari saham di luar 20 IDX watchlist (NASDAQ/ETF).
//

import SwiftUI

struct HomeView: View {

    @EnvironmentObject private var portfolioVM: PortfolioViewModel
    @EnvironmentObject private var homeVM:      HomeViewModel
    @EnvironmentObject private var notifVM:     NotificationViewModel
    @EnvironmentObject private var router:      Router
    @StateObject private var watchlistStore = WatchlistStore()

    // Observe LivePriceStore LANGSUNG (bukan cuma lewat homeVM.objectWillChange
    // forwarding) — jaminan tambahan supaya body benar-benar re-render tiap
    // ada harga baru, terlepas dari behavior forwarding di HomeViewModel.
    @ObservedObject private var livePriceStore = LivePriceStore.shared

    /// `homeVM.liveStocks` disaring sesuai tab watchlist yang aktif.
    /// "idx" → cuma saham IDX. "us" → cuma NASDAQ/NYSE/ETF (semua yang bukan
    /// IDX). "all" (Semua) atau tab custom lain (belum ada fitur assign
    /// saham ke tab custom) → tampilkan semua, tidak difilter.
    private var filteredStocks: [PortfolioItem] {
        switch watchlistStore.activeID {
        case "idx": return homeVM.liveStocks.filter { $0.market.uppercased() == "IDX" }
        case "us":  return homeVM.liveStocks.filter { $0.market.uppercased() != "IDX" }
        default:    return homeVM.liveStocks
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                PortfolioSummaryCardView(
                    summary:  portfolioVM.summary,
                    items:    portfolioVM.items,
                    holdings: portfolioVM.holdings
                )
                .padding(.top, 12)
                .padding(.bottom, 20)

                AIInsightCardView(chips: homeVM.insightChips)
                    .padding(.vertical, 12)

                sectionHeader("Watchlist")

                WatchlistTabSelectorView(store: watchlistStore)

                Divider()
                    .frame(height: 1.5)
                    .background(Color.PrimaryYellow)
                    .padding(.horizontal)

                StockListView(
                    items: filteredStocks,
                    onTap: { router.push(.stockDetail($0)) }
                )

                // Hint untuk user supaya tahu ada search
                searchHint
                    .padding(.top, 8)
                    .padding(.bottom, 20)
            }
        }
        .background(Color.DarkPurpleAppBackground.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top) { topBar }
        .task {
            await portfolioVM.fetchData()
            await homeVM.loadStocks(holdings: portfolioVM.holdings)
            await homeVM.loadInsights()
        }
        .task { await notifVM.checkForAlerts() }
        .onAppear {
            configureSegmentedAppearance()
            homeVM.startPriceStream()
        }
        .onDisappear { homeVM.stopPriceStream() }
    }

    // MARK: - Sub-views

    private var topBar: some View {
        HStack {
            HStack(spacing: 0) {
                Image("logo_icon")
                    .renderingMode(.template)
                    .resizable().scaledToFit()
                    .foregroundColor(Color.PrimaryYellow)
                Image("logo_teks")
                    .renderingMode(.template)
                    .resizable().scaledToFit()
                    .foregroundColor(Color(UIColor.label))
            }
            .frame(height: 36)

            Spacer()

            HStack(spacing: 16) {
                // Tombol Search — arahkan ke tab Search
                Button {
                    router.selectedTab = "search"
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.title3)
                        .foregroundColor(.primary)
                }

                NotificationButton(unreadCount: notifVM.unreadCount) {
                    router.push(.notification)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.DarkPurpleAppBackground)
    }

    /// Banner kecil di bawah daftar watchlist yang mengajak user search lebih banyak saham.
    private var searchHint: some View {
        Button {
            router.selectedTab = "search"
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(Color.PrimaryYellow)
                Text("Cari saham NASDAQ, ETF, dan lebih banyak lagi")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundColor(.primary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.systemGray6).opacity(0.18))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal)
        }
        .buttonStyle(.plain)
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(Font.title2).fontWeight(.bold)
                .foregroundColor(.primary)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.bottom, 6)
    }

    private func configureSegmentedAppearance() {
        UISegmentedControl.appearance().selectedSegmentTintColor = UIColor(Color.PrimaryYellow)
        UISegmentedControl.appearance().setTitleTextAttributes([.foregroundColor: UIColor.black],           for: .selected)
        UISegmentedControl.appearance().setTitleTextAttributes([.foregroundColor: UIColor.secondaryLabel], for: .normal)
    }
}

// MARK: - NotificationButton

struct NotificationButton: View {
    let unreadCount: Int
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "bell.fill")
                    .font(Font.title3)
                    .foregroundColor(.primary)
                if unreadCount > 0 {
                    ZStack {
                        Circle().fill(Color.LossRed).frame(width: 16, height: 16)
                        Text(unreadCount > 9 ? "9+" : "\(unreadCount)")
                            .font(Font.caption2).foregroundColor(.SurfaceWhite)
                    }
                    .offset(x: 6, y: -6)
                }
            }
        }
    }
}

struct StockListView: View {
    let items: [PortfolioItem]
    let onTap: (PortfolioItem) -> Void
    var body: some View {
        if items.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "tray")
                    .font(.system(size: 28))
                    .foregroundColor(.secondary.opacity(0.5))
                Text("Belum ada saham di kategori ini.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        } else {
            LazyVStack(spacing: 0) {
                ForEach(items) { item in
                    VStack(spacing: 0) {
                        StockRowView(stock: item).padding(.horizontal, 16).padding(.vertical, 6)
                        Divider().padding(.horizontal, 16)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { onTap(item) }
                }
            }
        }
    }
}
