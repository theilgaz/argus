import Foundation

/// HermesV2Result → HermesDecision adapter (legacy uyumluluğu).
///
/// Eski `HermesCouncil.shared.convene()` `HermesDecision` döndürüyordu (5 "MasterEngine"
/// proposal'larının voting sonucu). Round 8 sonrası `HermesV2Engine.analyze()` section-based
/// total skor üretir; bu adapter çıktıyı legacy struct'a çevirir → `ArgusGrandCouncil`
/// downstream code'unu kırmaz.
///
/// Mapping:
/// - totalScore >= 65 → actionBias=.buy, sentiment=.weakPositive (≥75 → strongPositive)
/// - 35 <= totalScore < 65 → .hold + .neutral
/// - totalScore < 35 → .sell + .weakNegative (<25 → strongNegative)
/// - netSupport: (totalScore - 50) / 50 (-1..+1)
/// - isHighImpact: impactScore >= 70 veya catalystScore >= 70
enum HermesV2DecisionAdapter {

    static func adapt(_ result: HermesV2Result) -> HermesDecision {
        let actionBias = derivedAction(totalScore: result.totalScore)
        let sentiment = derivedSentiment(totalScore: result.totalScore)
        let netSupport = (result.totalScore - 50) / 50.0
        let isHighImpact = (result.impactScore ?? 0) >= 70 || (result.catalystScore ?? 0) >= 70

        // Synthetic winning proposal — en yüksek skorlu bölüm
        let winning = synthesizeWinning(from: result, sentiment: sentiment)

        return HermesDecision(
            symbol: result.symbol,
            sentiment: sentiment,
            actionBias: actionBias,
            netSupport: netSupport,
            isHighImpact: isHighImpact,
            winningProposal: winning,
            votes: [],
            keyHeadlines: result.keyHeadlines,
            catalysts: result.catalysts,
            timestamp: result.timestamp
        )
    }

    private static func derivedAction(totalScore: Double) -> ProposedAction {
        // 2026-05-05 (Round 9) FIX: Eşik 60 → 55. Diğer V2 adapter'larla tutarlı.
        // Orta-üstü haber tablosu (55-60) AL'a yönlenir; gerçek nötr (45-55) hold.
        if totalScore >= 55 { return .buy }
        if totalScore <= 45 { return .sell }
        return .hold
    }

    private static func derivedSentiment(totalScore: Double) -> NewsSentiment {
        if totalScore >= 75 { return .strongPositive }
        if totalScore >= 55 { return .weakPositive }
        if totalScore >= 45 { return .neutral }
        if totalScore >= 25 { return .weakNegative }
        return .strongNegative
    }

    private static func synthesizeWinning(from result: HermesV2Result, sentiment: NewsSentiment) -> HermesNewsProposal? {
        let sections: [(id: String, name: String, score: Double?)] = [
            ("hermes_sentiment",  "Hissiyat Sinyali",     result.sentimentScore),
            ("hermes_impact",     "Etki Sinyali",         result.impactScore),
            ("hermes_freshness",  "Tazelik Sinyali",      result.freshnessScore),
            ("hermes_credibility","Güvenilirlik Sinyali", result.credibilityScore),
            ("hermes_catalyst",   "Tetikleyici Sinyali",  result.catalystScore)
        ]
        let valid = sections.compactMap { sec -> (String, String, Double)? in
            guard let s = sec.score else { return nil }
            return (sec.id, sec.name, s)
        }
        guard let dominant = valid.max(by: { $0.2 < $1.2 }) else { return nil }

        return HermesNewsProposal(
            proposer: dominant.0,
            proposerName: dominant.1,
            sentiment: sentiment,
            confidence: dominant.2 / 100.0,
            reasoning: result.summary,
            keyHeadline: result.keyHeadlines.first
        )
    }
}
