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
    @Published private(set) var macroCalendar: MacroCalendar = .placeholder
    @Published private(set) var isLoading: Bool = false

    private let fedWatchRepository: FedWatchRepositoryProtocol
    private let macroCalendarRepository: MacroCalendarRepositoryProtocol

    init(fedWatchRepository: FedWatchRepositoryProtocol,
         macroCalendarRepository: MacroCalendarRepositoryProtocol) {
        self.fedWatchRepository = fedWatchRepository
        self.macroCalendarRepository = macroCalendarRepository
    }

    func load() async {
        isLoading = true
        // Muat FedWatch & kalender makro paralel — keduanya independen.
        async let fw = fedWatchRepository.fetchSnapshot()
        async let cal = macroCalendarRepository.fetchCalendar()
        fedWatch = await fw
        macroCalendar = await cal
        isLoading = false
    }
}
