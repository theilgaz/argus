import Foundation

// MARK: - OrionV2 Result Model
//
// AtlasV2 patternı (Round 5) Orion için tekrarlanmıştır. Eski "5 Ustası" yerine
// section-based teknik analiz: Trend / Momentum / Hacim / Formasyon / Destek-Direnç /
// Volatilite. Her bölüm 2-3 standart indicator (IndicatorService'ten) hesaplar.
// Veri yetersiz section nil dönmek yerine score üretmez (Round 5 nil-aware pattern).

struct OrionV2Result: Identifiable, Codable {
    let id: String
    let symbol: String
    let timestamp: Date

    // Toplam skor (0-100, ağırlıklı ortalama mevcut bölümlerden)
    let totalScore: Double

    // Bölüm skorları (nil = veri yetersiz)
    let trendScore: Double?
    let momentumScore: Double?
    let volumeScore: Double?
    let patternScore: Double?
    let srScore: Double?           // Support/Resistance
    let volatilityScore: Double?

    // Detaylar (UI için)
    let trendDetails: [String]
    let momentumDetails: [String]
    let volumeDetails: [String]
    let patternDetails: [String]
    let srDetails: [String]
    let volatilityDetails: [String]

    // Genel yorum
    let summary: String
    let highlights: [String]
    let warnings: [String]

    // Kaç bölüm geçerli (UI'da "3/6 bölüm" göstermek için)
    let validSectionCount: Int

    init(
        symbol: String,
        totalScore: Double,
        trendScore: Double?,
        momentumScore: Double?,
        volumeScore: Double?,
        patternScore: Double?,
        srScore: Double?,
        volatilityScore: Double?,
        trendDetails: [String],
        momentumDetails: [String],
        volumeDetails: [String],
        patternDetails: [String],
        srDetails: [String],
        volatilityDetails: [String],
        summary: String,
        highlights: [String],
        warnings: [String],
        validSectionCount: Int
    ) {
        self.id = "\(symbol)_orionv2_\(Date().timeIntervalSince1970)"
        self.symbol = symbol
        self.timestamp = Date()
        self.totalScore = totalScore
        self.trendScore = trendScore
        self.momentumScore = momentumScore
        self.volumeScore = volumeScore
        self.patternScore = patternScore
        self.srScore = srScore
        self.volatilityScore = volatilityScore
        self.trendDetails = trendDetails
        self.momentumDetails = momentumDetails
        self.volumeDetails = volumeDetails
        self.patternDetails = patternDetails
        self.srDetails = srDetails
        self.volatilityDetails = volatilityDetails
        self.summary = summary
        self.highlights = highlights
        self.warnings = warnings
        self.validSectionCount = validSectionCount
    }
}
