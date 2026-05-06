import Foundation

// MARK: - Sirkiye Aether Engine
/// Türkiye Makro Zeka Merkezi
/// EVDS/TCMB verilerini analiz ederek Türkiye ekonomisinin nabzını tutar
/// BIST yatırım kararlarını güçlendirir

actor SirkiyeAetherEngine {
    static let shared = SirkiyeAetherEngine()
    
    private init() {}

    // MARK: - Sonuç Cache
    // TradeBrainExecutor her 60 saniyede bir analyze() çağırıyor.
    // TCMB verisi 20 dakika cached olsa da analiz hesapları her seferinde tekrar çalışıyor.
    // 5 dakikalık sonuç cache'i gereksiz CPU kullanımını önler.
    private var cachedScore: TurkeyMacroScore? = nil
    private var cacheTimestamp: Date = .distantPast
    private let resultCacheTTL: TimeInterval = 5 * 60  // 5 dakika

    // MARK: - Türkiye Makro Skoru
    
    struct TurkeyMacroScore: Sendable {
        let overallScore: Double           // 0-100 Genel Türkiye Skoru
        let monetaryStance: PolicyStance   // Para politikası duruşu
        let growthMomentum: Momentum       // Büyüme ivmesi
        let externalRisk: RiskLevel        // Dış kırılganlık
        let inflationPressure: Pressure    // Enflasyon baskısı
        
        let components: [ScoreComponent]   // Detay bileşenler
        let insights: [String]             // AI yorumları
        let timestamp: Date
        
        static let empty = TurkeyMacroScore(
            overallScore: 50,
            monetaryStance: .neutral,
            growthMomentum: .stable,
            externalRisk: .medium,
            inflationPressure: .medium,
            components: [],
            insights: ["Veri bekleniyor..."],
            timestamp: Date()
        )
        
        /// Risk seviyesi (yatırım kararları için)
        var investmentRisk: InvestmentRisk {
            if overallScore >= 70 { return .low }
            if overallScore >= 50 { return .moderate }
            if overallScore >= 30 { return .elevated }
            return .high
        }
    }
    
    struct ScoreComponent: Sendable, Identifiable {
        var id: String { name }
        let name: String
        let value: Double
        let score: Double      // 0-100
        let weight: Double     // Ağırlık
        let trend: Trend
        let icon: String
    }
    
    // MARK: - Enums
    
    enum PolicyStance: String, Sendable {
        case tight = "Sıkı"
        case neutral = "Nötr"
        case loose = "Gevşek"
        
        var color: String {
            switch self {
            case .tight: return "green"
            case .neutral: return "yellow"
            case .loose: return "red"
            }
        }
    }
    
    enum Momentum: String, Sendable {
        case accelerating = "Hızlanıyor"
        case stable = "Stabil"
        case decelerating = "Yavaşlıyor"
        
        var icon: String {
            switch self {
            case .accelerating: return "arrow.up.right"
            case .stable: return "arrow.right"
            case .decelerating: return "arrow.down.right"
            }
        }
    }
    
    enum RiskLevel: String, Sendable {
        case low = "Düşük"
        case medium = "Orta"
        case high = "Yüksek"
        case critical = "Kritik"
        
        var color: String {
            switch self {
            case .low: return "green"
            case .medium: return "yellow"
            case .high: return "orange"
            case .critical: return "red"
            }
        }
    }
    
    enum Pressure: String, Sendable {
        case low = "Düşük"
        case medium = "Orta"
        case high = "Yüksek"
        case severe = "Şiddetli"
    }
    
    enum Trend: String, Sendable {
        case up = "Yükseliyor"
        case stable = "Stabil"
        case down = "Düşüyor"
        
        var icon: String {
            switch self {
            case .up: return "arrow.up"
            case .stable: return "minus"
            case .down: return "arrow.down"
            }
        }
    }
    
    enum InvestmentRisk: String, Sendable {
        case low = "Düşük Risk"
        case moderate = "Orta Risk"
        case elevated = "Yüksek Risk"
        case high = "Çok Yüksek Risk"
        
        var recommendation: String {
            switch self {
            case .low: return "Agresif pozisyon alınabilir"
            case .moderate: return "Normal pozisyon boyutu"
            case .elevated: return "Pozisyon küçültülmeli"
            case .high: return "Nakit ağırlıklı ol"
            }
        }
    }
    
    // MARK: - Ana Analiz
    
    func analyze(forceRefresh: Bool = false) async -> TurkeyMacroScore {
        // Sonuç cache'i — forceRefresh yoksa ve TTL dolmamışsa direk döndür
        if !forceRefresh,
           let cached = cachedScore,
           Date().timeIntervalSince(cacheTimestamp) < resultCacheTTL {
            return cached
        }

        let snapshot = await TCMBDataService.shared.getMacroSnapshot(forceRefresh: forceRefresh)

        // 2026-05-05 (Round 4) FIX: Eski sürüm 6 component'in hepsini default değerlerle
        // garanti edip skor üretiyordu (veri yoksa bile sahte ~58 skor). Artık her
        // component snapshot'taki gerçek field nil ise nil dönüyor; analyze() bunları
        // filtreleyip ağırlıkları normalize ediyor. Yetersiz component sayısında
        // (< 3) `TurkeyMacroScore.empty` döndürülüp UI'a "veri yetersiz" sinyali gider.

        // Component listesi (nil = veri yok)
        let candidateComponents: [(label: String, component: ScoreComponent?)] = [
            ("Enflasyon", analyzeInflation(snapshot)),
            ("Kur Stabilitesi", analyzeFXStability(snapshot)),
            ("Reel Faiz", analyzeInterestRates(snapshot)),
            ("Büyüme", analyzeGrowth(snapshot)),
            ("Cari Denge", analyzeExternalBalance(snapshot)),
            ("MB Rezervleri", analyzeReserves(snapshot))
        ]
        let components = candidateComponents.compactMap { $0.component }
        let missingLabels = candidateComponents.filter { $0.component == nil }.map { $0.label }

        var insights: [String] = []

        // Yeterlilik kontrolü: en az 3 component olmadan güvenilir skor üretemez
        guard components.count >= 3 else {
            print("⚠️ SirkiyeAether: Sadece \(components.count) bileşen mevcut, skor güvenilir değil. Eksik: \(missingLabels.joined(separator: ", "))")
            insights.append("⚠️ Veri yetersiz: \(components.count)/6 bileşen mevcut")
            if !missingLabels.isEmpty {
                insights.append("Eksik bileşenler: \(missingLabels.joined(separator: ", "))")
            }
            insights.append("TCMB EVDS API key'ini Settings'ten girmek bu eksikleri kapatabilir")
            let emptyResult = TurkeyMacroScore(
                overallScore: 50,
                monetaryStance: .neutral,
                growthMomentum: .stable,
                externalRisk: .medium,
                inflationPressure: .medium,
                components: components,  // Eldeki bileşenleri yine göster (UI debug için)
                insights: insights,
                timestamp: Date()
            )
            cachedScore = emptyResult
            cacheTimestamp = Date()
            Task { await StaleDataRegistry.shared.touch("aether.turkey") }
            return emptyResult
        }

        // Ağırlıklı toplam — yalnız mevcut bileşenler üstünden, ağırlıklar normalize edilir
        let totalWeight = components.reduce(0.0) { $0 + $1.weight }
        let totalWeightedScore = components.reduce(0.0) { $0 + $1.score * $1.weight }
        let overallScore = totalWeight > 0 ? totalWeightedScore / totalWeight : 50

        // Eksik bileşen varsa kullanıcıya görünür şekilde uyarı ver
        if !missingLabels.isEmpty {
            insights.append("ℹ️ Skor \(components.count)/6 bileşen ile hesaplandı. Eksik: \(missingLabels.joined(separator: ", "))")
        }

        // Durum Belirleme (snapshot'tan, kendi nil-handling'leri var)
        let monetaryStance = determineMonetaryStance(snapshot)
        let growthMomentum = determineGrowthMomentum(snapshot)
        let externalRisk = determineExternalRisk(snapshot)
        let inflationPressure = determineInflationPressure(snapshot)

        // Standart Insight'lar
        let standardInsights = generateInsights(
            score: overallScore,
            snapshot: snapshot,
            monetaryStance: monetaryStance,
            growthMomentum: growthMomentum,
            externalRisk: externalRisk
        )
        insights.append(contentsOf: standardInsights)

        // Score trace (P3-6)
        let traceParts = components.map { "\($0.name)=\(Int($0.score))" }.joined(separator: " ")
        print("[SirkiyeAether] components=[\(traceParts)] weights=\(String(format: "%.2f", totalWeight)) → final=\(Int(overallScore))")

        let result = TurkeyMacroScore(
            overallScore: min(100, max(0, overallScore)),
            monetaryStance: monetaryStance,
            growthMomentum: growthMomentum,
            externalRisk: externalRisk,
            inflationPressure: inflationPressure,
            components: components,
            insights: insights,
            timestamp: Date()
        )
        cachedScore = result
        cacheTimestamp = Date()
        // Tazelik sicili: UI rozeti + diğer motorların stale-aware davranışı için
        Task { await StaleDataRegistry.shared.touch("aether.turkey") }
        return result
    }
    
    // MARK: - Bileşen Analizleri
    
    // 2026-05-05 (Round 4) FIX: Eski sürümde her bileşen `?? defaultValue` ile sahte
    // skor üretiyordu (inflation ?? 50 → score 40, usdTry ?? 35 → score 65, vb.). Sonuç:
    // TCMB API key yokken bile sistem ~58 stable skor üretiyor → kullanıcı UI'da
    // "her şey yolunda" sanıyor. Şimdi her component snapshot'taki gerçek field
    // nil ise `nil` dönüyor; analyze() bunları filtreleyip ağırlıkları normalize ediyor.

    private func analyzeInflation(_ snapshot: TCMBDataService.TCMBMacroSnapshot) -> ScoreComponent? {
        guard let inflation = snapshot.inflation else { return nil }

        let score: Double
        if inflation < 10 { score = 100 }
        else if inflation < 20 { score = 80 }
        else if inflation < 40 { score = 60 }
        else if inflation < 60 { score = 40 }
        else if inflation < 80 { score = 20 }
        else { score = 10 }

        // Trend (core vs headline karşılaştırması)
        let trend: Trend
        if let core = snapshot.coreInflation {
            if core < inflation - 5 { trend = .down }
            else if core > inflation + 5 { trend = .up }
            else { trend = .stable }
        } else {
            trend = .stable
        }

        return ScoreComponent(
            name: "Enflasyon",
            value: inflation,
            score: score,
            weight: 0.25,
            trend: trend,
            icon: "percent"
        )
    }

    private func analyzeFXStability(_ snapshot: TCMBDataService.TCMBMacroSnapshot) -> ScoreComponent? {
        guard let usdTry = snapshot.usdTry else { return nil }

        // Kur seviye-temelli (statik) — gerçekte volatilite hesaplanmalı (TODO: yıllık std dev)
        // Eşikler 2025-2026 referans aralığında ayarlandı; üretim sırasında güncellenmesi gerekebilir
        let score: Double
        if usdTry < 30 { score = 80 }
        else if usdTry < 35 { score = 65 }
        else if usdTry < 40 { score = 50 }
        else if usdTry < 45 { score = 35 }
        else { score = 20 }

        return ScoreComponent(
            name: "Kur Stabilitesi",
            value: usdTry,
            score: score,
            weight: 0.20,
            trend: .stable,
            icon: "dollarsign.circle"
        )
    }

    private func analyzeInterestRates(_ snapshot: TCMBDataService.TCMBMacroSnapshot) -> ScoreComponent? {
        guard let realRate = snapshot.realInterestRate else { return nil }

        let score: Double
        let trend: Trend
        if realRate > 10 { score = 90; trend = .up }
        else if realRate > 5 { score = 75; trend = .up }
        else if realRate > 0 { score = 60; trend = .stable }
        else if realRate > -10 { score = 40; trend = .down }
        else { score = 20; trend = .down }

        return ScoreComponent(
            name: "Reel Faiz",
            value: realRate,
            score: score,
            weight: 0.20,
            trend: trend,
            icon: "banknote"
        )
    }

    private func analyzeGrowth(_ snapshot: TCMBDataService.TCMBMacroSnapshot) -> ScoreComponent? {
        guard let gdp = snapshot.gdpGrowth else { return nil }

        let score: Double
        let trend: Trend
        if gdp > 5 { score = 90; trend = .up }
        else if gdp > 3 { score = 70; trend = .up }
        else if gdp > 0 { score = 50; trend = .stable }
        else if gdp > -3 { score = 30; trend = .down }
        else { score = 10; trend = .down }

        return ScoreComponent(
            name: "Büyüme",
            value: gdp,
            score: score,
            weight: 0.15,
            trend: trend,
            icon: "chart.line.uptrend.xyaxis"
        )
    }

    private func analyzeExternalBalance(_ snapshot: TCMBDataService.TCMBMacroSnapshot) -> ScoreComponent? {
        guard let currentAccount = snapshot.currentAccount else { return nil }

        let score: Double
        if currentAccount > 0 { score = 90 }
        else if currentAccount > -10 { score = 70 }
        else if currentAccount > -30 { score = 50 }
        else if currentAccount > -50 { score = 30 }
        else { score = 15 }

        return ScoreComponent(
            name: "Cari Denge",
            value: currentAccount,
            score: score,
            weight: 0.10,
            trend: currentAccount > -20 ? .up : .down,
            icon: "arrow.left.arrow.right"
        )
    }

    private func analyzeReserves(_ snapshot: TCMBDataService.TCMBMacroSnapshot) -> ScoreComponent? {
        guard let reserves = snapshot.reserves else { return nil }

        let score: Double
        if reserves > 150 { score = 90 }
        else if reserves > 120 { score = 70 }
        else if reserves > 90 { score = 50 }
        else if reserves > 60 { score = 30 }
        else { score = 15 }

        return ScoreComponent(
            name: "MB Rezervleri",
            value: reserves,
            score: score,
            weight: 0.10,
            trend: reserves > 100 ? .up : .down,
            icon: "building.columns"
        )
    }
    
    // MARK: - Durum Belirleme
    
    private func determineMonetaryStance(_ snapshot: TCMBDataService.TCMBMacroSnapshot) -> PolicyStance {
        guard let realRate = snapshot.realInterestRate else { return .neutral }
        
        if realRate > 5 { return .tight }
        if realRate < -5 { return .loose }
        return .neutral
    }
    
    private func determineGrowthMomentum(_ snapshot: TCMBDataService.TCMBMacroSnapshot) -> Momentum {
        guard let gdp = snapshot.gdpGrowth else { return .stable }
        
        if gdp > 4 { return .accelerating }
        if gdp < 1 { return .decelerating }
        return .stable
    }
    
    private func determineExternalRisk(_ snapshot: TCMBDataService.TCMBMacroSnapshot) -> RiskLevel {
        let currentAccount = snapshot.currentAccount ?? -30
        let reserves = snapshot.reserves ?? 100
        
        // Cari açık yüksek ve rezervler düşükse risk yüksek
        if currentAccount < -40 && reserves < 80 { return .critical }
        if currentAccount < -30 && reserves < 100 { return .high }
        if currentAccount < -20 { return .medium }
        return .low
    }
    
    private func determineInflationPressure(_ snapshot: TCMBDataService.TCMBMacroSnapshot) -> Pressure {
        guard let inflation = snapshot.inflation else { return .medium }
        
        if inflation > 60 { return .severe }
        if inflation > 40 { return .high }
        if inflation > 20 { return .medium }
        return .low
    }
    
    // MARK: - Insight Üretimi
    
    private func generateInsights(
        score: Double,
        snapshot: TCMBDataService.TCMBMacroSnapshot,
        monetaryStance: PolicyStance,
        growthMomentum: Momentum,
        externalRisk: RiskLevel
    ) -> [String] {
        var insights: [String] = []

        if score >= 70 {
            insights.append("Makro görünüm olumlu. Risk iştahı destekleniyor.")
        } else if score >= 50 {
            insights.append("Makro görünüm dengeli. Seçici pozisyonlama öne çıkıyor.")
        } else if score >= 30 {
            insights.append("Makro riskler artmış durumda. Defansif duruş korunmalı.")
        } else {
            insights.append("Makro görünüm zayıf. Nakit ve risk yönetimi öncelikli olmalı.")
        }

        if let realRate = snapshot.realInterestRate {
            if realRate > 5 {
                insights.append("Reel faiz güçlü pozitif (%\(String(format: "%.1f", realRate))). TL varlıklar destek bulabilir.")
            } else if realRate < 0 {
                insights.append("Reel faiz negatif (%\(String(format: "%.1f", realRate))). Koruma amaçlı dağılım önemli.")
            }
        }

        if monetaryStance == .tight {
            insights.append("Sıkı para politikası finansal hisseleri göreceli olarak destekleyebilir.")
        }

        if externalRisk == .high || externalRisk == .critical {
            insights.append("Dış kırılganlık yüksek. Döviz geliri güçlü şirketler görece dirençli kalabilir.")
        }

        if let inflation = snapshot.inflation {
            insights.append("Yıllık enflasyon: %\(String(format: "%.1f", inflation)).")
        }

        return insights
    }
}
