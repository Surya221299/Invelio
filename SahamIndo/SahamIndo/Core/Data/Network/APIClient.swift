//
//  APIClient.swift
//  SahamIndo
//

import Foundation

// MARK: - APIEndpoint

enum APIEndpoint {
    case status
    case allStocks
    case stock(symbol: String)
    case candles(symbol: String, range: String)
    case stockDetail(symbol: String)
    case alerts
    case macroLatest
    case weeklyRecommendations
    case insight(type: InsightType)
    case chat

    // --- BARU: Multi-market search & analyze ---
    /// Search universe simbol_referensi (ringan, ribuan NASDAQ+ETF+IDX)
    case searchSymbols(query: String, limit: Int)
    /// Analisis AI on-demand untuk satu saham (tidak otomatis masuk watchlist)
    case analyzeSaham(kode: String, market: String? = nil, nama: String? = nil)
    /// Tambah saham ke watchlist aktif scheduler
    case addWatchlist(kode: String)
    /// Hapus saham dari watchlist
    case removeWatchlist(kode: String)
    /// Perkiraan jadwal rilis laporan keuangan (earnings) per emiten
    case earnings(symbol: String)
    /// Rally streak (hari hijau berturut-turut) per emiten
    case rallyStreak(symbol: String)
    /// Analisis kesehatan portofolio + narasi harian (POST body holdings)
    case analyzePortfolio

    enum InsightType: String {
        case sentimentNews  = "sentimen-berita"
        case foreignFlow    = "asing-net-buy"
        case macro          = "makro-idr"
    }

    var path: String {
        switch self {
        case .status:                          return "/api/status"
        case .allStocks:                       return "/stocks"
        case .stock(let s):                    return "/stocks/\(s)"
        case .candles(let s, let r):           return "/stocks/\(s)/candles?range=\(r)"
        case .stockDetail(let s):              return "/rekomendasi/saham/\(s)"
        case .alerts:                          return "/api/alerts"
        case .macroLatest:                     return "/makro/terbaru"
        case .weeklyRecommendations:           return "/rekomendasi/mingguan"
        case .insight(let t):                  return "/ai/insights/\(t.rawValue)"
        case .chat:                            return "/chat"
        case .searchSymbols(let q, let lim):
            let encoded = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q
            return "/api/saham/search?q=\(encoded)&limit=\(lim)"
        case .analyzeSaham(let kode, let market, let nama):
            var path = "/api/saham/\(kode)/analyze"
            var query: [String] = []
            if let market, let encoded = market.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                query.append("market=\(encoded)")
            }
            if let nama, let encoded = nama.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                query.append("nama=\(encoded)")
            }
            if !query.isEmpty { path += "?" + query.joined(separator: "&") }
            return path
        case .addWatchlist(let kode):          return "/api/saham/\(kode)/watchlist"
        case .removeWatchlist(let kode):       return "/api/saham/\(kode)/watchlist"
        case .earnings(let s):                 return "/saham/\(s)/earnings"
        case .rallyStreak(let s):              return "/saham/\(s)/rally-streak"
        case .analyzePortfolio:                return "/portfolio/analyze"
        }
    }

    // HTTP method — default GET, beberapa endpoint POST/DELETE
    var method: String {
        switch self {
        case .analyzeSaham, .addWatchlist: return "POST"
        case .removeWatchlist:             return "DELETE"
        case .chat:                        return "POST"
        case .analyzePortfolio:            return "POST"
        default:                           return "GET"
        }
    }
}

// MARK: - APIError

enum APIError: Error, LocalizedError {
    case invalidURL
    case httpError(Int)
    case decodingError(Error)
    case noBaseURL

    var errorDescription: String? {
        switch self {
        case .invalidURL:           return "URL tidak valid"
        case .httpError(let code):  return "HTTP error: \(code)"
        case .decodingError(let e): return "Decode error: \(e.localizedDescription)"
        case .noBaseURL:            return "Server tidak dapat ditemukan"
        }
    }
}

// MARK: - APIClient

/// Pure networking layer. No business logic.
final class APIClient {

    // MARK: - Base URL Resolution

    private static var resolvedBaseURL: String?

    private static let candidateURLs = [
        "http://100.121.215.111:8080",
        "http://100.118.29.16:8080",
        "http://100.70.203.11:8080",
    ]
    private static let fallbackURL = "http://10.67.50.109:8080"

