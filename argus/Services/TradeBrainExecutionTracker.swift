import Foundation

// MARK: - TradeBrainExecutionTracker
/// Otopilot scan'i sembol bazında karar üretir; ama execution aşamasında
/// (TradeBrainExecutor.executeBuy) çok sayıda guard return mevcut:
/// - Yetersiz allocation
/// - Rejim bloğu
/// - Portföy ısı limiti
/// - Risk gate
/// - BIST Vali / Event takvimi
/// - ExecutionGovernor reject
/// - Round-down 0 / Notional yetersiz (FIX C+E)
///
/// Eski sürümde bu RED'ler yalnızca log'a düşüyordu — kullanıcı UI'da yalnız
/// scan-level (`AutoPilotStore.lastScanSummary.topSkipReasons`) görebiliyordu.
/// "Otopilot karar verdi ama trade açmadı" sorusunun cevabı görünmez kalıyordu.
///
/// Bu actor, her scan turunda execution-level RED'leri toplar; AutoPilotStore
/// scan özetini build ederken `topReasons` çağrısıyla merge eder.
actor TradeBrainExecutionTracker {
    static let shared = TradeBrainExecutionTracker()

    private struct SkipEntry {
        let symbol: String
        let reason: String
        let timestamp: Date
    }

    private var skips: [SkipEntry] = []
    private let maxEntries = 50

    private init() {}

    /// Yeni scan başında çağrılır; eski scan'in RED'leri temizlenir.
    func clearForNewScan() {
        skips.removeAll(keepingCapacity: true)
    }

    /// executeBuy/executeSell guard return noktalarından çağrılır.
    func recordSkip(symbol: String, reason: String) {
        skips.append(SkipEntry(symbol: symbol, reason: reason, timestamp: Date()))
        if skips.count > maxEntries {
            skips = Array(skips.suffix(maxEntries))
        }
    }

    /// "3x Yetersiz allocation", "2x Rejim bloğu" formatında, en sık RED'ler.
    func topReasons(limit: Int = 5) -> [String] {
        guard !skips.isEmpty else { return [] }
        let grouped = Dictionary(grouping: skips, by: { $0.reason })
        return grouped
            .map { (reason, entries) in (count: entries.count, label: "\(entries.count)x \(reason)") }
            .sorted { $0.count > $1.count }
            .prefix(limit)
            .map { $0.label }
    }

    /// Debug/tanılama için ham liste — son N RED, sembol+reason+ts.
    func recentSkips(limit: Int = 20) -> [(symbol: String, reason: String, timestamp: Date)] {
        return skips.suffix(limit).map { ($0.symbol, $0.reason, $0.timestamp) }
    }

    /// Toplam skip sayısı (UI badge için).
    func totalCount() -> Int {
        return skips.count
    }
}
