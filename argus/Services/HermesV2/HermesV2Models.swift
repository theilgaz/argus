import Foundation

// MARK: - HermesV2 Result Model
//
// 2026-05-05 (Round 8): Round 5+7B patternının 4. council uygulaması.
// Eski 5 "MasterEngine" (Sentiment/Impact/Timing/Credibility/Catalyst) yerine
// section-based haber analizi.

struct HermesV2Result: Identifiable, Codable {
    let id: String
    let symbol: String
    let timestamp: Date

    // Toplam skor (0-100). 50 = nötr, >65 = bullish news, <35 = bearish news
    let totalScore: Double

    // Bölüm skorları (nil = veri yetersiz)
    let sentimentScore: Double?       // Olumlu/olumsuz duygu
    let impactScore: Double?          // Haber etkisi büyüklüğü
    let freshnessScore: Double?       // Tazelik (saatlik decay)
    let credibilityScore: Double?     // Kaynak güvenilirliği
    let catalystScore: Double?        // M&A, earnings, upgrade vb. tetikleyici

    // Detaylar (UI için)
    let sentimentDetails: [String]
    let impactDetails: [String]
    let freshnessDetails: [String]
    let credibilityDetails: [String]
    let catalystDetails: [String]

    // Diagnostics
    let summary: String
    let highlights: [String]
    let warnings: [String]
    let validSectionCount: Int
    let keyHeadlines: [String]
    let catalysts: [String]

    init(
        symbol: String,
        totalScore: Double,
        sentimentScore: Double?,
        impactScore: Double?,
        freshnessScore: Double?,
        credibilityScore: Double?,
        catalystScore: Double?,
        sentimentDetails: [String],
        impactDetails: [String],
        freshnessDetails: [String],
        credibilityDetails: [String],
        catalystDetails: [String],
        summary: String,
        highlights: [String],
        warnings: [String],
        validSectionCount: Int,
        keyHeadlines: [String],
        catalysts: [String]
    ) {
        self.id = "\(symbol)_hermesv2_\(Date().timeIntervalSince1970)"
        self.symbol = symbol
        self.timestamp = Date()
        self.totalScore = totalScore
        self.sentimentScore = sentimentScore
        self.impactScore = impactScore
        self.freshnessScore = freshnessScore
        self.credibilityScore = credibilityScore
        self.catalystScore = catalystScore
        self.sentimentDetails = sentimentDetails
        self.impactDetails = impactDetails
        self.freshnessDetails = freshnessDetails
        self.credibilityDetails = credibilityDetails
        self.catalystDetails = catalystDetails
        self.summary = summary
        self.highlights = highlights
        self.warnings = warnings
        self.validSectionCount = validSectionCount
        self.keyHeadlines = keyHeadlines
        self.catalysts = catalysts
    }
}
