import Foundation
import Combine

/// Scan state + AGORA decision snapshot/trace store.
/// God Object Aşama A — ExecutionStateViewModel'den çıkarıldı.
@MainActor
final class ScanOrchestrator: ObservableObject {
    static let shared = ScanOrchestrator()

    @Published var isScanning: Bool = false
    @Published var lastScanTime: Date?
    @Published var activeScanSymbols: [String] = []

    /// AGORA decision snapshots (capped at 100).
    @Published var agoraSnapshots: [DecisionSnapshot] = []

    /// AGORA V2 decision traces by symbol.
    @Published var agoraTraces: [String: AgoraTrace] = [:]

    private init() {}

    func setScanning(_ scanning: Bool, symbols: [String] = []) {
        isScanning = scanning
        activeScanSymbols = symbols
        if scanning {
            lastScanTime = Date()
        }
    }

    func addAgoraSnapshot(_ snapshot: DecisionSnapshot) {
        agoraSnapshots.insert(snapshot, at: 0)
        if agoraSnapshots.count > 100 {
            agoraSnapshots.removeLast()
        }
    }

    func getRecentSnapshots(for symbol: String, limit: Int = 10) -> [DecisionSnapshot] {
        return agoraSnapshots
            .filter { $0.symbol == symbol }
            .prefix(limit)
            .map { $0 }
    }
}
