import Foundation
import Combine

// MARK: - Market Context + Balance Bridge
/// AutoPilotStore'un piyasa bağlamı (MarketContextCoordinator) ve portföy bakiye
/// değişimlerine reaksiyonu. Kullanıcının `isAutoPilotEnabled` toggle'ına ASLA
/// dokunulmaz — sadece pozisyon sizing çarpanı ve loop interval'i ayarlanır.
extension AutoPilotStore {

    func handleBalanceChange(usd: Double, tl: Double) {
        let usdDelta = Swift.abs(usd - lastKnownGlobalBalance)
        let tlDelta = Swift.abs(tl - lastKnownBistBalance)
        guard usdDelta > 500 || tlDelta > 10_000 else {
            lastKnownGlobalBalance = usd
            lastKnownBistBalance = tl
            return
        }
        ArgusLogger.info(
            "💰 AutoPilot↔Portfolio: Balance değişti — USD \(Int(lastKnownGlobalBalance))→\(Int(usd)) (Δ\(Int(usdDelta))) | TRY \(Int(lastKnownBistBalance))→\(Int(tl)) (Δ\(Int(tlDelta)))",
            category: "OTOPİLOT"
        )
        lastKnownGlobalBalance = usd
        lastKnownBistBalance = tl
        // Bakiye değişimi → context re-evaluate (opportunity mode re-check)
        let snapshot = MarketContextCoordinator.shared.snapshot
        handleMarketContextUpdate(snapshot)
    }

    /// Piyasa bağlamı değiştiğinde otopilot davranışını ayarlar.
    /// Prensip: kullanıcı yetkisine dokunma, sadece çarpanla davran.
    func handleMarketContextUpdate(_ snapshot: MarketContextCoordinator.Snapshot) {
        let prev = contextMultiplier
        contextMultiplier = snapshot.positionMultiplier

        // Anlamlı değişim → log + (gelecekte notify).
        if Swift.abs(prev - contextMultiplier) >= 0.10 {
            ArgusLogger.info(
                "AutoPilot↔Context uyumu: \(snapshot.humanSummary)",
                category: "OTOPİLOT.CONTEXT"
            )
        }

        // Fırsat modunda loop interval'ini hızlandır (120sn = 2 dk), diğerlerinde 180sn.
        // Scan süresinden (1-2 dk) kısa interval isScanning guard'ına takılır.
        if snapshot.opportunityMode, let timer = autoPilotTimer, timer.timeInterval > 150 {
            restartTimer(interval: 120)
        } else if !snapshot.opportunityMode, let timer = autoPilotTimer, timer.timeInterval < 150 {
            restartTimer(interval: 180)
        }
    }

    /// Otopilot'un pozisyon boyutu hesabında kullanacağı çarpan (0.4-1.2).
    /// Hiçbir zaman 0 dönmez — açıksa taban seviyede de olsa trade yapabilsin.
    public func currentContextMultiplier() -> Double {
        return contextMultiplier
    }

    /// Koruyucu mod aktif mi? Pozisyon açmadan önce context check.
    public func isProtectiveModeActive() -> Bool {
        return MarketContextCoordinator.shared.snapshot.protectiveMode
    }

    /// Fırsat penceresi mi? Daha agresif giriş için.
    public func isOpportunityModeActive() -> Bool {
        return MarketContextCoordinator.shared.snapshot.opportunityMode
    }
}
