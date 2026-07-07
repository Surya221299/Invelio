//
//  StockAppTryNewApp.swift
//  StockAppTryNew
//
//  Created by Surya on 16/06/26.
//

import SwiftUI

@main
struct StockAppTryNewApp: App {
    private let di = DIContainer.shared
     
        @StateObject private var router = Router()
        @StateObject private var portfolioVM: PortfolioViewModel
        @StateObject private var homeVM: HomeViewModel
        @StateObject private var chatVM: ChatViewModel
        @StateObject private var notifVM: NotificationViewModel
     
        init() {
            // Initialise ViewModels via DI container
            _portfolioVM = StateObject(wrappedValue: DIContainer.shared.makePortfolioViewModel())
            _homeVM      = StateObject(wrappedValue: DIContainer.shared.makeHomeViewModel())
            _chatVM      = StateObject(wrappedValue: DIContainer.shared.makeChatViewModel())
            _notifVM     = StateObject(wrappedValue: DIContainer.shared.makeNotificationViewModel())
        }
     
        var body: some Scene {
            WindowGroup {
                MainTabView()
                    .environmentObject(router)
                    .environmentObject(portfolioVM)
                    .environmentObject(homeVM)
                    .environmentObject(chatVM)
                    .environmentObject(notifVM)
            }
        }
}
