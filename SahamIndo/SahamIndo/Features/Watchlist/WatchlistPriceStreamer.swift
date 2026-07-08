//
//  WatchlistPriceStreamer.swift
//  SahamIndo
//
//  WebSocket client untuk streaming harga SELURUH saham watchlist sekaligus
//  (dipakai halaman Home/List saham), dari endpoint backend /ws/stocks.
//
//  Beda dengan StockPriceStreamer (1 simbol per koneksi, dipakai
//  StockDetailView), streamer ini satu koneksi untuk semua baris di list —
//  supaya halaman Home tidak perlu buka puluhan koneksi WebSocket sekaligus.
//

import Foundation
import Combine

struct WatchlistPriceUpdate: Decodable {
    let symbol:     String
    let price:      Double
    let change:     Double
    let pctChange:  Double

    enum CodingKeys: String, CodingKey {
        case symbol, price, change
        case pctChange = "pct_change"
    }
}

private struct WatchlistUpdateMessage: Decodable {
    let type:    String
    let updates: [WatchlistPriceUpdate]
    let ts:      Double
}

@MainActor
final class WatchlistPriceStreamer: ObservableObject {

    /// Update terbaru per simbol — key = kode saham (mis. "BBCA").
    /// HomeViewModel observe ini dan menimpa harga di `stocks` saat berubah.
    @Published private(set) var latestBySymbol: [String: WatchlistPriceUpdate] = [:]
    @Published private(set) var isConnected: Bool = false

    private var task: URLSessionWebSocketTask?
    private var shouldReconnect = false

    func connect() {
        if task != nil { return } // sudah connect, no-op
        shouldReconnect = true

        Task {
            let base = await APIClient.resolveBaseURL()
            let wsBase = base
                .replacingOccurrences(of: "https://", with: "wss://")
                .replacingOccurrences(of: "http://", with: "ws://")

            guard let url = URL(string: "\(wsBase)/ws/stocks") else { return }

            let newTask = URLSession.shared.webSocketTask(with: url)
            self.task = newTask
            newTask.resume()
            self.isConnected = true
            self.listen()
        }
    }

    func disconnect() {
        shouldReconnect = false
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        isConnected = false
    }

    private func listen() {
        task?.receive { [weak self] result in
            guard let self else { return }
            Task { @MainActor in
                switch result {
                case .success(let message):
                    if case .string(let text) = message,
                       let data = text.data(using: .utf8),
                       let batch = try? JSONDecoder().decode(WatchlistUpdateMessage.self, from: data) {
                        for update in batch.updates where update.price > 0 {
                            // Jaga-jaga: abaikan harga 0/negatif (sentinel kegagalan
                            // fetch di backend), sama seperti StockPriceStreamer.
                            self.latestBySymbol[update.symbol] = update
                        }
                    }
                    self.listen()
                case .failure:
                    self.isConnected = false
                    if self.shouldReconnect {
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        if self.shouldReconnect { self.connect() }
                    }
                }
            }
        }
    }
}
