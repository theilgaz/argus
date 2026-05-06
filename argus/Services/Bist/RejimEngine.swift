import Foundation
import SwiftUI

/// REJİM: Birleşik Makro/Piyasa Modü
/// Sirkiye (Makro) + Oracle (Sinyalleri) + Sektör Rotasyonu

// MARK: - Types

enum SymbolType {
    case bist
    case global
}

enum RejimSignal: String, Sendable {
    case riskOn = "RISK-ON"
    case riskOff = "RISK-OFF"
    case neutral = "NEUTRAL"
    
    var color: String {
        switch self {
        case .riskOn: return "green"
        case .neutral: return "yellow"
        case .riskOff: return "red"
        }
    }
    
    var icon: String {
        switch self {
        case .riskOn: return "arrow.up.circle.fill"
        case .neutral: return "pause.circle"
        case .riskOff: return "arrow.down.circle.fill"
        }
    }
}

struct RejimResult: Sendable {
    let symbol: String
    let signal: RejimSignal
    let confidence: Double
    let sirkiyeScore: Double
    let oracleScore: Double
    let sectorScore: Double
    let macroRegime: MacroRegime
    let summary: String
    let timestamp: Date
    
    enum MacroRegime: String, Sendable {
        case expansion = "EXPANSION"
        case peak = "PEAK"
        case recession = "RECESSION"
        case contraction = "CONTRACTION"
        case recovery = "RECOVERY"
        
        var color: Color {
            switch self {
            case .expansion: return .green
            case .peak: return .orange
            case .recession: return .red
            case .contraction: return .purple
            case .recovery: return .mint
            }
        }
        
        var description: String {
            switch self {
            case .expansion: return "Büyüme fazı"
            case .peak: return "zirve noktası"
            case .recession: return "düşüş fazı"
            case .contraction: return "daralma"
            case .recovery: return "toparlanma"
            }
        }
    }
}

// MARK: - Main Engine

