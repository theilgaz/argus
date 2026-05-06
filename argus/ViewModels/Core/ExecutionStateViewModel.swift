import Foundation
import Combine
import SwiftUI

// MARK: - Execution State ViewModel (Facade)
/// God Object Aşama A — 4 sorumluluğa bölündü:
/// - AutoPilotController:  AutoPilot lifecycle + UserDefaults + engine seçimi
/// - ScanOrchestrator:     Scan state + AGORA snapshot/trace store
/// - ExecutionLogger:      lastTradeError + lastTradeTimes + decision context
/// - AlertManager:         buy/sell core + TradeBrain observers + cooldowns
///
/// Backward compat: 27+ caller `ExecutionStateViewModel.shared.X` formuna
/// alışkın → computed pass-through ile API korundu.
/// Reactivity: Child'ların objectWillChange'ı parent'a relay edilir (L61).
@MainActor
final class ExecutionStateViewModel: ObservableObject {
    static let shared = ExecutionStateViewModel()

    // MARK: - Children

    let autoPilot: AutoPilotController
    let scan: ScanOrchestrator
    let logger: ExecutionLogger
    let alerts: AlertManager

    private var cancellables = Set<AnyCancellable>()

    private init() {
        self.autoPilot = AutoPilotController.shared
        self.scan = ScanOrchestrator.shared
        self.logger = ExecutionLogger.shared
        self.alerts = AlertManager.shared

        relayChildChanges()
    }

    /// L61: Computed pass-through property'ler view'da observe edildiğinde
    /// child değişimleri parent'ın objectWillChange'ını otomatik tetiklemez.
    /// Sink ile manuel relay yapılır.
    private func relayChildChanges() {
        autoPilot.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &cancellables)
        scan.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &cancellables)
        logger.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &cancellables)
        alerts.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &cancellables)
    }

    // MARK: - Backward Compatibility

    // AutoPilotController
    var isAutoPilotEnabled: Bool {
        get { autoPilot.isAutoPilotEnabled }
        set { autoPilot.isAutoPilotEnabled = newValue }
    }
    var selectedEngine: AutoPilotEngine {
        get { autoPilot.selectedEngine }
        set { autoPilot.selectedEngine = newValue }
    }
    var autoPilotLogs: [String] {
        get { autoPilot.autoPilotLogs }
        set { autoPilot.autoPilotLogs = newValue }
    }
    func toggleAutoPilot() { autoPilot.toggle() }

    // ScanOrchestrator
    var isScanning: Bool {
        get { scan.isScanning }
        set { scan.isScanning = newValue }
    }
    var lastScanTime: Date? {
        get { scan.lastScanTime }
        set { scan.lastScanTime = newValue }
    }
    var activeScanSymbols: [String] {
        get { scan.activeScanSymbols }
        set { scan.activeScanSymbols = newValue }
    }
    var agoraSnapshots: [DecisionSnapshot] {
        get { scan.agoraSnapshots }
        set { scan.agoraSnapshots = newValue }
    }
    var agoraTraces: [String: AgoraTrace] {
        get { scan.agoraTraces }
        set { scan.agoraTraces = newValue }
    }
    func setScanning(_ scanning: Bool, symbols: [String] = []) {
        scan.setScanning(scanning, symbols: symbols)
    }
    func addAgoraSnapshot(_ snapshot: DecisionSnapshot) {
        scan.addAgoraSnapshot(snapshot)
    }
    func getRecentSnapshots(for symbol: String, limit: Int = 10) -> [DecisionSnapshot] {
        scan.getRecentSnapshots(for: symbol, limit: limit)
    }

    // ExecutionLogger
    var lastTradeError: String? {
        get { logger.lastTradeError }
        set { logger.lastTradeError = newValue }
    }
    var lastTradeTimes: [String: Date] {
        get { logger.lastTradeTimes }
        set { logger.lastTradeTimes = newValue }
    }

    // AlertManager
    var planAlerts: [TradeBrainAlert] {
        get { alerts.planAlerts }
        set { alerts.planAlerts = newValue }
    }
    var tradeCooldowns: [String: Date] {
        get { alerts.tradeCooldowns }
        set { alerts.tradeCooldowns = newValue }
    }
    func isInCooldown(symbol: String) -> Bool { alerts.isInCooldown(symbol: symbol) }
    func setCooldown(symbol: String, duration: TimeInterval) { alerts.setCooldown(symbol: symbol, duration: duration) }
    func clearCooldown(symbol: String) { alerts.clearCooldown(symbol: symbol) }
    func remainingCooldown(symbol: String) -> TimeInterval? { alerts.remainingCooldown(symbol: symbol) }

    @discardableResult
    func buy(symbol: String, quantity: Double, source: TradeSource = .user, engine: AutoPilotEngine? = nil, stopLoss: Double? = nil, takeProfit: Double? = nil, rationale: String? = nil, decisionTrace: DecisionTraceSnapshot? = nil, marketSnapshot: MarketSnapshot? = nil, referencePrice: Double? = nil) -> Trade? {
        alerts.buy(symbol: symbol, quantity: quantity, source: source, engine: engine, stopLoss: stopLoss, takeProfit: takeProfit, rationale: rationale, decisionTrace: decisionTrace, marketSnapshot: marketSnapshot, referencePrice: referencePrice)
    }

    func sell(symbol: String, quantity: Double, source: TradeSource = .user, engine: AutoPilotEngine? = nil, reason: String? = nil, referencePrice: Double? = nil) {
        alerts.sell(symbol: symbol, quantity: quantity, source: source, engine: engine, reason: reason, referencePrice: referencePrice)
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let autoPilotStateChanged = Notification.Name("autoPilotStateChanged")
    static let tradeBrainAlert = Notification.Name("tradeBrainAlert")
}
