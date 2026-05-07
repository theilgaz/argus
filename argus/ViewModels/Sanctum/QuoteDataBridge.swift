import Foundation
import Combine
import SwiftUI

/// SanctumViewModel'in piyasa verisi (quote + candle + timeframe) sorumluluğu.
/// MarketDataStore SSoT'una abone olur, candle yüklemesini yönetir.
@MainActor
final class QuoteDataBridge: ObservableObject {
    let symbol: String

    @Published var selectedTimeframe: TimeframeMode = .daily
    @Published var quote: Quote?
    @Published var candles: [Candle] = []
    @Published var isCandlesLoading: Bool = false

    private var cancellables = Set<AnyCancellable>()
    private let marketStore = MarketDataStore.shared

    init(symbol: String) {
        self.symbol = symbol
        setupBindings()
    }

    private func setupBindings() {
        marketStore.$quotes
            .map { $0[self.symbol]?.value }
            .receive(on: RunLoop.main)
            .assign(to: \.quote, on: self)
            .store(in: &cancellables)
    }

    /// Initial quote + candle fetch — paralel.
    /// Quote ve candle bağımsız network çağrıları; sequential bekleme yerine
    /// async-let ile aynı anda başlat.
    func ensureQuote() async {
        async let quoteJob: () = { [marketStore, symbol] in
            _ = await marketStore.ensureQuote(symbol: symbol)
        }()
        async let candleJob: () = loadCandles(for: selectedTimeframe)
        _ = await (quoteJob, candleJob)
    }

    /// Timeframe değişince hem state hem candle'ları günceller.
    /// Caller (AnalysisBridge) timeframe değişimi sonrası orionScore'u recompute etmeli.
    func changeTimeframe(to newTimeframe: TimeframeMode) async {
        guard newTimeframe != selectedTimeframe else { return }
        selectedTimeframe = newTimeframe
        await loadCandles(for: newTimeframe)
    }

    /// Belirli bir timeframe için candle yükler (public — AnalysisBridge.resolveCouncilCandles kullanabilir).
    func loadCandles(for timeframe: TimeframeMode) async {
        isCandlesLoading = true
        defer { isCandlesLoading = false }

        let apiTimeframe = timeframe.apiString
        if let candleData = await marketStore.ensureCandles(symbol: symbol, timeframe: apiTimeframe).value {
            self.candles = candleData
            print("✅ QuoteDataBridge: \(symbol) candles loaded for \(apiTimeframe) - \(candleData.count) bars")
        } else {
            print("⚠️ QuoteDataBridge: \(symbol) candles fetch failed for \(apiTimeframe)")
        }
    }

    /// Council fallback: birden fazla timeframe dener, ≥30 bar bulduğunda döner.
    func ensureCouncilCandles(minimumBars: Int = 30) async -> [Candle] {
        if candles.count >= minimumBars {
            return candles
        }

        var candidates: [String] = [selectedTimeframe.apiString, "1day", "1d", "1G"]
        var seen = Set<String>()
        candidates = candidates.filter { seen.insert($0).inserted }

        for timeframe in candidates {
            let data = await marketStore.ensureCandles(symbol: symbol, timeframe: timeframe).value ?? []
            guard data.count >= minimumBars else { continue }
            if candles != data {
                candles = data
            }
            return data
        }

        return candles
    }
}
