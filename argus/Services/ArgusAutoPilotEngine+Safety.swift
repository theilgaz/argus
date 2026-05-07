import Foundation

// MARK: - Safety Check Result

/// Earnings/event guard sonucu. Hard-block yerine confidence penalty modeli:
/// provider yokken ticareti tamamen engellemek yerine güveni düşürüp
/// AdvisorNote ile uyarı veriyor.
struct SafetyCheckResult: Sendable {
    /// Güvene uygulanacak çarpan. 1.0 = penalty yok, <1.0 = risk indirimi.
    let confidenceMultiplier: Double
    /// UI'da gösterilecek danışman notu (nil = ek not yok).
    let advisorNote: AdvisorNote?
    /// `false` ise trade tamamen reddedilmeli (hard block — gerçek provider
    /// bağlandığında earnings <3 gün kala kullanılacak).
    let passed: Bool

    static let clean = SafetyCheckResult(
        confidenceMultiplier: 1.0,
        advisorNote: nil,
        passed: true
    )
}

// MARK: - Earnings Guard

extension ArgusAutoPilotEngine {

    /// Earnings/event risk guard.
    ///
    /// `AutoPilotConfig.earningsGuardEnabled == false` iken her durumda
    /// `SafetyCheckResult.clean` döner — hiçbir penalty uygulanmaz.
    ///
    /// `true` iken ve henüz gerçek bir earnings takvim provider'ı (EODHD,
    /// Yahoo Finance Calendar vb.) bağlı değilken: ticareti tamamen
    /// engellemek yerine confidence'a %15 penalty uygular ve bir
    /// AdvisorNote uyarısı ekler. Böylece güçlü sinyaller hâlâ geçer,
    /// sınırdaki sinyaller düşük-güven filtresine takılır.
    ///
    /// - TODO: Gerçek earnings calendar API bağlandığında:
    ///   - Earnings tarihi <3 gün ise → `passed = false` (hard block)
    ///   - Earnings tarihi 3-7 gün ise → %25 penalty
    ///   - Earnings tarihi >7 gün ise → penalty yok
    func checkSafety(symbol: String) async -> SafetyCheckResult {
        guard AutoPilotConfig.earningsGuardEnabled else {
            return .clean
        }

        // Gerçek provider bağlı değil — bilinmeyen earnings riski için
        // soft penalty uygula, hard block yapma.
        let penaltyMultiplier = 0.85

        ArgusLogger.warn(
            "Earnings guard etkin, provider bağlı değil — \(symbol) confidence ×\(penaltyMultiplier) penalty",
            category: "SAFETY"
        )

        let note = AdvisorNote(
            module: "EarningsGuard",
            advice: "Earnings takvimi bağlı değil; kazanç açıklama riski bilinmiyor. Güven %15 düşürüldü.",
            tone: .caution
        )

        return SafetyCheckResult(
            confidenceMultiplier: penaltyMultiplier,
            advisorNote: note,
            passed: true
        )
    }
}
