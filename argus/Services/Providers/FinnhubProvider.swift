import Foundation

final class FinnhubProvider: HeimdallProvider, @unchecked Sendable {
    static let shared = FinnhubProvider()

    nonisolated var name: String { "Finnhub" }
    nonisolated var capabilities: [HeimdallDataField] { [.quote, .candles, .profile] }

    private let baseURL = "https://finnhub.io/api/v1"

    private var apiKey: String? {
        APIKeyStore.shared.getKey(for: .finnhub)
    }

    // MARK: - Quote

    func fetchQuote(symbol: String) async throws -> Quote {
        guard let key = apiKey, !key.isEmpty else {
            throw URLError(.userAuthenticationRequired)
        }

        let urlStr = "\(baseURL)/quote?symbol=\(symbol)&token=\(key)"
        guard let url = URL(string: urlStr) else { throw URLError(.badURL) }

        let data = try await HeimdallNetwork.request(
            url: url, engine: .orion, provider: .finnhub, symbol: symbol
        )

        let raw = try JSONDecoder().decode(FinnhubQuoteResponse.self, from: data)
        guard raw.c > 0 else { throw URLError(.cannotParseResponse) }

        return Quote(
            c: raw.c,
            d: raw.d,
            dp: raw.dp,
            currency: "USD",
            shortName: nil,
            symbol: symbol,
            previousClose: raw.pc,
            volume: raw.v > 0 ? Double(raw.v) : nil
        )
    }

    // MARK: - Candles

    func fetchCandles(symbol: String, timeframe: String, limit: Int) async throws -> [Candle] {
        guard let key = apiKey, !key.isEmpty else {
            throw URLError(.userAuthenticationRequired)
        }

        let resolution = mapTimeframe(timeframe)
        let to = Int(Date().timeIntervalSince1970)
        let secondsPerBar = resolutionSeconds(resolution)
        let from = to - (limit * secondsPerBar)

        let urlStr = "\(baseURL)/stock/candle?symbol=\(symbol)&resolution=\(resolution)&from=\(from)&to=\(to)&token=\(key)"
        guard let url = URL(string: urlStr) else { throw URLError(.badURL) }

        let data = try await HeimdallNetwork.request(
            url: url, engine: .orion, provider: .finnhub, symbol: symbol
        )

        let raw = try JSONDecoder().decode(FinnhubCandleResponse.self, from: data)
        guard raw.s == "ok", !raw.c.isEmpty else {
            throw URLError(.cannotParseResponse)
        }

        let count = min(raw.c.count, raw.o.count, raw.h.count, raw.l.count, raw.v.count, raw.t.count)
        return (0..<count).map { i in
            Candle(
                date: Date(timeIntervalSince1970: raw.t[i]),
                open: raw.o[i],
                high: raw.h[i],
                low: raw.l[i],
                close: raw.c[i],
                volume: raw.v[i]
            )
        }
    }

    // MARK: - Profile

    func fetchProfile(symbol: String) async throws -> AssetProfile {
        guard let key = apiKey, !key.isEmpty else {
            throw URLError(.userAuthenticationRequired)
        }

        let urlStr = "\(baseURL)/stock/profile2?symbol=\(symbol)&token=\(key)"
        guard let url = URL(string: urlStr) else { throw URLError(.badURL) }

        let data = try await HeimdallNetwork.request(
            url: url, engine: .atlas, provider: .finnhub, symbol: symbol
        )

        let raw = try JSONDecoder().decode(FinnhubProfileResponse.self, from: data)
        return AssetProfile(
            symbol: symbol,
            name: raw.name ?? symbol,
            sector: raw.finnhubIndustry,
            industry: raw.finnhubIndustry,
            marketCap: raw.marketCapitalization.map { $0 * 1_000_000 },
            currency: raw.currency ?? "USD",
            isEtf: false,
            description: nil,
            domicile: raw.country
        )
    }

    // MARK: - Helpers

    private func mapTimeframe(_ tf: String) -> String {
        switch tf.lowercased() {
        case "1", "1m": return "1"
        case "5", "5m": return "5"
        case "15", "15m": return "15"
        case "30", "30m": return "30"
        case "60", "1h": return "60"
        case "d", "1d", "daily": return "D"
        case "w", "1w", "weekly": return "W"
        case "m", "1mo", "monthly": return "M"
        default: return "D"
        }
    }

    private func resolutionSeconds(_ r: String) -> Int {
        switch r {
        case "1": return 60
        case "5": return 300
        case "15": return 900
        case "30": return 1800
        case "60": return 3600
        case "D": return 86400
        case "W": return 604800
        case "M": return 2592000
        default: return 86400
        }
    }
}

// MARK: - Response Models (FinnhubCandleResponse APIService.swift'te tanımlı)

private struct FinnhubQuoteResponse: Decodable {
    let c: Double
    let d: Double?
    let dp: Double?
    let h: Double?
    let l: Double?
    let o: Double?
    let pc: Double?
    let t: Int?
    let v: Int
}

private struct FinnhubProfileResponse: Decodable {
    let country: String?
    let currency: String?
    let finnhubIndustry: String?
    let name: String?
    let ticker: String?
    let marketCapitalization: Double?
}
