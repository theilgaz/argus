import Foundation
import Combine
import SwiftUI

/// FAZ 2: AppStateCoordinator - Single Source of Truth (SSOT)
/// Tüm alt ViewModel'leri koordine eden merkezi orchestrator.
/// TradingViewModel'den ayrılmış modüler yapı için köprü görevi görür.
///
/// SSOT Pattern: AppStateCoordinator acts as a facade to child stores/ViewModels:
/// - Does NOT duplicate data
/// - Uses computed properties to access child store data
/// - Binds only its own @Published UI state properties
/// - Coordinates between different domains (Watchlist, Market, Portfolio, Signals, Execution, Diagnostics)
///
/// 2026-05-06 — Aşama A refactor: 31 flat @Published → 6 typed domain state
/// (BacktestState, ReportState, ShockState, UniverseState, EnvironmentState, ExecutionMirrorState).
/// Eski caller'lar için backward-compat computed property'ler korundu.
@MainActor
final class AppStateCoordinator: ObservableObject {

    // MARK: - Singleton (Geçiş döneminde backward compatibility için)
    static let shared = AppStateCoordinator()

    // MARK: - Sub ViewModels
    let watchlist: WatchlistViewModel

    // MARK: - Legacy Accessor for Views (Backward Compatibility)
    var portfolio: PortfolioStore {
        PortfolioStore.shared
    }

    // MARK: - Domain State (6 typed groups)

    @Published var backtest = BacktestState()
    @Published var report = ReportState()
    @Published var shock = ShockState()
    @Published var universe = UniverseState()
    @Published var environment = EnvironmentState()
    @Published var executionMirror = ExecutionMirrorState()

    // MARK: - Combine
    var cancellables = Set<AnyCancellable>()

    // MARK: - Init
    private init() {
        self.watchlist = WatchlistViewModel()
        setupDataBindings()
        setupDomainSideEffects()
    }

    /// Domain state struct değişimlerinde tetiklenecek side-effect'ler.
    /// (Eski didSet'ler typed struct'a taşınamadığı için Combine ile çözülüyor.)
    private func setupDomainSideEffects() {
        $environment
            .map(\.isUnlimitedPositions)
            .removeDuplicates()
            .sink { value in
                PortfolioRiskManager.shared.isUnlimitedPositionsEnabled = value
            }
            .store(in: &cancellables)
    }

    // MARK: - Convenience Methods

    /// Sembol detay görünümüne geçiş
    func selectSymbol(_ symbol: String) {
        universe.selectedSymbol = symbol
    }

    // MARK: - Backward Compatibility (computed pass-through)
    // Eski caller'lar için — view migration yapılana kadar.
    // Yeni kod doğrudan `coordinator.backtest.isRunning` formunu kullanmalı.

    // Backtest
    var isBacktesting: Bool {
        get { backtest.isRunning }
        set { backtest.isRunning = newValue }
    }
    var activeBacktestResult: BacktestResult? {
        get { backtest.activeResult }
        set { backtest.activeResult = newValue }
    }
    var sarTsiBacktestResult: OrionSarTsiBacktestResult? {
        get { backtest.sarTsiResult }
        set { backtest.sarTsiResult = newValue }
    }
    var isLoadingSarTsiBacktest: Bool {
        get { backtest.isLoadingSarTsi }
        set { backtest.isLoadingSarTsi = newValue }
    }
    var sarTsiErrorMessage: String? {
        get { backtest.sarTsiErrorMessage }
        set { backtest.sarTsiErrorMessage = newValue }
    }

    // Report
    var dailyReport: String? {
        get { report.daily }
        set { report.daily = newValue }
    }
    var weeklyReport: String? {
        get { report.weekly }
        set { report.weekly = newValue }
    }
    var bistDailyReport: String? {
        get { report.bistDaily }
        set { report.bistDaily = newValue }
    }
    var bistWeeklyReport: String? {
        get { report.bistWeekly }
        set { report.bistWeekly = newValue }
    }

    // Shock
    var activeShocks: [ShockFlag] {
        get { shock.activeShocks }
        set { shock.activeShocks = newValue }
    }
    var overreactionResult: OverreactionResult? {
        get { shock.overreaction }
        set { shock.overreaction = newValue }
    }
    var demeterScores: [DemeterScore] {
        get { shock.demeterScores }
        set { shock.demeterScores = newValue }
    }
    var demeterMatrix: CorrelationMatrix? {
        get { shock.demeterMatrix }
        set { shock.demeterMatrix = newValue }
    }
    var isRunningDemeter: Bool {
        get { shock.isRunningDemeter }
        set { shock.isRunningDemeter = newValue }
    }

    // Universe
    var selectedSymbol: String? {
        get { universe.selectedSymbol }
        set { universe.selectedSymbol = newValue }
    }
    var universeCache: [String: UniverseItem] {
        get { universe.cache }
        set { universe.cache = newValue }
    }
    var kapDisclosures: [String: [KAPDataService.KAPNews]] {
        get { universe.kapDisclosures }
        set { universe.kapDisclosures = newValue }
    }
    var hermesSummaries: [String: [HermesSummary]] {
        get { universe.hermesSummaries }
        set { universe.hermesSummaries = newValue }
    }
    var hermesMode: HermesMode {
        get { universe.hermesMode }
        set { universe.hermesMode = newValue }
    }

    // Environment
    var isGlobalLoading: Bool {
        get { environment.isGlobalLoading }
        set { environment.isGlobalLoading = newValue }
    }
    var isLoadingEtf: Bool {
        get { environment.isLoadingEtf }
        set { environment.isLoadingEtf = newValue }
    }
    var etfSummaries: [String: ArgusEtfSummary] {
        get { environment.etfSummaries }
        set { environment.etfSummaries = newValue }
    }
    var isUnlimitedPositions: Bool {
        get { environment.isUnlimitedPositions }
        set { environment.isUnlimitedPositions = newValue }
    }
    var terminalItems: [TerminalItem] {
        get { environment.terminalItems }
        set { environment.terminalItems = newValue }
    }
    var lastAction: String {
        get { environment.lastAction }
        set { environment.lastAction = newValue }
    }
    var bistAtmosphere: AetherDecision? {
        get { environment.bistAtmosphere }
        set { environment.bistAtmosphere = newValue }
    }
    var bistAtmosphereLastUpdated: Date? {
        get { environment.bistAtmosphereLastUpdated }
        set { environment.bistAtmosphereLastUpdated = newValue }
    }
    var errorMessage: String? {
        get { environment.errorMessage }
        set { environment.errorMessage = newValue }
    }

    // Execution Mirror
    var planAlerts: [TradeBrainAlert] {
        get { executionMirror.planAlerts }
        set { executionMirror.planAlerts = newValue }
    }
    var agoraSnapshots: [DecisionSnapshot] {
        get { executionMirror.agoraSnapshots }
        set { executionMirror.agoraSnapshots = newValue }
    }
    var lastTradeTimes: [String: Date] {
        get { executionMirror.lastTradeTimes }
        set { executionMirror.lastTradeTimes = newValue }
    }
}
