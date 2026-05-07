import Foundation
import Combine

// MARK: - Data Health Report (Inline)
enum DataHealthStatus: String {
    case healthy = "Healthy"
    case degraded = "Degraded"
    case unhealthy = "Unhealthy"
}

struct DataHealthReport {
    var timestamp: Date
    var overallStatus: DataHealthStatus
    var apiLatency: Double
    var dataFreshness: Double
    var activeProvider: String
    var errors: [String]
}

/// "The Hydra" - Legacy Provider Manager
/// Yahoo Direct Mode aktif: TwelveData streaming kaldırıldı.
/// Fetch logic MarketDataStore (SSoT) ve HeimdallOrchestrator'da.
class MarketDataProvider: ObservableObject {
    static let shared = MarketDataProvider()

    // MARK: - Streaming Publisher
    // Legacy publisher -- callers should migrate to MarketDataStore observation.
    let priceUpdate = PassthroughSubject<Quote, Never>()
    private var cancellables = Set<AnyCancellable>()

    // MARK: - State
    @Published var dataHealth = DataHealthReport(
        timestamp: Date(),
        overallStatus: .healthy,
        apiLatency: 0,
        dataFreshness: 0,
        activeProvider: "Yahoo",
        errors: []
    )

    private init() {}

    // MARK: - Streaming (no-op, TwelveData removed)

    func injectLiveQuote(_ quote: Quote, source: String) {
        guard let ts = quote.timestamp, Date().timeIntervalSince(ts) <= 15 else {
            return
        }
        DispatchQueue.main.async {
            self.priceUpdate.send(quote)
            self.dataHealth.activeProvider = source
            self.dataHealth.dataFreshness = 0
            Task { @MainActor in
                MarketDataStore.shared.injectLiveQuote(quote, source: source)
            }
        }
    }

    func connectStream(symbols: [String]) {
        // no-op: TwelveData WebSocket streaming removed (Yahoo Direct Mode)
    }
    
    // MARK: - DEPRECATED / REMOVED METHODS
    // These methods have been moved to MarketDataStore or HeimdallOrchestrator to ensure SSoT.
    // Leaving Stubs/Deprecations if needed, but for "Senior Architect" refactor we clean them up.
    // If strict compilation is required, we might need these to prevent build errors until ViewModel is fixed.
    // I will REMOVE them and fix the errors in ViewModel.
    
    // MARK: - Yahoo Search Implementation
    private struct YahooSearchResponse: Codable {
        let quotes: [YahooSearchResult]
    }
    private struct YahooSearchResult: Codable {
        let symbol: String
        let shortname: String?
        let longname: String?
        let typeDisp: String?
        let exchange: String?
    }

    func searchSymbols(query: String) async throws -> [SearchResult] {
        let urlString = "https://query1.finance.yahoo.com/v1/finance/search?q=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        guard let url = URL(string: urlString) else { return [] }

        // Y2: timeout + explicit status guard. Yahoo rate-limit durumunda 429/401
        // dönüp boş JSON gönderebiliyor; decode başarılı ama liste boş görünüyor ve
        // kullanıcı "arama bozuk" mu, "sonuç yok" mu ayırt edemiyordu.
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw URLError(.badServerResponse, userInfo: [
                NSLocalizedDescriptionKey: "Yahoo search HTTP \(code)"
            ])
        }

        let decoded = try JSONDecoder().decode(YahooSearchResponse.self, from: data)

        return decoded.quotes.map { q in
            SearchResult(
                symbol: q.symbol,
                description: q.longname ?? q.shortname ?? q.symbol
            )
        }
    }
    
    // Helper to evaluate health (Pure Logic)
    func evaluateDataHealth(symbol: String) async -> DataHealth {
        var h = DataHealth(symbol: symbol)
        h.technical = CoverageComponent.present(quality: 0.5)
        return h
    }
}
