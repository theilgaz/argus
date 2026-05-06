import Foundation
import Combine

/// AutoPilot lifecycle + UserDefaults persistence + engine seçimi.
/// God Object Aşama A — ExecutionStateViewModel'den çıkarıldı.
@MainActor
final class AutoPilotController: ObservableObject {
    static let shared = AutoPilotController()

    @Published var isAutoPilotEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(isAutoPilotEnabled, forKey: "autopilot_enabled_v2")
            if isAutoPilotEnabled {
                start()
            } else {
                stop()
            }
        }
    }

    @Published var selectedEngine: AutoPilotEngine = .corse {
        didSet {
            UserDefaults.standard.set(selectedEngine.rawValue, forKey: "autopilot_engine_v2")
        }
    }

    @Published var autoPilotLogs: [String] = []

    private var autoPilotTask: Task<Void, Never>?

    private init() {
        loadPersistedState()
    }

    private func loadPersistedState() {
        isAutoPilotEnabled = UserDefaults.standard.bool(forKey: "autopilot_enabled_v2")
        if let engineRaw = UserDefaults.standard.string(forKey: "autopilot_engine_v2"),
           let engine = AutoPilotEngine(rawValue: engineRaw) {
            selectedEngine = engine
        }
    }

    private func start() {
        ArgusLogger.info("AutoPilot Started: \(selectedEngine.rawValue)", category: "EXECUTION")
        NotificationCenter.default.post(name: .autoPilotStateChanged, object: nil, userInfo: ["enabled": true])
    }

    private func stop() {
        ArgusLogger.info("AutoPilot Stopped", category: "EXECUTION")
        autoPilotTask?.cancel()
        autoPilotTask = nil
        ScanOrchestrator.shared.isScanning = false
        NotificationCenter.default.post(name: .autoPilotStateChanged, object: nil, userInfo: ["enabled": false])
    }

    func toggle() {
        isAutoPilotEnabled.toggle()
    }
}
