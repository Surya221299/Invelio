////
////  MainTabView.swift
////  StockAppTryNew
////
////  Created by Surya on 16/06/26.
////
//
//import SwiftUI
//
//struct MainTabView: View {
//
//    @EnvironmentObject private var router: Router
//
//    var body: some View {
//        TabView(selection: $router.selectedTab) {
//            Tab("Home",
//                systemImage: router.selectedTab == "home" ? "chart.bar.fill" : "chart.bar",
//                value: "home") {
//                HomeNavigationView()
//            }
//            Tab("Portfolio",
//                systemImage: "briefcase.fill",
//                value: "portfolio") {
//                PortfolioNavigationView()
//            }
//            Tab("Chatbot",
//                systemImage: "sparkles.square.filled.on.square",
//                value: "chatbot") {
//                ChatbotView()
//            }
//        }
//        .tint(Color.PrimaryYellow)
//    }
//}
//
//// MARK: - Navigation Hosts
//
//struct HomeNavigationView: View {
//    @EnvironmentObject private var router: Router
//    var body: some View {
//        NavigationStack(path: $router.path) {
//            HomeView()
//                .navigationDestination(for: Route.self) { destinationView(for: $0) }
//        }
//    }
//}
//
//struct PortfolioNavigationView: View {
//    @EnvironmentObject private var router: Router
//    var body: some View {
//        NavigationStack(path: $router.path) {
//            PortfolioView()
//                .navigationDestination(for: Route.self) { destinationView(for: $0) }
//        }
//    }
//}
//
//// MARK: - Shared destination factory
//
//@ViewBuilder
//private func destinationView(for route: Route) -> some View {
//    switch route {
//    case .stockDetail(let item):
//        StockDetailView(
//            viewModel: DIContainer.shared.makeStockDetailViewModel(item: item)
//        )
//        .toolbar(.hidden, for: .tabBar)
//
//    case .portfolioDetail(let item):
//        DetailPortfolioPerEmitentView(item: item)
//            .toolbar(.hidden, for: .tabBar)
//
//    case .notification:
//        NotificationView()
//            .toolbar(.hidden, for: .tabBar)
//    }
//}
