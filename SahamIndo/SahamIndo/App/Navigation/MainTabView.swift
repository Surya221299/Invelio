//
//  MainTabView.swift
//  SahamIndo
//
//  Ditambah tab "Search" untuk mencari saham di luar watchlist
//  (NASDAQ/ETF/IDX) dan menjalankan Analyze on-demand.
//

import SwiftUI

struct MainTabView: View {

    @EnvironmentObject private var router: Router

    var body: some View {
        TabView(selection: $router.selectedTab) {
            Tab("Home",
                systemImage: router.selectedTab == "home" ? "chart.bar.fill" : "chart.bar",
                value: "home") {
                HomeNavigationView()
            }
            Tab("Portfolio",
                systemImage: "briefcase.fill",
                value: "portfolio") {
                PortfolioNavigationView()
            }
            /// Tab baru: Search universe NASDAQ/ETF/IDX + Analyze on-demand
            Tab("Search",
                systemImage: router.selectedTab == "search" ? "magnifyingglass.circle.fill" : "magnifyingglass.circle",
                value: "search") {
                SearchNavigationView()
            }
            /// Tab baru: Release — probabilitas CME FedWatch (suku bunga Fed)
            Tab("Release",
                systemImage: router.selectedTab == "release" ? "calendar.badge.clock" : "calendar",
                value: "release") {
                ReleaseView()
            }
            Tab("Chatbot",
                systemImage: "sparkles.square.filled.on.square",
                value: "chatbot") {
                ChatbotView()
            }
        }
        .tint(Color.PrimaryYellow)
    }
}

// MARK: - Navigation Hosts

struct HomeNavigationView: View {
    @EnvironmentObject private var router: Router
    var body: some View {
        NavigationStack(path: $router.path) {
            HomeView()
                .navigationDestination(for: Route.self) { destinationView(for: $0) }
        }
    }
}

struct PortfolioNavigationView: View {
    @EnvironmentObject private var router: Router
    var body: some View {
        NavigationStack(path: $router.path) {
            PortfolioView()
                .navigationDestination(for: Route.self) { destinationView(for: $0) }
        }
    }
}

struct SearchNavigationView: View {
    @EnvironmentObject private var router: Router
    var body: some View {
        NavigationStack(path: $router.path) {
            SearchView(vm: DIContainer.shared.makeSearchViewModel())
                .navigationDestination(for: Route.self) { destinationView(for: $0) }
        }
    }
}

// MARK: - Shared destination factory

@ViewBuilder
private func destinationView(for route: Route) -> some View {
    switch route {
    case .stockDetail(let item):
        StockDetailView(
            viewModel: DIContainer.shared.makeStockDetailViewModel(item: item)
        )
        .toolbar(.hidden, for: .tabBar)

    case .portfolioDetail(let item):
        DetailPortfolioPerEmitentView(item: item)
            .toolbar(.hidden, for: .tabBar)

    case .notification:
        NotificationView()
            .toolbar(.hidden, for: .tabBar)

    case .search:
        // Bisa juga dipakai lewat router.push(.search) dari HomeView
        SearchView(vm: DIContainer.shared.makeSearchViewModel())
            .toolbar(.hidden, for: .tabBar)
    }
}
