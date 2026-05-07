import Foundation

// MARK: - Orion BIST V2 Engine
// BIST hisseleri için section-based teknik analiz motoru.
// OrionV2Engine patternını BIST volatilite profiliyle adapte eder:
//   - RSI eşikleri 30/70 → 25/75 (BIST yüksek volatilite)
//   - TSI + SAR (OrionBistEngine'den) Trend + Momentum bölümlerine eklenir
//   - EMA 20/50/200 hizası Trend bölümünde korunur
// OrionV2Result döndürür → OrionV2DecisionAdapter direkt kullanılabilir (ek adapter gerekmez).

actor OrionBistV2Engine {
    static let shared = OrionBistV2Engine()

    private var cache: [String: OrionV2Result] = [:]
    private var cacheTimestamps: [String: Date] = [:]
    private let cacheTTL: TimeInterval = 300  // 5 dakika

    private let tsiLong  = 9
    private let tsiShort = 3
    private let sarStart = 0.02
    private let sarInc   = 0.02
    private let sarMax   = 0.2

    private init() {}

    // MARK: - Public API

    func analyze(symbol: String, candles: [Candle], forceRefresh: Bool = false) async -> OrionV2Result {
        if !forceRefresh,
           let cached = cache[symbol],
           let ts = cacheTimestamps[symbol],
           Date().timeIntervalSince(ts) < cacheTTL {
            return cached
        }

        guard candles.count >= 50 else {
            return emptyResult(symbol: symbol, reason: "Yetersiz veri (min 50 mum, mevcut \(candles.count))")
        }

        let (trendScore, trendDetails)     = analyzeTrend(candles: candles)
        let (momScore, momDetails)         = analyzeMomentum(candles: candles)
        let (volScore, volDetails)         = analyzeVolume(candles: candles)
        let (patScore, patDetails)         = analyzePattern(candles: candles)
        let (srScore, srDetails)           = analyzeSupportResistance(candles: candles)
        let (volatScore, volatDetails)     = analyzeVolatility(candles: candles)

        // Nil-aware aggregator (BIST: Trend ve Momentum daha ağırlıklı)
        let candidates: [(String, Double?, Double)] = [
            ("Trend",         trendScore,  0.30),  // BIST: trend takibi kritik
            ("Momentum",      momScore,    0.25),  // TSI + RSI kombinasyonu
            ("Hacim",         volScore,    0.15),
            ("Formasyon",     patScore,    0.10),
            ("Destek/Direnç", srScore,     0.12),
            ("Volatilite",    volatScore,  0.08),
        ]
        let valid   = candidates.compactMap { (l, s, w) -> (String, Double, Double)? in
            guard let s = s else { return nil }; return (l, s, w)
        }
        let missing = candidates.filter { $0.1 == nil }.map { $0.0 }

        var warnings: [String] = []
        let totalScore: Double
        if valid.count < 3 {
            totalScore = 50.0
            warnings.append("⚠️ Veri yetersiz: \(valid.count)/6 bölüm. Skor 50 nötr atandı.")
            if !missing.isEmpty { warnings.append("Eksik: \(missing.joined(separator: ", "))") }
        } else {
            let tw = valid.reduce(0.0) { $0 + $1.2 }
            totalScore = valid.reduce(0.0) { $0 + $1.1 * $1.2 } / tw
            if !missing.isEmpty {
                warnings.append("ℹ️ Skor \(valid.count)/6 bölümle hesaplandı. Eksik: \(missing.joined(separator: ", "))")
            }
        }

        var highlights: [String] = []
        for (lbl, s, _) in valid where s >= 75 { highlights.append("\(lbl) güçlü (\(Int(s)))") }
        for (lbl, s, _) in valid where s <= 25 { warnings.append("\(lbl) zayıf (\(Int(s)))") }

        let summary: String
        if totalScore >= 70      { summary = "[\(symbol)] BIST teknik tablo olumlu — \(Int(totalScore))/100" }
        else if totalScore >= 55 { summary = "[\(symbol)] BIST teknik tablo orta-üstü — \(Int(totalScore))/100" }
        else if totalScore >= 45 { summary = "[\(symbol)] BIST teknik tablo nötr — \(Int(totalScore))/100" }
        else if totalScore >= 30 { summary = "[\(symbol)] BIST teknik tablo orta-altı — \(Int(totalScore))/100" }
        else                     { summary = "[\(symbol)] BIST teknik tablo olumsuz — \(Int(totalScore))/100" }

        let trace = valid.map { "\($0.0)=\(Int($0.1))" }.joined(separator: " ")
        ArgusLogger.info(.orion, "BistV2 \(symbol) total=\(Int(totalScore)) (\(valid.count)/6 bölüm) \(trace)")

        let result = OrionV2Result(
            symbol: symbol,
            totalScore: min(100, max(0, totalScore)),
            trendScore: trendScore,
            momentumScore: momScore,
            volumeScore: volScore,
            patternScore: patScore,
            srScore: srScore,
            volatilityScore: volatScore,
            trendDetails: trendDetails,
            momentumDetails: momDetails,
            volumeDetails: volDetails,
            patternDetails: patDetails,
            srDetails: srDetails,
            volatilityDetails: volatDetails,
            summary: summary,
            highlights: highlights,
            warnings: warnings,
            validSectionCount: valid.count
        )
        cache[symbol] = result
        cacheTimestamps[symbol] = Date()
        return result
    }

    // MARK: - Trend (EMA hizası + TSI + SAR)

    private func analyzeTrend(candles: [Candle]) -> (Double?, [String]) {
        let closes = candles.map { $0.close }
        let highs  = candles.map { $0.high }
        let lows   = candles.map { $0.low }
        var scores: [Double] = []
        var details: [String] = []

        // EMA hizası (OrionV2 ile aynı)
        if closes.count >= 200,
           let ema20 = IndicatorService.calculateEMA(values: closes, period: 20).last as? Double,
           let ema50 = IndicatorService.calculateEMA(values: closes, period: 50).last as? Double,
           let ema200 = IndicatorService.calculateEMA(values: closes, period: 200).last as? Double {
            let align = (ema20 > ema50 ? 1 : 0) + (ema50 > ema200 ? 1 : 0)
            let s = Double(align) * 50.0
            scores.append(s)
            details.append("EMA hizası: \(align)/2 yukarı (skor \(Int(s)))")
        } else if closes.count >= 50,
                  let ema20 = IndicatorService.calculateEMA(values: closes, period: 20).last as? Double,
                  let ema50 = IndicatorService.calculateEMA(values: closes, period: 50).last as? Double {
            let s = ema20 > ema50 ? 70.0 : 30.0
            scores.append(s)
            details.append("EMA20/50: \(ema20 > ema50 ? "yukarı" : "aşağı") (skor \(Int(s)))")
        }

        // SAR (BIST trend-following — OrionBistEngine'den)
        let sarVals = calculateSAR(highs: highs, lows: lows)
        if let sar = sarVals.last, let close = closes.last {
            let sarUp = close > sar
            let s = sarUp ? 75.0 : 25.0
            scores.append(s)
            details.append("SAR: \(sarUp ? "AL sinyali" : "SAT sinyali") (skor \(Int(s)))")
        }

        // TSI üst trend (pozitif TSI = yukarı momentum)
        let tsiVals = calculateTSI(closes: closes)
        if let tsi = tsiVals.last {
            let s: Double = tsi > 25 ? 80 : tsi > 0 ? 60 : tsi > -25 ? 40 : 20
            scores.append(s)
            details.append("TSI=\(String(format: "%.1f", tsi)) (skor \(Int(s)))")
        }

        guard !scores.isEmpty else { return (nil, ["Trend için yeterli veri yok"]) }
        return (scores.reduce(0, +) / Double(scores.count), details)
    }

    // MARK: - Momentum (RSI BIST eşikleri 25/75 + TSI slope)

    private func analyzeMomentum(candles: [Candle]) -> (Double?, [String]) {
        let closes = candles.map { $0.close }
        var scores: [Double] = []
        var details: [String] = []

        // RSI — BIST: 25 oversold, 75 overbought (yüksek volatilite)
        if let rsi = IndicatorService.lastRSI(candles: candles, period: 14) {
            let s: Double
            if rsi < 25      { s = 85 }   // Aşırı satım — dönüş fırsatı
            else if rsi < 45 { s = 55 }   // Zayıf momentum ama değer bölgesi
            else if rsi < 60 { s = 65 }   // Nötr-olumlu
            else if rsi < 75 { s = 80 }   // Güçlü momentum
            else             { s = 35 }   // Aşırı alım — dikkat
            scores.append(s)
            details.append("RSI(14)=\(String(format: "%.1f", rsi)) (BIST eşiği 25/75, skor \(Int(s)))")
        }

        // TSI slope (momentum ivmesi)
        let tsiVals = calculateTSI(closes: closes)
        if tsiVals.count >= 3 {
            let slope = tsiVals[tsiVals.count - 1] - tsiVals[tsiVals.count - 3]
            let s: Double = slope > 5 ? 75 : slope > 0 ? 60 : slope > -5 ? 40 : 25
            scores.append(s)
            details.append("TSI eğimi: \(slope > 0 ? "artıyor" : "azalıyor") (skor \(Int(s)))")
        }

        guard !scores.isEmpty else { return (nil, ["Momentum için yeterli veri yok"]) }
        return (scores.reduce(0, +) / Double(scores.count), details)
    }

    // MARK: - Hacim (Volume MA20 karşılaştırma)

    private func analyzeVolume(candles: [Candle]) -> (Double?, [String]) {
        guard candles.count >= 20 else { return (nil, ["Hacim için yeterli veri yok"]) }
        let volumes = candles.map { $0.volume }
        let ma20 = volumes.suffix(20).reduce(0, +) / 20.0
        let currentVol = volumes.last ?? 0
        guard ma20 > 0, currentVol > 0 else { return (nil, ["Hacim verisi yok"]) }

        let ratio = currentVol / ma20
        let s: Double = ratio > 2.0 ? 85 : ratio > 1.5 ? 70 : ratio > 1.0 ? 55 : ratio > 0.6 ? 40 : 25
        let detail = "Hacim/MA20=\(String(format: "%.2f", ratio))x (skor \(Int(s)))"
        return (s, [detail])
    }

    // MARK: - Formasyon (Yüksek yüksek / Düşük düşük pattern)

    private func analyzePattern(candles: [Candle]) -> (Double?, [String]) {
        guard candles.count >= 20 else { return (nil, ["Formasyon için yeterli veri yok"]) }
        let slice = Array(candles.suffix(20))
        let closes = slice.map { $0.close }
        guard closes.count >= 2 else { return (nil, []) }

        // Kısa vadeli yukarı trend (son 5 bar ortalaması > önceki 5 bar ortalaması)
        let recent5 = Array(closes.suffix(5))
        let prev5   = Array(closes.dropLast(5).suffix(5))
        guard !recent5.isEmpty, !prev5.isEmpty else { return (nil, []) }

        let recentAvg = recent5.reduce(0, +) / Double(recent5.count)
        let prevAvg   = prev5.reduce(0, +) / Double(prev5.count)

        let trendUp = recentAvg > prevAvg
        let strength = abs(recentAvg - prevAvg) / prevAvg * 100

        let s: Double = trendUp ? (strength > 3 ? 80 : 65) : (strength > 3 ? 20 : 35)
        let detail = "Kısa vadeli yapı: \(trendUp ? "yükselen" : "alçalan") (%\(String(format: "%.1f", strength)), skor \(Int(s)))"
        return (s, [detail])
    }

    // MARK: - Destek/Direnç (ATR-aware mesafe)

    private func analyzeSupportResistance(candles: [Candle]) -> (Double?, [String]) {
        guard candles.count >= 20,
              let atr = IndicatorService.lastATR(candles: candles, period: 14) else {
            return (nil, ["ATR için yeterli veri yok"])
        }
        let closes = candles.map { $0.close }
        guard let close = closes.last, close > 0, atr > 0 else { return (nil, []) }

        let recent = Array(closes.suffix(20))
        let high20 = recent.max() ?? close
        let low20  = recent.min() ?? close

        let distFromHigh = (high20 - close) / atr
        let distFromLow  = (close - low20) / atr

        // Simetrik: destek yakını AL sinyali (75), direnç yakını SAT sinyali (25), orta nötr (50)
        let totalDist = distFromLow + distFromHigh
        let s: Double
        if totalDist > 0 {
            let position = distFromLow / totalDist
            s = 75.0 - (position * 50.0)
        } else {
            s = 50
        }

        let detail = "Dirence mesafe=\(String(format: "%.1f", distFromHigh)) ATR, Desteğe mesafe=\(String(format: "%.1f", distFromLow)) ATR (skor \(Int(s)))"
        return (s, [detail])
    }

    // MARK: - Volatilite (ATR/fiyat oranı)

    private func analyzeVolatility(candles: [Candle]) -> (Double?, [String]) {
        guard let atr = IndicatorService.lastATR(candles: candles, period: 14),
              let close = candles.last?.close, close > 0 else {
            return (nil, ["ATR için yeterli veri yok"])
        }

        let atrPct = (atr / close) * 100.0
        // BIST yüksek volatilite normaldir; %3-8 ideal, aşırı volatilite risk
        let s: Double
        if atrPct < 1.0      { s = 50 }  // Sıkışma — düşük hareket
        else if atrPct < 3.0 { s = 70 }  // Normal
        else if atrPct < 8.0 { s = 60 }  // Yüksek ama BIST için kabul edilebilir
        else                  { s = 30 }  // Aşırı volatilite — risk

        let detail = "ATR/Fiyat=%\(String(format: "%.1f", atrPct)) (skor \(Int(s)))"
        return (s, [detail])
    }

    // MARK: - Indicators (OrionBistEngine'den taşındı)

    private func calculateTSI(closes: [Double]) -> [Double] {
        guard closes.count > tsiLong + tsiShort else { return [] }
        var pc: [Double] = []
        for i in 1..<closes.count { pc.append(closes[i] - closes[i - 1]) }
        let pcs  = ema(data: pc, period: tsiLong)
        let apcs = ema(data: pc.map { abs($0) }, period: tsiLong)
        let pcs2  = ema(data: pcs, period: tsiShort)
        let apcs2 = ema(data: apcs, period: tsiShort)
        return (0..<pcs2.count).compactMap { i in
            apcs2[i] != 0 ? 100.0 * (pcs2[i] / apcs2[i]) : 0.0
        }
    }

    private func calculateSAR(highs: [Double], lows: [Double]) -> [Double] {
        guard highs.count > 1 else { return [] }
        var sar = Array(repeating: 0.0, count: highs.count)
        var isBullish = true
        var af = sarStart
        var ep = highs[0]
        sar[0] = lows[0]
        for i in 1..<highs.count {
            let prev = sar[i - 1]
            if isBullish {
                sar[i] = prev + af * (ep - prev)
                let p1 = lows[i - 1]
                let p2 = i > 1 ? lows[i - 2] : p1
                sar[i] = min(sar[i], p1, p2)
                if highs[i] > ep { ep = highs[i]; af = min(af + sarInc, sarMax) }
                if lows[i] < sar[i] { isBullish = false; sar[i] = ep; ep = lows[i]; af = sarStart }
            } else {
                sar[i] = prev + af * (ep - prev)
                let p1 = highs[i - 1]
                let p2 = i > 1 ? highs[i - 2] : p1
                sar[i] = max(sar[i], p1, p2)
                if lows[i] < ep { ep = lows[i]; af = min(af + sarInc, sarMax) }
                if highs[i] > sar[i] { isBullish = true; sar[i] = ep; ep = highs[i]; af = sarStart }
            }
        }
        return sar
    }

    private func ema(data: [Double], period: Int) -> [Double] {
        guard !data.isEmpty else { return [] }
        let k = 2.0 / Double(period + 1)
        var result = [data[0]]
        for i in 1..<data.count {
            result.append(data[i] * k + (result.last ?? data[0]) * (1.0 - k))
        }
        return result
    }

    private func emptyResult(symbol: String, reason: String) -> OrionV2Result {
        OrionV2Result(
            symbol: symbol, totalScore: 50,
            trendScore: nil, momentumScore: nil, volumeScore: nil,
            patternScore: nil, srScore: nil, volatilityScore: nil,
            trendDetails: [], momentumDetails: [], volumeDetails: [],
            patternDetails: [], srDetails: [], volatilityDetails: [],
            summary: "[\(symbol)] \(reason)", highlights: [],
            warnings: [reason], validSectionCount: 0
        )
    }
}
