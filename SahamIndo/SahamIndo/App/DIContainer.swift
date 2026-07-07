//
//  DIContainer.swift
//  SahamIndo
//
//  Ditambah SearchRepository dan makeSearchViewModel().
//

import Foundation

final class DIContainer {

    static let shared = DIContainer()
    private init() {}

    // MARK: - Repositories (lazy, singletons)

    lazy var stockRepository: StockRepositoryProtocol         = StockRepository()
    lazy var detailRepository: StockDetailRepositoryProtocol  = StockDetailRepository()
    lazy var chartRepository: ChartRepositoryProtocol         = ChartRepository()
    lazy var insightRepository: InsightRepositoryProtocol     = InsightRepository()
    lazy var chatRepository: ChatRepositoryProtocol           = ChatRepository()
    lazy var alertRepository: AlertRepositoryProtocol         = AlertRepository()
    lazy var portfolioRepository: PortfolioRepositoryProtocol = UserDefaultsPortfolioRepository()

    /// Repository untuk search universe simbol + analyze on-demand.
    /// Lazy singleton — tidak butuh lebih dari satu instance.
    lazy var searchRepository: SearchRepositoryProtocol       = SearchRepository()

    // MARK: - Use Cases

    func makeFetchStocksUseCase() -> FetchStocksUseCase {
        FetchStocksUseCase(stockRepo: stockRepository, detailRepo: detailRepository)
    }

    func makeFetchChartDataUseCase() -> FetchChartDataUseCase {
        FetchChartDataUseCase(repo: chartRepository)
    }

    func makeBuyUseCase()  -> BuyStockUseCase  { BuyStockUseCase() }
    func makeSellUseCase() -> SellStockUseCase { SellStockUseCase() }

    // MARK: - ViewModels

    func makeHomeViewModel() -> HomeViewModel {
        HomeViewModel(
            fetchStocksUseCase: makeFetchStocksUseCase(),
            insightRepository:  insightRepository,
            chartRepository:    chartRepository
        )
    }

    func makePortfolioViewModel() -> PortfolioViewModel {
        PortfolioViewModel(
            fetchStocksUseCase:  makeFetchStocksUseCase(),
            buyUseCase:          makeBuyUseCase(),
            sellUseCase:         makeSellUseCase(),
            portfolioRepository: portfolioRepository,
            fetchChartUseCase:   makeFetchChartDataUseCase()
        )
    }

    func makeStockDetailViewModel(item: PortfolioItem) -> StockDetailViewModel {
        StockDetailViewModel(
            item:              item,
            fetchChartUseCase: makeFetchChartDataUseCase(),
            detailRepository:  detailRepository
        )
    }

    func makeChatViewModel() -> ChatViewModel {
        ChatViewModel(chatRepository: chatRepository)
    }

    func makeNotificationViewModel() -> NotificationViewModel {
        NotificationViewModel(
            detailRepository: detailRepository,
            alertRepository:  alertRepository
        )
    }

    /// Setiap SearchView punya ViewModel baru (tidak singleton) supaya
    /// state query/results selalu bersih saat tab di-tap dari awal.
    func makeSearchViewModel() -> SearchViewModel {
        SearchViewModel(repo: searchRepository)
    }
}
