import Foundation

/// AtlasV2Result → AtlasDecision adapter.
///
/// Eski sürümde `ArgusGrandCouncil:168` `AtlasCouncil.shared.convene()` çağırıp
/// `AtlasDecision` döndürüyordu. AtlasCouncil "5 Ustası" pattern'i:
/// - Static thresholds (P/E < 10 = "değer") sektörden bağımsız
/// - Veri eksikse `return nil` → silent weight=0 → kullanıcı "Ağırlık: 0% Veri yok" log'u görür
/// - Cross-member logic yok, her usta bağımsız oy veriyor
///
/// AtlasV2Engine **section-based** (Değerleme/Karlılık/Büyüme/Mali Sağlık/Nakit/Temettü/Risk),
/// sektör-aware (`AtlasSectorBenchmarks`), modern quant pattern. Ama production'a hiç bağlanmamış,
/// sadece UI detay sayfasında çalışıyordu.
///
/// Bu adapter V2 çıktısını mevcut `AtlasDecision` struct'ına çevirir → swap minimal değişiklik
/// (tek satır `ArgusGrandCouncil:168`), downstream code (line 218, 234, 253, 325, 351, 411, 884)
/// mevcut `AtlasDecision` API'sini kullanmaya devam eder.
///
/// Mapping kuralları:
/// - `totalScore >= 70` → `.buy`, `<= 30` → `.sell`, else `.hold`
/// - `netSupport = totalScore / 100` (0.0–1.0 normalize)
/// - `isStrongSignal = totalScore >= 80 || totalScore <= 20`
/// - 6 section skorundan synthetic `FundamentalProposal`'lar türet (UI'da "Ustalar" yerine
///   modern bölümler görünür, ama tip uyumu korunur)
/// - `vetoReasons`: V2'nin warnings'inden
enum AtlasV2DecisionAdapter {

    /// Adapter ana entry point. V2 sonucunu legacy `AtlasDecision`'a çevirir.
    static func adapt(_ result: AtlasV2Result, engine: AutoPilotEngine) -> AtlasDecision {
        let action = derivedAction(totalScore: result.totalScore)
        let netSupport = result.totalScore / 100.0
        let isStrong = result.totalScore >= 80 || result.totalScore <= 20

        // 6 section'dan synthetic proposals üret. Eski "Ustalar" yerine modern bölümler.
        let proposals = synthesizeProposals(from: result)

        // Winning proposal: en yüksek confidence'lı (ya da en güçlü directional sinyal)
        let winning = proposals.max(by: { $0.confidence < $1.confidence })

        return AtlasDecision(
            symbol: result.symbol,
            action: action,
            netSupport: netSupport,
            isStrongSignal: isStrong,
            intrinsicValue: nil,                 // V2 intrinsic value hesaplamıyor (DCF yok)
            marginOfSafety: nil,                 // — aynı sebep
            winningProposal: winning,
            allProposals: proposals,
            votes: [],                           // V2'de voting/proposing ayrımı yok; tek motor
            vetoReasons: result.warnings,        // V2 warnings = potential vetoes
            timestamp: result.timestamp
        )
    }

    // MARK: - Private helpers

    private static func derivedAction(totalScore: Double) -> ProposedAction {
        // 2026-05-05 (Round 9) FIX: Eşik 70/30 → 60/40. Diğer V2 adapter'larla
        // standardizasyon. Atlas için 70 eşiği aşırı sıkıydı — fundamentalleri
        // makul (60+) skorlanan şirketler bile `.hold`'a düşüyordu. 60 eşiği
        // "iyi şirket = AL eğilimli" prensibiyle uyumlu.
        if totalScore >= 60 { return .buy }
        if totalScore <= 40 { return .sell }
        return .hold
    }

    /// V2'nin 6 bölüm skorundan FundamentalProposal listesi üretir.
    /// Bu sayede UI'da "Ustalar" yerine "Değerleme Sinyali / Karlılık Sinyali / ..." görünür.
    private static func synthesizeProposals(from result: AtlasV2Result) -> [FundamentalProposal] {
        let sections: [(id: String, name: String, score: Double, weight: Double, formula: String)] = [
            ("valuation",      "Değerleme Sinyali",   result.valuationScore,      0.25, "P/E + P/B + EV/EBITDA"),
            ("profitability",  "Karlılık Sinyali",    result.profitabilityScore,  0.30, "ROE + Net Margin"),
            ("growth",         "Büyüme Sinyali",      result.growthScore,         0.15, "Revenue + EPS CAGR"),
            ("health",         "Mali Sağlık Sinyali", result.healthScore,         0.20, "Debt/Equity + Current Ratio"),
            ("cash",           "Nakit Sinyali",       result.cashScore,           0.10, "FCF + Cash Position"),
            ("dividend",       "Temettü Sinyali",     result.dividendScore,       0.05, "Yield + Payout Ratio")
        ]

        return sections.map { sec in
            let action = derivedAction(totalScore: sec.score)
            let confidence = sec.score / 100.0
            let reasoning = "[\(sec.formula)] Bölüm skoru \(Int(sec.score))/100, ağırlık %\(Int(sec.weight * 100))"
            return FundamentalProposal(
                proposer: sec.id,
                proposerName: sec.name,
                action: action,
                confidence: confidence,
                reasoning: reasoning,
                targetPrice: nil,
                intrinsicValue: nil,
                marginOfSafety: nil
            )
        }
    }
}
