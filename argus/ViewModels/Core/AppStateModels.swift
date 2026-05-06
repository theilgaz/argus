import Foundation

/// AppStateCoordinator'ın 31 flat @Published property'sinin
/// 6 anlamsal domain'e gruplanmış struct'ları.
///
/// Davranış aynı — sadece tip güvenliği ve organizasyon.
/// Backward compat: AppStateCoordinator'da computed property'ler
/// eski API'ı (`coordinator.dailyReport`, vb.) korur.

// MARK: - Backtest

/// Backtest çalıştırma + sonuç durumu.
struct BacktestState {
    var isRunning: Bool = false
    var activeResult: BacktestResult? = nil
    var sarTsiResult: OrionSarTsiBacktestResult? = nil
    var isLoadingSarTsi: Bool = false
    var sarTsiErrorMessage: String? = nil
}

// MARK: - Reports

/// Günlük/haftalık market raporları (Global + BIST).
struct ReportState {
    var daily: String? = nil
    var weekly: String? = nil
    var bistDaily: String? = nil
    var bistWeekly: String? = nil
}

// MARK: - Shock & Stress Analysis

/// Şok flag'leri, overreaction analizi, Demeter korelasyon matrisi.
struct ShockState {
    var activeShocks: [ShockFlag] = []
    var overreaction: OverreactionResult? = nil
    var demeterScores: [DemeterScore] = []
    var demeterMatrix: CorrelationMatrix? = nil
    var isRunningDemeter: Bool = false
}

// MARK: - Universe & Symbol Selection

/// Sembol seçimi, universe cache, KAP açıklamaları, Hermes özet/mode.
struct UniverseState {
    var selectedSymbol: String? = nil
    var cache: [String: UniverseItem] = [:]
    var kapDisclosures: [String: [KAPDataService.KAPNews]] = [:]
    var hermesSummaries: [String: [HermesSummary]] = [:]
    var hermesMode: HermesMode = .full
}

// MARK: - Environment / Global Context

/// Genel UI loading, terminal, lastAction, ETF cache, atmosphere ve
/// portföy konfigürasyonu (isUnlimitedPositions).
struct EnvironmentState {
    var isGlobalLoading: Bool = false
    var isLoadingEtf: Bool = false
    var etfSummaries: [String: ArgusEtfSummary] = [:]
    var isUnlimitedPositions: Bool = false
    var terminalItems: [TerminalItem] = []
    var lastAction: String = ""
    var bistAtmosphere: AetherDecision? = nil
    var bistAtmosphereLastUpdated: Date? = nil
    var errorMessage: String? = nil
}

// MARK: - Execution Mirror

/// ExecutionStateViewModel'den AppStateCoordinator'a relay edilen state.
/// AppStateCoordinator SINGLE SUBSCRIBER pattern'ini korumak için.
struct ExecutionMirrorState {
    var planAlerts: [TradeBrainAlert] = []
    var agoraSnapshots: [DecisionSnapshot] = []
    var lastTradeTimes: [String: Date] = [:]
}
