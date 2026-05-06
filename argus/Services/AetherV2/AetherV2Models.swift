import Foundation

// MARK: - AetherV2 Result Model
//
// Eski 5 "Master" pattern (MonetaryPolicy/MarketSentiment/SectorRotation/EconomicCycle/CrossAsset)
// yerine section-based makro analiz. Round 5+7 patternı.

struct AetherV2Result: Identifiable, Codable {
    let id: String
    let timestamp: Date

    // Toplam skor (0-100, ağırlıklı ortalama mevcut bölümlerden)
    // Yüksek skor = risk-on uygun, düşük skor = risk-off
    let totalScore: Double

    // Bölüm skorları (nil = veri yetersiz)
    let liquidityScore: Double?
    let riskOffScore: Double?       // Düşükse risk-off (yüksek = "risk-off değil")
    let sectorRotationScore: Double?
    let crossAssetScore: Double?
    let sentimentScore: Double?

    // Detaylar
    let liquidityDetails: [String]
    let riskOffDetails: [String]
    let sectorRotationDetails: [String]
    let crossAssetDetails: [String]
    let sentimentDetails: [String]

    let summary: String
    let highlights: [String]
    let warnings: [String]
    let validSectionCount: Int

    init(
        totalScore: Double,
        liquidityScore: Double?,
        riskOffScore: Double?,
        sectorRotationScore: Double?,
        crossAssetScore: Double?,
        sentimentScore: Double?,
        liquidityDetails: [String],
        riskOffDetails: [String],
        sectorRotationDetails: [String],
        crossAssetDetails: [String],
        sentimentDetails: [String],
        summary: String,
        highlights: [String],
        warnings: [String],
        validSectionCount: Int
    ) {
        self.id = "aetherv2_\(Date().timeIntervalSince1970)"
        self.timestamp = Date()
        self.totalScore = totalScore
        self.liquidityScore = liquidityScore
        self.riskOffScore = riskOffScore
        self.sectorRotationScore = sectorRotationScore
        self.crossAssetScore = crossAssetScore
        self.sentimentScore = sentimentScore
        self.liquidityDetails = liquidityDetails
        self.riskOffDetails = riskOffDetails
        self.sectorRotationDetails = sectorRotationDetails
        self.crossAssetDetails = crossAssetDetails
        self.sentimentDetails = sentimentDetails
        self.summary = summary
        self.highlights = highlights
        self.warnings = warnings
        self.validSectionCount = validSectionCount
    }
}
