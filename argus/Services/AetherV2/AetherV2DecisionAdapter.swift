import Foundation

/// AetherV2Result → AetherDecision adapter.
///
/// Eski `AetherCouncil.shared.convene()` `AetherDecision` döndürüyordu (5 İngilizce
/// "Engine" proposal'larının voting sonucu). Round 7B sonrası `AetherV2Engine.analyze()`
/// section-based total skor üretir. Bu adapter sonucu legacy `AetherDecision` struct'ına
/// çevirir → `ArgusGrandCouncil` downstream code'unu kırmaz.
///
/// Mapping:
/// - totalScore >= 75 → stance=.riskOn
/// - 55 <= totalScore < 75 → .cautious
/// - 30 <= totalScore < 55 → .defensive
/// - totalScore < 30 → .riskOff
/// - netSupport: totalScore / 100 (0-1)
/// - marketMode: VIX/F&G temelli — yüksek korku = .fear, açgözlülük = .extremeGreed
enum AetherV2DecisionAdapter {

    static func adapt(_ result: AetherV2Result, marketMode: MarketMode = .neutral) -> AetherDecision {
        let stance = derivedStance(totalScore: result.totalScore)
        let netSupport = result.totalScore / 100.0
        let isStrong = result.totalScore >= 75 || result.totalScore <= 25

        // Synthetic winning proposal — en yüksek skorlu bölüm
        let winning = synthesizeWinningProposal(from: result, stance: stance)

        return AetherDecision(
            stance: stance,
            marketMode: marketMode,
            netSupport: netSupport,
            isStrongSignal: isStrong,
            winningProposal: winning,
            votes: [],
            warnings: result.warnings,
            timestamp: result.timestamp
        )
    }

    private static func derivedStance(totalScore: Double) -> MacroStance {
        if totalScore >= 75 { return .riskOn }
        if totalScore >= 55 { return .cautious }
        if totalScore >= 30 { return .defensive }
        return .riskOff
    }

    private static func synthesizeWinningProposal(from result: AetherV2Result, stance: MacroStance) -> MacroProposal {
        // En yüksek skorlu bölümü seç (winning proposal'ın "proposer'ı" o)
        let sections: [(id: String, name: String, score: Double?)] = [
            ("aether_liquidity", "Likidite Sinyali",         result.liquidityScore),
            ("aether_risk",      "Risk Modu Sinyali",        result.riskOffScore),
            ("aether_sector",    "Sektör Rotasyonu Sinyali", result.sectorRotationScore),
            ("aether_cross",     "Cross-Asset Sinyali",      result.crossAssetScore),
            ("aether_sentiment", "Hissiyat Sinyali",         result.sentimentScore)
        ]
        let valid = sections.compactMap { sec -> (String, String, Double)? in
            guard let s = sec.score else { return nil }
            return (sec.id, sec.name, s)
        }
        let dominant = valid.max(by: { $0.2 < $1.2 })

        let proposerId = dominant?.0 ?? "aether_v2"
        let proposerName = dominant?.1 ?? "AetherV2"
        let confidence = result.totalScore / 100.0

        return MacroProposal(
            proposer: proposerId,
            proposerName: proposerName,
            stance: stance,
            confidence: confidence,
            reasoning: result.summary
        )
    }
}
