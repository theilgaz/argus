import Foundation

// MARK: - HermesV2 Engine
//
// 2026-05-05 (Round 8): Eski 5 "MasterEngine" (Sentiment/Impact/Timing/Credibility/Catalyst)
// pattern yerine section-based haber analizi. Round 5/7 patternı (nil-aware, weight normalize,
// trace logging). HermesNewsSnapshot içindeki insights ve articles üzerinden 5 bölümlü analiz.

actor HermesV2Engine {
    static let shared = HermesV2Engine()

    private var cache: [String: (result: HermesV2Result, timestamp: Date)] = [:]
    private let cacheTTL: TimeInterval = 300  // 5 dakika

    private init() {}

    // MARK: - Ana Analiz

    func analyze(symbol: String, news: HermesNewsSnapshot) async -> HermesV2Result {
        if let cached = cache[symbol], Date().timeIntervalSince(cached.timestamp) < cacheTTL {
            return cached.result
        }

        // Boş haber snapshot → her şey nil
        // 2026-05-05 (Round 9) FIX: Eskiden silent return ediyordu, kullanıcı log'da
        // HermesV2 görünmediği için "çalışmıyor mu" sanıyordu. Artık net log düşer.
        guard !news.insights.isEmpty else {
            ArgusLogger.info(.hermes, "V2 \(symbol) total=50 (0/5 bölüm) — haber yok, analiz atlandı")
            let empty = HermesV2Result(
                symbol: symbol,
                totalScore: 50,
                sentimentScore: nil, impactScore: nil, freshnessScore: nil,
                credibilityScore: nil, catalystScore: nil,
                sentimentDetails: [], impactDetails: [], freshnessDetails: [],
                credibilityDetails: [], catalystDetails: [],
                summary: "[\(symbol)] Haber yok — analiz edilmedi",
                highlights: [],
                warnings: ["Haber kaynağı boş"],
                validSectionCount: 0,
                keyHeadlines: [],
                catalysts: []
            )
            return empty
        }

        let (sentScore, sentDetails) = analyzeSentiment(news: news)
        let (impactScore, impactDetails) = analyzeImpact(news: news)
        let (freshScore, freshDetails) = analyzeFreshness(news: news)
        let (credScore, credDetails) = analyzeCredibility(news: news)
        let (catScore, catDetails, catalysts) = analyzeCatalyst(news: news)

        let candidateSections: [(label: String, score: Double?, weight: Double)] = [
            ("Hissiyat",      sentScore,   0.30),
            ("Etki",          impactScore, 0.25),
            ("Tazelik",       freshScore,  0.15),
            ("Güvenilirlik",  credScore,   0.15),
            ("Tetikleyici",   catScore,    0.15)
        ]
        let validSections = candidateSections.compactMap { (lbl, s, w) -> (String, Double, Double)? in
            guard let s = s else { return nil }
            return (lbl, s, w)
        }
        let missingLabels = candidateSections.filter { $0.score == nil }.map { $0.label }

        var warnings: [String] = []
        var highlights: [String] = []
        let totalScore: Double
        if validSections.count < 2 {
            totalScore = 50.0
            warnings.append("⚠️ Haber verisi yetersiz: 5 bölümden \(validSections.count). Skor 50 nötr.")
        } else {
            let totalWeight = validSections.reduce(0.0) { $0 + $1.2 }
            let weightedSum = validSections.reduce(0.0) { $0 + $1.1 * $1.2 }
            totalScore = weightedSum / totalWeight
            if !missingLabels.isEmpty {
                warnings.append("ℹ️ Skor \(validSections.count)/5 bölümle hesaplandı. Eksik: \(missingLabels.joined(separator: ", "))")
            }
        }

        for (lbl, s, _) in validSections where s >= 75 { highlights.append("\(lbl) güçlü olumlu (\(Int(s)))") }
        for (lbl, s, _) in validSections where s <= 25 { warnings.append("\(lbl) güçlü olumsuz (\(Int(s)))") }

        let summary: String
        if totalScore >= 70       { summary = "[\(symbol)] Haber tablo olumlu (\(Int(totalScore)))" }
        else if totalScore >= 55  { summary = "[\(symbol)] Haber tablo nötr-üstü (\(Int(totalScore)))" }
        else if totalScore >= 45  { summary = "[\(symbol)] Haber tablo nötr (\(Int(totalScore)))" }
        else if totalScore >= 30  { summary = "[\(symbol)] Haber tablo nötr-altı (\(Int(totalScore)))" }
        else                       { summary = "[\(symbol)] Haber tablo olumsuz (\(Int(totalScore)))" }

        let trace = validSections.map { "\($0.0)=\(Int($0.1))" }.joined(separator: " ")
        ArgusLogger.info(.hermes, "V2 \(symbol) total=\(Int(totalScore)) (\(validSections.count)/5 bölüm) \(trace)")

        let keyHeadlines = news.articles.prefix(5).map { $0.headline }

        let result = HermesV2Result(
            symbol: symbol,
            totalScore: min(100, max(0, totalScore)),
            sentimentScore: sentScore,
            impactScore: impactScore,
            freshnessScore: freshScore,
            credibilityScore: credScore,
            catalystScore: catScore,
            sentimentDetails: sentDetails,
            impactDetails: impactDetails,
            freshnessDetails: freshDetails,
            credibilityDetails: credDetails,
            catalystDetails: catDetails,
            summary: summary,
            highlights: highlights,
            warnings: warnings,
            validSectionCount: validSections.count,
            keyHeadlines: Array(keyHeadlines),
            catalysts: catalysts
        )

        cache[symbol] = (result, Date())
        return result
    }

    // MARK: - Section: Hissiyat (aggregated sentiment)

    private func analyzeSentiment(news: HermesNewsSnapshot) -> (Double?, [String]) {
        guard let aggregate = news.aggregatedSentiment else {
            return (nil, ["Hissiyat hesaplanamadı (insights boş)"])
        }
        // aggregate: -1.0 (strong neg) — +1.0 (strong pos)
        // Skor: -1 → 0, 0 → 50, +1 → 100
        let s = ((aggregate + 1.0) / 2.0) * 100.0
        return (s, [
            "Toplu hissiyat: \(String(format: "%+.2f", aggregate)) (-1..+1)",
            "Skor: \(Int(s))"
        ])
    }

    // MARK: - Section: Etki (impact magnitude)

    private func analyzeImpact(news: HermesNewsSnapshot) -> (Double?, [String]) {
        guard !news.insights.isEmpty else { return (nil, ["Etki hesabı için insight yok"]) }
        // ImpactScore field: insight.impactScore (0-100)
        let avgImpact = news.insights.map { $0.impactScore }.reduce(0, +) / Double(news.insights.count)
        // 50'ye uzaklık = etki büyüklüğü; bullish/bearish yön sentiment ile eşleşmiş kabul edilir
        // Etki ~50 = nötr, > 65 veya < 35 = anlamlı etki
        let distance = abs(avgImpact - 50.0)
        // Mesafe büyükse "gürültülü ama etkili" — skor sentiment yönüyle uyumlu mu?
        // Burada etkinin "büyüklüğünü" döndürüyoruz, yön sentiment'te.
        // Skor: nötr veya hafif → 50, anlamlı → 65-85
        let s: Double
        if distance > 30      { s = 85 }   // Yüksek etki
        else if distance > 15 { s = 70 }   // Orta etki
        else if distance > 5  { s = 55 }   // Düşük etki
        else                   { s = 45 }   // İhmal edilebilir
        return (s, [
            "Ortalama etki: \(Int(avgImpact))/100",
            "50'den uzaklık: \(Int(distance)) (büyüklük)",
            "Skor: \(Int(s))"
        ])
    }

    // MARK: - Section: Tazelik (recent vs old)

    private func analyzeFreshness(news: HermesNewsSnapshot) -> (Double?, [String]) {
        guard !news.articles.isEmpty else { return (nil, ["Tazelik için article yok"]) }
        let now = Date()
        let ages = news.articles.map { now.timeIntervalSince($0.publishedAt) / 3600.0 }  // Hours
        let avgAge = ages.reduce(0, +) / Double(ages.count)

        let s: Double
        if avgAge < 6        { s = 90 }   // 6 saat içinde
        else if avgAge < 24  { s = 75 }   // Günlük taze
        else if avgAge < 72  { s = 55 }   // 3 günlük
        else if avgAge < 168 { s = 35 }   // Haftalık
        else                  { s = 20 }   // Eski

        return (s, [
            "Ortalama yaş: \(String(format: "%.1f", avgAge)) saat",
            "Skor: \(Int(s))"
        ])
    }

    // MARK: - Section: Güvenilirlik (kaynak)

    private func analyzeCredibility(news: HermesNewsSnapshot) -> (Double?, [String]) {
        guard !news.articles.isEmpty else { return (nil, ["Güvenilirlik için article yok"]) }
        let avgRel = news.articles.map { $0.sourceReliability }.reduce(0, +) / Double(news.articles.count)
        // sourceReliability 0-1; *100 ile skor üret
        let s = avgRel * 100.0
        return (s, [
            "Ortalama kaynak güveni: \(String(format: "%.2f", avgRel))",
            "Skor: \(Int(s))"
        ])
    }

    // MARK: - Section: Tetikleyici (M&A, earnings, upgrade)

    private func analyzeCatalyst(news: HermesNewsSnapshot) -> (Double?, [String], [String]) {
        var catalysts: [String] = []
        if news.hasUpgrade { catalysts.append("Hedef yükseltme") }
        if news.hasDowngrade { catalysts.append("Hedef düşürme") }
        if news.hasDividendAnnouncement { catalysts.append("Temettü duyurusu") }
        if news.hasEarnings { catalysts.append("Kazanç haberi") }
        if news.hasMergersAcquisitions { catalysts.append("Birleşme/Satın alma") }

        if catalysts.isEmpty {
            return (40, ["Belirgin tetikleyici yok (skor 40 nötr-altı)"], [])
        }

        // Catalyst sayısı * 15 + base 50, max 95
        let s = min(95.0, 50.0 + Double(catalysts.count) * 15.0)
        // Negatif tetikleyiciler (downgrade) skoru aşağıya çekmeli
        let negativeCount = (news.hasDowngrade ? 1 : 0)
        let adjusted = s - Double(negativeCount) * 20.0

        return (max(10, adjusted), [
            "Tetikleyiciler: \(catalysts.joined(separator: ", "))",
            "Skor: \(Int(adjusted))"
        ], catalysts)
    }
}