actor RejimEngine {
    static let shared = RejimEngine()
    private init() {}
    
    // MARK: - Main Analysis
    
    func analyze(symbol: String) async throws -> RejimResult {
        let cleanSymbol = symbol.uppercased()
        
        // MARK: - Symbol Type Detection
        let symbolType: SymbolType
        if cleanSymbol.hasSuffix(".IS") || cleanSymbol.hasSuffix("-IS") {
            symbolType = .bist
        } else {
            symbolType = .global
        }
        
        // MARK: - Sirkiye Makro (sadece BIST için)
        var sirkiyeScore: Double = 50.0
        
        if symbolType == .bist {
            do {
                // 2026-05-05 (Round 4): foreignFlow + general TR news (sembol-spesifik news yetersizse)
                async let foreignFlowTask = ForeignInvestorFlowService.shared.getMarketForeignSentiment()
                async let symbolNewsTask = getNewsSnapshot(symbol: cleanSymbol)
                async let trGeneralNewsTask = SirkiyeNewsHelper.snapshotForTurkey()

                let symbolNews = await symbolNewsTask
                // Sembol-spesifik insight'lar boşsa veya çok azsa Türkiye geneline düş
                let news = (symbolNews?.insights.count ?? 0) >= 2
                    ? symbolNews
                    : await trGeneralNewsTask

                let input = SirkiyeEngine.SirkiyeInput(
                    usdTry: await getUSDTry(),
                    usdTryPrevious: await getUSDTryPrevious(),
                    dxy: await getDXY(),
                    brentOil: await getBrentOil(),
                    globalVix: await getGlobalVIX(),
                    newsSnapshot: news,
                    foreignFlowScore: await foreignFlowTask
                )
                let sirkiyeResult = try await SirkiyeEngine.shared.analyze(input: input)
                sirkiyeScore = sirkiyeResult.netSupport * 100.0
            } catch {
                print("⚠️ RejimEngine: Sirkiye analizi başarısız: \(error)")
            }
        }
        
        // MARK: - Oracle Sinyalleri (özellikle BIST için)
        var oracleScore: Double = 50.0
        
        if symbolType == .bist {
            let signals = await OracleEngine.shared.getSignals(for: cleanSymbol)
            if !signals.isEmpty {
                let buySignals = signals.filter { $0.sentiment == .bullish }.count
                let sellSignals = signals.filter { $0.sentiment == .bearish }.count
                let effectValues = signals
                    .flatMap { $0.effects }
                    .map(\.scoreImpact)
                let meanImpact = effectValues.isEmpty
                    ? 0
                    : effectValues.reduce(0, +) / Double(effectValues.count)
                let sentimentTilt = Double(buySignals - sellSignals) * 6.0
                oracleScore = max(0, min(100, 50 + (meanImpact * 1.2) + sentimentTilt))
            }
        }
        
        // MARK: - Sektör Rotasyonu
        var sectorScore: Double = 50.0
        
        if symbolType == .bist {
            do {
                let sectorResult = try await BistSektorEngine.shared.analyze(symbol: cleanSymbol)
                sectorScore = sectorResult.score
            } catch {
                print("⚠️ RejimEngine: Sektör analizi başarısız: \(error)")
            }
        }
        
        // MARK: - Makro Regime Tespiti
        let regime = detectMacroRegime(
            sirkiyeScore: sirkiyeScore,
            oracleScore: oracleScore,
            sectorScore: sectorScore
        )
        
        // MARK: - Birleşik Skor
        let totalScore = (sirkiyeScore * 0.4) + (oracleScore * 0.35) + (sectorScore * 0.25)
        
        // MARK: - Sinyal Belirleme
        let signal: RejimSignal
        if totalScore >= 70 {
            signal = .riskOn
        } else if totalScore <= 30 {
            signal = .riskOff
        } else {
            signal = .neutral
        }
        
        // MARK: - Özet
        let summary = generateSummary(
            symbolType: symbolType,
            sirkiyeScore: sirkiyeScore,
            oracleScore: oracleScore,
            sectorScore: sectorScore,
            totalScore: totalScore,
            regime: regime
        )
        
        // 2026-05-05 (Round 4) P3-6: Score trace
        print("[RejimEngine] \(cleanSymbol) sirkiye=\(Int(sirkiyeScore)) oracle=\(Int(oracleScore)) sektor=\(Int(sectorScore)) → total=\(Int(totalScore)) signal=\(signal) regime=\(regime)")

        return RejimResult(
            symbol: cleanSymbol,
            signal: signal,
            confidence: totalScore,
            sirkiyeScore: sirkiyeScore,
            oracleScore: oracleScore,
            sectorScore: sectorScore,
            macroRegime: regime,
            summary: summary,
            timestamp: Date()
        )
    }
    
    // MARK: - Makro Regime Detection
    
    private func detectMacroRegime(
        sirkiyeScore: Double,
        oracleScore: Double,
        sectorScore: Double
    ) -> RejimResult.MacroRegime {
        let marketScore = sirkiyeScore * 0.4 + oracleScore * 0.35
        let leadingScore = sectorScore * 0.25
        
        if sirkiyeScore >= 70 && oracleScore >= 70 {
            return .expansion
        } else if sirkiyeScore <= 30 || oracleScore <= 30 {
            return .recession
        } else if marketScore >= 70 && leadingScore >= 70 {
            return .peak
        } else if sirkiyeScore < 50 {
            return .contraction
        } else {
            return .recovery
        }
    }
    
    // MARK: - Özet Oluşturma
    
    private func generateSummary(
        symbolType: SymbolType,
        sirkiyeScore: Double,
        oracleScore: Double,
        sectorScore: Double,
        totalScore: Double,
        regime: RejimResult.MacroRegime
    ) -> String {
        var parts = [String]()
        
        if symbolType == .bist {
            parts.append("BIST Analizi:")
        } else {
            parts.append("Global Analizi:")
        }
        
        // Sirkiye durumu
        if sirkiyeScore >= 70 {
            parts.append("Makro riskleri nötr.")
        } else if sirkiyeScore <= 30 {
            parts.append("Makro riskleri yüksek.")
        }
        
        // Oracle durumu
        if oracleScore >= 70 {
            parts.append("Oracle sinyalleri pozitif.")
        } else if oracleScore <= 30 {
            parts.append("Oracle sinyalleri negatif.")
        }
        
        // Sektör durumu
        if sectorScore >= 70 {
            parts.append("Sektör performansı güçlü.")
        } else if sectorScore <= 30 {
            parts.append("Sektör performansı zayıf.")
        }
        
        // Makro rejimi
        parts.append("Makro rejimi: \(regime.description)")
        
        return parts.joined(separator: " | ")
    }
    
    // MARK: - Helper Functions
    
    private func getUSDTry() async -> Double {
        // 2026-05-05 (Round 4): BorsaPy primary, Heimdall fallback. Eski sürüm yalnız
        // HeimdallOrchestrator kullanıyordu — Yahoo USD/TRY zayıf, sık fail veriyordu.
        // BorsaPy daha hızlı ve güvenilir; Render'da çalışıyor.
        if let fx = try? await BorsaPyProvider.shared.getFXRate(asset: "USDTRY"), fx.last > 0 {
            return fx.last
        }
        if let quote = try? await HeimdallOrchestrator.shared.requestQuote(symbol: "USD/TRY"), quote.currentPrice > 0 {
            return quote.currentPrice
        }
        return 0  // Veri yok — caller fxChange hesabı yapmamalı (analyze() guard ile koruyor)
    }

    private func getUSDTryPrevious() async -> Double {
        // 2026-05-05 (Round 4) FIX: Eski sürüm `return 35.0` hardcoded. Sonuç: kur değişimi
        // hesabı her zaman 35.0 referansıyla yapılıyor → gerçek 41+ TL kuruyla bile fxChange
        // uçuk sayılar üretiyor, Sirkiye localStress skoru saçmalıyor.
        // Şimdi: BorsaPy FX endpoint'i `open` (günün açılışı) veya `previousClose` döndürüyor;
        // bu intra-day değişim için doğru referans.
        if let fx = try? await BorsaPyProvider.shared.getFXRate(asset: "USDTRY"), fx.open > 0 {
            return fx.open
        }
        // MarketDataStore Yahoo cache fallback
        if let quote = await MarketDataStore.shared.getQuote(for: "USD/TRY"),
           let prev = quote.previousClose, prev > 0 {
            return prev
        }
        // Son çare: getUSDTry() döndür (fxChange = 0 → nötr localStress, en kötü ihtimal saçma değil)
        return await getUSDTry()
    }

    private func getDXY() async -> Double {
        // 2026-05-05 (Round 4) FIX: Eski sürüm `return 104.0` hardcoded → globalScore'da
        // dolar gücü hiç oynamıyordu. MarketDataStore (Yahoo) DX-Y.NYB endeksini destekliyor.
        let dataValue = await MarketDataStore.shared.ensureQuote(symbol: "DX-Y.NYB")
        if let price = dataValue.value?.currentPrice, price > 0 {
            return price
        }
        // Heimdall fallback
        if let q = try? await HeimdallOrchestrator.shared.requestQuote(symbol: "DX-Y.NYB"), q.currentPrice > 0 {
            return q.currentPrice
        }
        return 100.0  // DXY uzun-vadeli ortalama — fallback nadiren tetiklenir
    }

    private func getBrentOil() async -> Double? {
        // 2026-05-05 (Round 4) FIX: Eski sürüm `return nil` → SirkiyeEngine globalScore'da
        // oil bloğu (line 113-116) hiç çalışmıyordu. BorsaPy /gold/BRENT endpoint'i mevcut.
        if let fx = try? await BorsaPyProvider.shared.getBrentPrice(), fx.last > 0 {
            return fx.last
        }
        // MarketDataStore Yahoo "BZ=F" (Brent) veya "CL=F" (WTI) fallback
        let dataValue = await MarketDataStore.shared.ensureQuote(symbol: "BZ=F")
        if let price = dataValue.value?.currentPrice, price > 0 {
            return price
        }
        return nil  // Veri yoksa nil — SirkiyeEngine'in oil bloğu pas geçer (mevcut nil-aware mantık)
    }

    private func getGlobalVIX() async -> Double? {
        // 2026-05-05 (Round 4) FIX: Eski sürüm `return nil` → korku indeksi yok.
        // MarketDataStore Yahoo "^VIX" sembolünü destekliyor.
        let dataValue = await MarketDataStore.shared.ensureQuote(symbol: "^VIX")
        if let price = dataValue.value?.currentPrice, price > 0 {
            return price
        }
        // Heimdall fallback
        if let q = try? await HeimdallOrchestrator.shared.requestQuote(symbol: "^VIX"), q.currentPrice > 0 {
            return q.currentPrice
        }
        return nil
    }

    private func getNewsSnapshot(symbol: String) async -> HermesNewsSnapshot? {
        // BIST sembolü için sembol-spesifik haber snapshot'ı
        if let payload = try? await BISTSentimentEngine.shared.analyzeSentimentPayload(for: symbol) {
            return BISTSentimentAdapter.adapt(result: payload.result, articles: payload.articles)
        }
        return nil
    }
}
