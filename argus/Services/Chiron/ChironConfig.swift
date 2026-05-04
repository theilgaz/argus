import Foundation

/// Static Configuration for Chiron Risk Governor
struct RiskBudgetConfig: Sendable {
    // Risk Limits
    // Removed static limit: nonisolated static let maxOpenRiskR: Double = 2.5 
    // 2026-05-04 paper-tuned: 10 → 30 (paper trading öğrenme alanı geniş tut)
    nonisolated static let maxPositions: Int = 30     // Max concurrent positions
    
    // Cluster Limits
    nonisolated static let maxConcentrationPerCluster: Int = 100 // Max positions per sector/cluster (Expanded from 2)
    
    // Time Limits
    // 2026-05-04 paper-tuned: 30 → 5 dk (aynı sembolde hızlı tur)
    nonisolated static let cooldownMinutes: Double = 5 // Min minutes between trades on same symbol

    // Regime thresholds (Aether) — 2026-05-04 paper-tuned
    // Eski: deepRiskOff 25, riskOff 40 (gerçek paraya geçilirse geri dön)
    // Yeni: deepRiskOff 15 (sadece gerçek çöküş), riskOff 25 (non-safe blok eşiği daha düşük)
    nonisolated static let deepRiskOffMaxScore: Double = 15
    nonisolated static let riskOffMaxScore: Double = 25

    // Forced unwind settings
    nonisolated static let deepRiskOffTrimPercent: Double = 50
    nonisolated static let riskOffTrimPercent: Double = 25
    
    // Dynamic Risk Ceiling
    // Aether >= 70 (Boğa)   -> 10R rahat ama sınırlı
    // Aether >= 55 (Nötr)   ->  6R temkinli
    // Aether >= 40 (Dikkat) ->  3R çok küçük
    // Aether >= 25 (Kötü)   ->  1.5R minimal
    // Aether  < 25 (Çöküş)  ->  0R yeni giriş yok
    // 2026-05-04 paper-tuned: tüm seviyeler 2x, çöküş eşiği 0 → 1R minimal
    // Eski: 10/6/3/1.5/0 (gerçek paraya geçilirse geri dön)
    nonisolated static func dynamicMaxRiskR(aetherScore: Double) -> Double {
        if aetherScore >= 70 { return 20.0 }   // Boğa: paper'da geniş alan
        if aetherScore >= 55 { return 12.0 }   // Nötr
        if aetherScore >= 40 { return 6.0 }    // Dikkat
        if aetherScore >= 25 { return 3.0 }    // Kötü
        return 1.0                             // Çöküş: minimal entry (was 0R hard-stop)
    }
}
