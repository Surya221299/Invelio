//
//  ReleaseViewModel.swift
//  SahamIndo
//
//  ViewModel untuk tab "Release" — menampilkan probabilitas CME FedWatch
//  (target range suku bunga Fed pada rapat FOMC berikutnya).
//

import SwiftUI
import Combine

@MainActor
final class ReleaseViewModel: ObservableObject {

    @Published private(set) var fedWatch: FedWatchSnapshot = .placeholder
    @Published private(set) var isLoading: Bool = false

    private let fedWatchRepository: FedWatchRepositoryProtocol

    init(fedWatchRepository: FedWatchRepositoryProtocol) {
        self.fedWatchRepository = fedWatchRepository
    }

    func load() async {
        isLoading = true
        fedWatch = await fedWatchRepository.fetchSnapshot()
        isLoading = false
    }
}
