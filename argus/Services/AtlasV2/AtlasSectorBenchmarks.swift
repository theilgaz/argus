import Foundation

// MARK: - Atlas Sektör Benchmark Veritabanı
// Yahoo Finance sektör ETF'lerinden dinamik güncelleme, statik fallback.

actor AtlasSectorBenchmarks {
    static let shared = AtlasSectorBenchmarks()

    private var dynamicBenchmarks: [String: AtlasSectorBenchmark] = [:]
    private var lastRefresh: Date?
    private let refreshTTL: TimeInterval = 86400 // 24 saat

    private init() {}

    // MARK: - Sektör → ETF eşlemesi

    private let sectorETFMap: [String: String] = [
        "Technology": "XLK",
        "Financial Services": "XLF",
        "Healthcare": "XLV",
        "Consumer Cyclical": "XLY",
        "Consumer Defensive": "XLP",
        "Industrials": "XLI",
        "Energy": "XLE",
        "Basic Materials": "XLB",
        "Communication Services": "XLC",
        "Utilities": "XLU",
        "Real Estate": "XLRE"
    ]

    // MARK: - Statik fallback (Yahoo Finance'ten çekilemezse)

    private let staticBenchmarks: [String: AtlasSectorBenchmark] = [
        "Technology": AtlasSectorBenchmark(sector: "Technology", avgPE: 32.0, avgPB: 8.5, avgROE: 25.0, avgNetMargin: 18.0, avgDebtToEquity: 0.6, avgDividendYield: 0.8),
        "Financial Services": AtlasSectorBenchmark(sector: "Financial Services", avgPE: 12.0, avgPB: 1.4, avgROE: 12.0, avgNetMargin: 25.0, avgDebtToEquity: 2.5, avgDividendYield: 2.8),
        "Healthcare": AtlasSectorBenchmark(sector: "Healthcare", avgPE: 22.0, avgPB: 4.5, avgROE: 18.0, avgNetMargin: 12.0, avgDebtToEquity: 0.8, avgDividendYield: 1.5),
        "Consumer Cyclical": AtlasSectorBenchmark(sector: "Consumer Cyclical", avgPE: 20.0, avgPB: 5.0, avgROE: 20.0, avgNetMargin: 8.0, avgDebtToEquity: 1.0, avgDividendYield: 1.2),
        "Consumer Defensive": AtlasSectorBenchmark(sector: "Consumer Defensive", avgPE: 22.0, avgPB: 5.5, avgROE: 25.0, avgNetMargin: 10.0, avgDebtToEquity: 1.2, avgDividendYield: 2.5),
        "Industrials": AtlasSectorBenchmark(sector: "Industrials", avgPE: 20.0, avgPB: 4.0, avgROE: 15.0, avgNetMargin: 8.0, avgDebtToEquity: 1.0, avgDividendYield: 1.8),
        "Energy": AtlasSectorBenchmark(sector: "Energy", avgPE: 10.0, avgPB: 1.8, avgROE: 15.0, avgNetMargin: 10.0, avgDebtToEquity: 0.5, avgDividendYield: 4.0),
        "Basic Materials": AtlasSectorBenchmark(sector: "Basic Materials", avgPE: 12.0, avgPB: 2.0, avgROE: 12.0, avgNetMargin: 8.0, avgDebtToEquity: 0.6, avgDividendYield: 2.5),
        "Communication Services": AtlasSectorBenchmark(sector: "Communication Services", avgPE: 18.0, avgPB: 3.5, avgROE: 15.0, avgNetMargin: 15.0, avgDebtToEquity: 1.0, avgDividendYield: 1.0),
        "Utilities": AtlasSectorBenchmark(sector: "Utilities", avgPE: 18.0, avgPB: 2.0, avgROE: 10.0, avgNetMargin: 12.0, avgDebtToEquity: 1.5, avgDividendYield: 3.5),
        "Real Estate": AtlasSectorBenchmark(sector: "Real Estate", avgPE: 35.0, avgPB: 2.5, avgROE: 8.0, avgNetMargin: 20.0, avgDebtToEquity: 1.2, avgDividendYield: 4.0)
    ]

    private let defaultBenchmark = AtlasSectorBenchmark(
        sector: "Market Average",
        avgPE: 20.0, avgPB: 3.5, avgROE: 15.0,
        avgNetMargin: 10.0, avgDebtToEquity: 0.8, avgDividendYield: 2.0
    )

    // MARK: - Dinamik güncelleme

    func refreshIfNeeded() async {
        if let last = lastRefresh, Date().timeIntervalSince(last) < refreshTTL { return }

        for (sector, etfSymbol) in sectorETFMap {
            guard let fallback = staticBenchmarks[sector] else { continue }
            do {
                let data = try await HeimdallOrchestrator.shared.requestFundamentals(symbol: etfSymbol)
                dynamicBenchmarks[sector] = AtlasSectorBenchmark(
                    sector: sector,
                    avgPE: data.peRatio ?? fallback.avgPE,
                    avgPB: data.priceToBook ?? fallback.avgPB,
                    avgROE: data.returnOnEquity.map { $0 * 100 } ?? fallback.avgROE,
                    avgNetMargin: data.profitMargin.map { $0 * 100 } ?? fallback.avgNetMargin,
                    avgDebtToEquity: data.debtToEquity.map { $0 / 100 } ?? fallback.avgDebtToEquity,
                    avgDividendYield: data.dividendYield.map { $0 * 100 } ?? fallback.avgDividendYield
                )
            } catch {
                ArgusLogger.warning(.atlas, "Sektör ETF \(etfSymbol) benchmark güncellenemedi: \(error.localizedDescription)")
            }
        }

        lastRefresh = Date()
        let dynamicCount = dynamicBenchmarks.count
        ArgusLogger.info(.atlas, "Sektör benchmark güncellendi: \(dynamicCount)/\(sectorETFMap.count) dinamik")
    }

    // MARK: - Public API

    func getBenchmark(for sector: String?) -> AtlasSectorBenchmark {
        guard let sector = sector else { return defaultBenchmark }

        if let dynamic = dynamicBenchmarks[sector] { return dynamic }
        if let static_ = staticBenchmarks[sector] { return static_ }

        for (key, value) in dynamicBenchmarks {
            if sector.contains(key) || key.contains(sector) { return value }
        }
        for (key, value) in staticBenchmarks {
            if sector.contains(key) || key.contains(sector) { return value }
        }

        return defaultBenchmark
    }

    func getSectorAveragePE(for sector: String?) -> Double {
        getBenchmark(for: sector).avgPE
    }

    func getSectorAveragePB(for sector: String?) -> Double {
        getBenchmark(for: sector).avgPB
    }

    func getSectorAverageROE(for sector: String?) -> Double {
        getBenchmark(for: sector).avgROE
    }
}
