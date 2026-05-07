import Foundation
import Combine
import SwiftUI

// MARK: - Sanctum View Model (Facade)
/// "Sanctum" (Hisse Detay) ekranı için hafif sıklet facade.
/// Üç bridge'i orkestre eder: QuoteData, Analysis, News.
///
/// Backward compat: View'lar `vm.quote`, `vm.orionAnalysis`, `vm.newsInsights` gibi
/// eski API'ı kullanmaya devam edebilir — computed property'ler bridge'e delege eder.
/// Yeni view'lar bridge'i doğrudan observe edebilir (`vm.quoteBridge`).
///
/// L61 (lessons.md): Bridge'lerin objectWillChange'ı parent'a relay edilir
/// → eski caller'lar için reactivity korunur.
@MainActor
final class SanctumViewModel: ObservableObject {

    // MARK: - Identity
    let symbol: String

    // MARK: - Bridges (yeni API)
    let quoteBridge: QuoteDataBridge
    let analysisBridge: AnalysisBridge
    let newsBridge: NewsBridge

    // MARK: - Cross-cutting State
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization
    init(symbol: String) {
        self.symbol = symbol
        let quote = QuoteDataBridge(symbol: symbol)
        self.quoteBridge = quote
        self.analysisBridge = AnalysisBridge(symbol: symbol, quoteBridge: quote)
        self.newsBridge = NewsBridge(symbol: symbol)

        relayBridgeChanges()

        Task { await loadData() }
    }

    /// Bridge'lerin `objectWillChange`'ını parent'a forward eder.
    /// Sebep: Eski view'lar `@ObservedObject var vm: SanctumViewModel` ile observe ediyor;
    /// computed property'ler bridge'den okuduğu için bridge değişiklikleri parent'ın
    /// objectWillChange'ını otomatik tetiklemez (L61).
    private func relayBridgeChanges() {
        quoteBridge.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
        analysisBridge.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
        newsBridge.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    // MARK: - Lifecycle

    func loadData() async {
        self.isLoading = true
        defer { self.isLoading = false }

        // 2026-05-07: Sequential await zinciri 30+30+30=90sn'lik beklemeye yol
        // açıyordu (her ağ çağrısı önceki bitmeden başlamıyordu). ensureQuote
        // (quote + candle) ile loadAnalysisCore (snapshot + macro) bağımsız —
        // paralel başlatılıyor. conveneCouncil ikisinin de bitmesini bekliyor
        // (snapshot + candle gerekli), önceki davranış korunmuş oluyor.
        async let quoteJob: () = quoteBridge.ensureQuote()
        async let analysisJob: () = analysisBridge.loadAnalysisCore()
        _ = await (quoteJob, analysisJob)

        await analysisBridge.conveneCouncil()
    }

    func refresh() async {
        await loadData()
    }

    func changeTimeframe(to newTimeframe: TimeframeMode) async {
        await quoteBridge.changeTimeframe(to: newTimeframe)
    }

    func analyzeOnDemand() async {
        await newsBridge.analyzeOnDemand()
    }

    // MARK: - Backward Compatibility (computed pass-through)
    // Eski caller'lar için — view migration yapılana kadar.

    var selectedTimeframe: TimeframeMode {
        get { quoteBridge.selectedTimeframe }
        set { quoteBridge.selectedTimeframe = newValue }
    }
    var quote: Quote? { quoteBridge.quote }
    var candles: [Candle] { quoteBridge.candles }
    var isCandlesLoading: Bool { quoteBridge.isCandlesLoading }

    var orionAnalysis: MultiTimeframeAnalysis? { analysisBridge.orionAnalysis }
    var orionFailure: OrionFailureReason? { analysisBridge.orionFailure }
    var orionScore: OrionScoreResult? { analysisBridge.orionScore }
    var entrySetup: EntrySetup? { analysisBridge.entrySetup }
    var macroRating: MacroEnvironmentRating? { analysisBridge.macroRating }
    var grandDecision: ArgusGrandDecision? { analysisBridge.grandDecision }
    var snapshot: FinancialSnapshot? { analysisBridge.snapshot }

    var newsInsights: [NewsInsight] { newsBridge.newsInsights }
    var hermesEvents: [HermesEvent] { newsBridge.hermesEvents }
    var kulisEvents: [HermesEvent] { newsBridge.kulisEvents }
    var isLoadingNews: Bool { newsBridge.isLoadingNews }
    var newsErrorMessage: String? { newsBridge.newsErrorMessage }
}
