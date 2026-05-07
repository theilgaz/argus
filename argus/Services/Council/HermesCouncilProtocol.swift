import Foundation

// MARK: - Hermes Council Protocol & Models
// The News Council - evaluates news and sentiment impact
// Uses existing NewsArticle and NewsSentiment from NewsModels.swift

// MARK: - News Council Member Protocol

protocol NewsCouncilMember: Sendable {
    var id: String { get }
    var name: String { get }
    
    func analyze(news: HermesNewsSnapshot, symbol: String) async -> HermesNewsProposal?
    func vote(on proposal: HermesNewsProposal, news: HermesNewsSnapshot) -> HermesNewsVote
}

// MARK: - Hermes News Snapshot (Input Data)

struct HermesNewsSnapshot: Sendable, Codable {
    let symbol: String
    let timestamp: Date
    
    // News insights (analyzed)
    let insights: [NewsInsight]
    
    // Raw articles
    let articles: [NewsArticle]
    
    // Aggregated sentiment
    var aggregatedSentiment: Double? {
        guard !insights.isEmpty else { return nil }
        var sum = 0.0
        for insight in insights {
            switch insight.sentiment {
            case .strongPositive: sum += 1.0
            case .weakPositive: sum += 0.5
            case .neutral: sum += 0.0
            case .weakNegative: sum -= 0.5
            case .strongNegative: sum -= 1.0
            }
        }
        return sum / Double(insights.count)
    }
    
    var avgConfidence: Double {
        guard !insights.isEmpty else { return 0 }
        return insights.map { $0.confidence }.reduce(0, +) / Double(insights.count)
    }
    
    // Catalyst detection from headlines
    var hasUpgrade: Bool {
        articles.contains { $0.headline.lowercased().contains("upgrade") || $0.headline.contains("yükselt") }
    }
    
    var hasDowngrade: Bool {
        articles.contains { $0.headline.lowercased().contains("downgrade") || $0.headline.contains("düşür") }
    }
    
    var hasDividendAnnouncement: Bool {
        articles.contains { $0.headline.lowercased().contains("dividend") || $0.headline.contains("temettü") }
    }
    
    var hasEarnings: Bool {
        articles.contains { $0.headline.lowercased().contains("earnings") || $0.headline.contains("kazanç") }
    }
    
    var hasMergersAcquisitions: Bool {
        articles.contains { 
            $0.headline.lowercased().contains("merger") || 
            $0.headline.lowercased().contains("acquisition") ||
            $0.headline.contains("birleşme") || 
            $0.headline.contains("satın al")
        }
    }
    
    static func empty(symbol: String) -> HermesNewsSnapshot {
        HermesNewsSnapshot(symbol: symbol, timestamp: Date(), insights: [], articles: [])
    }

    // MARK: - Cache-Based Factory

    /// Mevcut cache'lerden (HermesNewsViewModel + HermesEventStore) sembol için
    /// HermesNewsSnapshot üretir. Watchlist refresh'leri sırasında dolan verileri
    /// kullanır — yeni fetch tetiklemez.
    /// Cache boşsa nil döner (graceful degradation).
    @MainActor
    static func fromCache(symbol: String) -> HermesNewsSnapshot? {
        let vm = HermesNewsViewModel.shared
        let insights = vm.newsInsightsBySymbol[symbol] ?? []
        let articles = vm.newsBySymbol[symbol] ?? []

        // Insight varsa doğrudan snapshot oluştur
        if !insights.isEmpty {
            return HermesNewsSnapshot(
                symbol: symbol,
                timestamp: insights.first?.createdAt ?? Date(),
                insights: insights,
                articles: articles
            )
        }

        // Insight yoksa HermesEventStore'dan event-based fallback dene.
        // Event'ler LLM analizinden geliyor, insight'a dönüştürülebilir.
        let events = HermesEventStore.shared.getEvents(for: symbol)
        let recentEvents = events.filter {
            Date().timeIntervalSince($0.publishedAt) < 24 * 3600 // Son 24 saat
        }
        guard !recentEvents.isEmpty else { return nil }

        let eventInsights: [NewsInsight] = recentEvents.prefix(10).map { event in
            NewsInsight(
                symbol: event.symbol,
                articleId: event.articleId,
                headline: event.headline,
                summaryTRLong: event.summaryTRShort ?? event.rationaleShort,
                impactSentenceTR: event.rationaleShort,
                sentiment: event.sentimentLabel ?? sentimentFromPolarity(event.polarity),
                confidence: event.confidence,
                impactScore: event.finalScore
            )
        }

        return HermesNewsSnapshot(
            symbol: symbol,
            timestamp: recentEvents.first?.publishedAt ?? Date(),
            insights: eventInsights,
            articles: articles
        )
    }

