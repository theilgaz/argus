import Foundation

/// OrionV2Result → CouncilDecision adapter (legacy uyumluluğu).
///
/// Eski `OrionCouncil.shared.convene()` `CouncilDecision` döndürüyordu (5 "Ustası"
/// proposal'larının voting'i sonucu). Round 7B sonrası `OrionV2Engine.analyze()`
/// section-based total skor üretir; bu adapter çıktıyı legacy struct'a çevirir,
/// `ArgusGrandCouncil` downstream code'unu kırmaz.
///
/// Mapping:
/// - totalScore >= 70 → action=.buy, isStrongSignal=true
/// - 55 <= totalScore < 70 → .buy, isWeakSignal=true (ya da Strong ne kadar yüksek)
/// - 45 <= totalScore < 55 → .hold
/// - 30 <= totalScore < 45 → .sell, isWeakSignal=true
/// - totalScore < 30 → .sell, isStrongSignal=true
/// - netSupport: Eski sürümle uyumlu için (totalScore - 50) / 50.0 → -1..+1 aralığı,
///   GrandCouncil totalSupport hesabı confidence kullanır → onunla uyumlu olur
/// - 6 section'dan synthetic CouncilProposal türet (UI'da "Ustalar" yerine modern bölümler)
enum OrionV2DecisionAdapter {

    static func adapt(_ result: OrionV2Result) -> CouncilDecision {
        let action = derivedAction(totalScore: result.totalScore)
        // netSupport: Orion legacy'de "approveWeight - vetoWeight" idi (-1..+1).
        // V2'de tek skor 0-100; merkezden offset olarak normalize.
        let netSupport = (result.totalScore - 50) / 50.0

        let isStrong = result.totalScore >= 75 || result.totalScore <= 25
        let isWeak = (result.totalScore >= 55 && result.totalScore < 75) ||
                     (result.totalScore > 25 && result.totalScore <= 45)

        let proposals = synthesizeProposals(from: result)
        let winning = proposals.max(by: { $0.confidence < $1.confidence })

        return CouncilDecision(
            symbol: result.symbol,
            action: action,
            netSupport: netSupport,
            approveWeight: max(0, netSupport),
            vetoWeight: max(0, -netSupport),
            isStrongSignal: isStrong,
            isWeakSignal: isWeak && !isStrong,
            winningProposal: winning,
            allProposals: proposals,
            votes: [],                          // V2'de voting yok, tek motor skor üretiyor
            vetoReasons: result.warnings,
            timestamp: result.timestamp
        )
    }

    private static func derivedAction(totalScore: Double) -> ProposedAction {
        // 2026-05-05 (Round 9) FIX: Eşik 60 → 55. Eski sürüm 56 gibi orta-üstü
        // teknik tablo skorları `.hold`'a gidiyor → totalHold ağırlığı şişiyor →
        // GrandCouncil GÖZLE saplantısı. 55 eşiği nötr-üstü tüm sinyalleri AL'a
        // yönlendirir; gerçek nötr (45-55) ve negatif (<45) için hold/sell aynı.
        if totalScore >= 55 { return .buy }
        if totalScore <= 45 { return .sell }
        return .hold
    }

    private static func synthesizeProposals(from result: OrionV2Result) -> [CouncilProposal] {
        let sections: [(id: String, name: String, score: Double?)] = [
            ("orion_trend",      "Trend Sinyali",        result.trendScore),
            ("orion_momentum",   "Momentum Sinyali",     result.momentumScore),
            ("orion_volume",     "Hacim Sinyali",        result.volumeScore),
            ("orion_pattern",    "Formasyon Sinyali",    result.patternScore),
            ("orion_sr",         "Destek/Direnç Sinyali", result.srScore),
            ("orion_volatility", "Volatilite Sinyali",   result.volatilityScore)
        ]

        return sections.compactMap { sec in
            guard let score = sec.score else { return nil }
            let action = derivedAction(totalScore: score)
            let confidence = score / 100.0
            return CouncilProposal(
                proposer: sec.id,
                proposerName: sec.name,
                action: action,
                confidence: confidence,
                reasoning: "\(sec.name) bölüm skoru \(Int(score))/100",
                entryPrice: nil,
                stopLoss: nil,
                target: nil
            )
        }
    }
}
