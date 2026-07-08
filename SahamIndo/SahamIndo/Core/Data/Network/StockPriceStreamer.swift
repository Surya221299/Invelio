//
//  StockPriceStreamer.swift
//  SahamIndo
//
//  WebSocket client untuk streaming harga saham near-real-time dari backend
//  (/ws/stocks/{symbol}). Reuse APIClient.resolveBaseURL() supaya base URL
//  (Tailscale/LAN candidates) tetap konsisten dengan request REST biasa.
//
//  CATATAN: sumber data backend saat ini adalah yfinance, jadi update yang
//  diterima di sini bukan tick-per-detik asli — granularitas & delay-nya
//  mengikuti keterbatasan yfinance. Yang "real-time" di sisi UI adalah
//  push otomatis-nya (tanpa perlu refresh manual), bukan kecepatan datanya.
//

import Foundation
import Combine

struct StockPriceUpdate: Decodable {
    let symbol:     String
    let price:      Double
    let change:     Double
    let pctChange:  Double
    let ts:         Double

    enum CodingKeys: String, CodingKey {
        case symbol, price, change, ts
        case pctChange = "pct_change"
    }
}

@MainActor
final class StockPriceStreamer: ObservableObject {

    @Published private(set) var latest: StockPriceUpdate?
    @Published private(set) var isConnected: Bool = false

    private var task: URLSessionWebSocketTask?
    private var symbol: String = ""
    private var shouldReconnect = false

    /// Mulai streaming harga untuk satu simbol. Aman dipanggil berkali-kali
    /// (misal dari .task SwiftUI) — akan no-op kalau simbol yang sama sudah connect.
    func connect(symbol: String, market: String = "IDX") {
        let symbolUpper = symbol.uppercased()
        if self.symbol == symbolUpper, task != nil { return }

        disconnect()
        self.symbol = symbolUpper
        shouldReconnect = true

        Task {
            let base = await APIClient.resolveBaseURL()
            let wsBase = base
                .replacingOccurrences(of: "https://", with: "wss://")
                .replacingOccurrences(of: "http://", with: "ws://")

            guard let url = URL(string: "\(wsBase)/ws/stocks/\(symbolUpper)?market=\(market)") else { return }

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
                       let update = try? JSONDecoder().decode(StockPriceUpdate.self, from: data),
                       update.price > 0 {
                        // Jaga-jaga: abaikan payload dengan harga 0/negatif (sentinel
                        // kegagalan fetch di backend) supaya tidak menimpa harga valid
                        // terakhir yang sudah ditampilkan.
                        self.latest = update
                    }
                    self.listen() // lanjut dengar pesan berikutnya
                case .failure:
                    self.isConnected = false
                    // Reconnect sederhana kalau koneksi putus tak disengaja
                    if self.shouldReconnect {
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        if self.shouldReconnect { self.connect(symbol: self.symbol) }
                    }
                }
            }
        }
    }
}