    /// BIST sembolleri için BISTSentimentEngine cache'inden snapshot üretir.
    /// Actor-isolated olduğu için async. Cache boşsa nil döner.
    /// Yeni fetch tetiklemez — yalnızca mevcut cache verisi kullanılır.
    static func fromBistCache(symbol: String) async -> HermesNewsSnapshot? {
        // Önce standart cache'i dene (BIST haberleri de HermesNewsViewModel'e akıyor)
        let standard = await MainActor.run { fromCache(symbol: symbol) }
        if standard != nil { return standard }

        // BISTSentimentEngine actor-isolated cache'i (cache-only, fetch yok)
        let engine = BISTSentimentEngine.shared
        guard let payload = await engine.getCachedPayload(for: symbol) else {
            return nil
        }
        // BISTSentimentAdapter zaten BISTSentimentResult → HermesNewsSnapshot dönüşümü yapıyor
        let snapshot = BISTSentimentAdapter.adapt(result: payload.result, articles: payload.articles)
        guard !snapshot.insights.isEmpty else { return nil }
        return snapshot
    }

    private static func sentimentFromPolarity(_ polarity: HermesEventPolarity) -> NewsSentiment {
        switch polarity {
        case .positive: return .weakPositive
        case .negative: return .weakNegative
        case .mixed: return .neutral
        }
    }
}

// MARK: - Hermes News Proposal

struct HermesNewsProposal: Sendable, Identifiable, Codable {
    let id = UUID()
    let proposer: String
    let proposerName: String
    let sentiment: NewsSentiment
    let confidence: Double
    let reasoning: String
    let keyHeadline: String?
    let timestamp: Date = Date()
    
    var actionBias: ProposedAction {
        switch sentiment {
        case .strongPositive, .weakPositive: return .buy
        case .neutral: return .hold
        case .weakNegative, .strongNegative: return .sell
        }
    }
}

// MARK: - Hermes News Vote

struct HermesNewsVote: Sendable, Codable {
    let voter: String
    let voterName: String
    let decision: VoteDecision
    let reasoning: String?
    let weight: Double
}

// MARK: - Hermes Decision

struct HermesDecision: Sendable, Codable {
    let symbol: String
    let sentiment: NewsSentiment
    let actionBias: ProposedAction
    let netSupport: Double
    let isHighImpact: Bool
    let winningProposal: HermesNewsProposal?
    let votes: [HermesNewsVote]
    let keyHeadlines: [String]
    let catalysts: [String]
    let timestamp: Date
    
    var summary: String {
        "\(symbol) Haber: \(sentiment.rawValue) | Etki: \(isHighImpact ? "YÜKSEK" : "NORMAL")"
    }
}

// MARK: - Hermes Member Weights

struct HermesMemberWeights: Codable, Sendable {
    var sentimentMaster: Double
    var impactMaster: Double
    var timingMaster: Double
    var credibilityMaster: Double
    var catalystMaster: Double
    var updatedAt: Date
    var confidence: Double
    
    static let defaultWeights = HermesMemberWeights(
        sentimentMaster: 0.25,
        impactMaster: 0.25,
        timingMaster: 0.15,
        credibilityMaster: 0.15,
        catalystMaster: 0.20,
        updatedAt: Date(),
        confidence: 0.5
    )
    
    func weight(for memberId: String) -> Double {
        switch memberId {
        case "hermes_sentiment_master": return sentimentMaster
        case "hermes_impact_master": return impactMaster
        case "hermes_timing_master": return timingMaster
        case "hermes_credibility_master": return credibilityMaster
        case "hermes_catalyst_master": return catalystMaster
        default: return 0.1
        }
    }
}