    static func resolveBaseURL() async -> String {
        if let cached = resolvedBaseURL { return cached }

        let resolved = await withTaskGroup(of: String?.self, returning: String?.self) { group in
            for candidate in candidateURLs {
                group.addTask {
                    guard let url = URL(string: "\(candidate)/api/status") else { return nil }
                    var request = URLRequest(url: url)
                    request.timeoutInterval = 1.0
                    do {
                        let (_, response) = try await URLSession.shared.data(for: request)
                        if let http = response as? HTTPURLResponse,
                           (200...299).contains(http.statusCode) { return candidate }
                    } catch {}
                    return nil
                }
            }
            for await res in group {
                if let url = res { group.cancelAll(); return url }
            }
            return nil
        }

        let finalURL = resolved ?? fallbackURL
        resolvedBaseURL = finalURL
        print("[APIClient] Base URL: \(finalURL)")
        return finalURL
    }

    // MARK: - Decoder

    static var decoder: JSONDecoder {
        let d = JSONDecoder()
        let isoFrac  = ISO8601DateFormatter()
        isoFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoPlain = ISO8601DateFormatter()
        isoPlain.formatOptions = [.withInternetDateTime]
        let dfJKT = DateFormatter()
        dfJKT.locale     = Locale(identifier: "en_US_POSIX")
        dfJKT.timeZone   = TimeZone(identifier: "Asia/Jakarta")
        dfJKT.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        let dfJKTFrac = DateFormatter()
        dfJKTFrac.locale     = Locale(identifier: "en_US_POSIX")
        dfJKTFrac.timeZone   = TimeZone(identifier: "Asia/Jakarta")
        dfJKTFrac.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"

        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let str       = try container.decode(String.self)
            if let date = isoFrac.date(from: str)   { return date }
            if let date = isoPlain.date(from: str)  { return date }
            if let date = dfJKTFrac.date(from: str) { return date }
            if let date = dfJKT.date(from: str)     { return date }
            throw DecodingError.dataCorruptedError(in: container,
                debugDescription: "Cannot parse date: \(str)")
        }
        return d
    }

    // MARK: - GET

    static func get<T: Decodable>(_ endpoint: APIEndpoint, as type: T.Type) async throws -> T {
        let base = await resolveBaseURL()
        guard let url = URL(string: base + endpoint.path) else { throw APIError.invalidURL }
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw APIError.httpError(http.statusCode)
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch let err {
            if let raw = String(data: data, encoding: .utf8) {
                print("[APIClient] Raw (300): \(raw.prefix(300))")
            }
            throw APIError.decodingError(err)
        }
    }

    // MARK: - POST / DELETE (tanpa body, response JSON)

    static func request<T: Decodable>(_ endpoint: APIEndpoint, as type: T.Type) async throws -> T {
        let base = await resolveBaseURL()
        guard let url = URL(string: base + endpoint.path) else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = endpoint.method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 300  // analyze on-demand bisa butuh waktu (LLM lokal)
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw APIError.httpError(http.statusCode)
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch let err {
            if let raw = String(data: data, encoding: .utf8) {
                print("[APIClient] Raw (300): \(raw.prefix(300))")
            }
            throw APIError.decodingError(err)
        }
    }

    // MARK: - POST dengan JSON body (response JSON)

    static func post<T: Decodable, B: Encodable>(_ endpoint: APIEndpoint, body: B, as type: T.Type) async throws -> T {
        let base = await resolveBaseURL()
        guard let url = URL(string: base + endpoint.path) else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = endpoint.method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 300  // analisis portofolio memanggil LLM lokal
        req.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw APIError.httpError(http.statusCode)
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch let err {
            if let raw = String(data: data, encoding: .utf8) {
                print("[APIClient] Raw (300): \(raw.prefix(300))")
            }
            throw APIError.decodingError(err)
        }
    }

    // MARK: - Streaming POST (chat)

    static func streamChat(question: String, history: [ChatHistoryItem]) async throws -> AsyncThrowingStream<String, Error> {
        let base = await resolveBaseURL()
        guard let url = URL(string: base + APIEndpoint.chat.path) else { throw APIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 240

        let payload = ChatPayload(pertanyaan: question, riwayat: history)
        request.httpBody = try JSONEncoder().encode(payload)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIError.httpError((response as? HTTPURLResponse)?.statusCode ?? 500)
        }

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    var buffer = Data()
                    var iterator = bytes.makeAsyncIterator()
                    while let byte = try await iterator.next() {
                        buffer.append(byte)
                        if let str = String(data: buffer, encoding: .utf8) {
                            continuation.yield(str)
                            buffer.removeAll()
                        }
                    }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
        }
    }
}

// MARK: - Payload (needed by APIClient)

struct ChatPayload: Codable {
    let pertanyaan: String
    let riwayat: [ChatHistoryItem]
}
