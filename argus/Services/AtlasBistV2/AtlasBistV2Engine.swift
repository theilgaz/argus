import Foundation

// MARK: - Atlas BIST V2 Engine
// BIST hisseleri için bağımsız fundamental analiz motoru.
// BorsaPy'den kendi verisini çeker — GrandCouncil snapshot bağımlılığı YOK.
// AtlasV2Result döndürür → AtlasV2DecisionAdapter direkt kullanılabilir (ek adapter gerekmez).
// Pattern: AtlasV2Engine ile özdeş (6 bölüm, nil-aware, normalize ağırlık, < 3 bölüm → skor 50).

actor AtlasBistV2Engine {
    static let shared = AtlasBistV2Engine()

    private var cache: [String: AtlasV2Result] = [:]
    private let cacheTTL: TimeInterval = 3600  // 1 saat

    private init() {}

    // MARK: - Public API

    func analyze(symbol: String, forceRefresh: Bool = false) async -> AtlasV2Result {
        if !forceRefresh,
           let cached = cache[symbol],
           Date().timeIntervalSince(cached.timestamp) < cacheTTL {
            return cached
        }

        // BorsaPy'den paralel veri çek
        async let finTask   = try? BorsaPyProvider.shared.getFinancialStatements(symbol: symbol)
        async let divTask   = try? BorsaPyProvider.shared.getDividends(symbol: symbol)
        async let quoteTask = try? BorsaPyProvider.shared.getBistQuote(symbol: symbol)
        let (financials, dividends, bistQuote) = await (finTask, divTask, quoteTask)

        // Section scores (nil = veri yok)
        let valuationOpt      = scoreValuation(financials: financials, quote: bistQuote)
        let profitabilityOpt  = scoreProfitability(financials: financials)
        let growthOpt         = scoreGrowth(financials: financials)
        let healthOpt         = scoreHealth(financials: financials)
        let cashOpt           = scoreCash(financials: financials)
        let dividendOpt       = scoreDividend(dividends: dividends, quote: bistQuote)

        // Nil-aware aggregator (< 3 bölüm → "Veri yetersiz", skor 50)
        let candidates: [(String, Double?, Double)] = [
            ("Değerleme",   valuationOpt,     0.30),
            ("Karlılık",    profitabilityOpt, 0.25),
            ("Büyüme",      growthOpt,        0.20),
            ("Mali Sağlık", healthOpt,        0.15),
            ("Nakit",       cashOpt,          0.07),
            ("Temettü",     dividendOpt,      0.03),
        ]
        let valid   = candidates.compactMap { (l, s, w) -> (String, Double, Double)? in
            guard let s = s else { return nil }; return (l, s, w)
        }
        let missing = candidates.filter { $0.1 == nil }.map { $0.0 }

        var warnings: [String] = []
        let totalScore: Double
        if valid.count < 3 {
            totalScore = 50.0
            warnings.append("⚠️ Veri yetersiz: \(valid.count)/6 bölüm mevcut. Eksik: \(missing.joined(separator: ", ")). BorsaPy verisini kontrol et.")
            ArgusLogger.warning(.atlas, "BistV2 \(symbol) yetersiz veri (\(valid.count)/6). Skor=50.")
        } else {
            let tw = valid.reduce(0.0) { $0 + $1.2 }
            totalScore = valid.reduce(0.0) { $0 + $1.1 * $1.2 } / tw
            if !missing.isEmpty {
                warnings.append("ℹ️ Skor \(valid.count)/6 bölümle hesaplandı. Eksik: \(missing.joined(separator: ", "))")
            }
        }

        let trace = "val=\(fmtS(valuationOpt)) prof=\(fmtS(profitabilityOpt)) grow=\(fmtS(growthOpt)) health=\(fmtS(healthOpt)) cash=\(fmtS(cashOpt)) div=\(fmtS(dividendOpt))"
        ArgusLogger.info(.atlas, "BistV2 \(symbol) total=\(Int(totalScore)) (\(valid.count)/6 bölüm) \(trace)")

        let result = buildResult(
            symbol: symbol,
            financials: financials,
            dividends: dividends,
            bistQuote: bistQuote,
            totalScore: min(100, max(0, totalScore)),
            valuationScore: valuationOpt ?? 0,
            profitabilityScore: profitabilityOpt ?? 0,
            growthScore: growthOpt ?? 0,
            healthScore: healthOpt ?? 0,
            cashScore: cashOpt ?? 0,
            dividendScore: dividendOpt ?? 0,
            warnings: warnings
        )
        cache[symbol] = result
        return result
    }

    // MARK: - Section Scoring

    private func scoreValuation(financials: BistFinancials?, quote: BistQuote?) -> Double? {
        guard let f = financials else { return nil }
        var scores: [Double] = []

        if let pe = f.pe {
            if pe < 0       { scores.append(5) }   // Zarar
            else if pe < 5  { scores.append(90) }  // Derin değer (BIST)
            else if pe < 10 { scores.append(75) }
            else if pe < 20 { scores.append(50) }
            else if pe < 35 { scores.append(30) }
            else            { scores.append(10) }
        }
        if let pb = f.pb, pb > 0 {
            if pb < 0.7      { scores.append(90) }
            else if pb < 1.5 { scores.append(70) }
            else if pb < 3.0 { scores.append(50) }
            else if pb < 5.0 { scores.append(30) }
            else             { scores.append(10) }
        }
        if let ebitda = f.ebitda, ebitda > 0, let mc = f.marketCap, mc > 0 {
            let netDebt = (f.totalDebt ?? 0) - (f.cash ?? 0)
            let ratio = (mc + netDebt) / ebitda
            if ratio < 4       { scores.append(85) }
            else if ratio < 8  { scores.append(65) }
            else if ratio < 12 { scores.append(45) }
            else if ratio < 20 { scores.append(25) }
            else               { scores.append(10) }
        }
        guard !scores.isEmpty else { return nil }
        return scores.reduce(0, +) / Double(scores.count)
    }

    private func scoreProfitability(financials: BistFinancials?) -> Double? {
        guard let f = financials else { return nil }
        var scores: [Double] = []

        if let roe = f.roe {
            scores.append(roe > 0.30 ? 90 : roe > 0.20 ? 75 : roe > 0.10 ? 55 : roe > 0 ? 35 : 10)
        }
        if let roa = f.roa {
            scores.append(roa > 0.15 ? 85 : roa > 0.10 ? 70 : roa > 0.05 ? 50 : roa > 0 ? 30 : 10)
        }
        if let nm = f.netMargin {
            scores.append(nm > 0.20 ? 90 : nm > 0.10 ? 70 : nm > 0.05 ? 50 : nm > 0 ? 30 : 10)
        }
        if let gm = f.grossMargin {
            scores.append(gm > 0.50 ? 85 : gm > 0.30 ? 65 : gm > 0.15 ? 45 : gm > 0 ? 25 : 10)
        }
        guard !scores.isEmpty else { return nil }
        return scores.reduce(0, +) / Double(scores.count)
    }

    private func scoreGrowth(financials: BistFinancials?) -> Double? {
        guard let f = financials else { return nil }
        // BIST: ~%50 enflasyon referansı. %80+ nominal → reel büyüme güçlü.
        var scores: [Double] = []

        if let rg = f.revenueGrowth {
            scores.append(rg > 0.80 ? 90 : rg > 0.50 ? 70 : rg > 0.30 ? 50 : rg > 0 ? 30 : 10)
        }
        if let ng = f.netProfitGrowth {
            scores.append(ng > 1.00 ? 90 : ng > 0.60 ? 70 : ng > 0.30 ? 50 : ng > 0 ? 30 : 10)
        }
        guard !scores.isEmpty else { return nil }
        return scores.reduce(0, +) / Double(scores.count)
    }

    private func scoreHealth(financials: BistFinancials?) -> Double? {
        guard let f = financials else { return nil }
        var scores: [Double] = []

        if let de = f.debtToEquity {
            if de < 0       { scores.append(50) }  // Negatif özkaynak — belirsiz
            else if de < 0.30 { scores.append(90) }
            else if de < 0.70 { scores.append(70) }
            else if de < 1.50 { scores.append(50) }
            else if de < 3.00 { scores.append(30) }
            else              { scores.append(10) }
        }
        if let cr = f.currentRatio {
            scores.append(cr > 2.0 ? 90 : cr > 1.5 ? 70 : cr > 1.0 ? 50 : cr > 0.7 ? 30 : 10)
        }
        guard !scores.isEmpty else { return nil }
        return scores.reduce(0, +) / Double(scores.count)
    }

    private func scoreCash(financials: BistFinancials?) -> Double? {
        guard let f = financials else { return nil }
        var scores: [Double] = []

        if let ocf = f.operatingCashFlow {
            scores.append(ocf > 0 ? 70 : 20)  // Pozitif OCF = yeterlilik
        }
        if let cr = f.cashRatio {
            scores.append(cr > 1.0 ? 90 : cr > 0.5 ? 70 : cr > 0.2 ? 45 : 20)
        }
        guard !scores.isEmpty else { return nil }
        return scores.reduce(0, +) / Double(scores.count)
    }

    private func scoreDividend(dividends: [BistDividend]?, quote: BistQuote?) -> Double? {
        guard let divs = dividends, !divs.isEmpty else { return nil }

        let oneYearAgo = Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? Date()
        let recent = divs.filter { $0.date > oneYearAgo }
        guard !recent.isEmpty else { return nil }

        let price = quote?.last ?? 0
        guard price > 0 else {
            // Fiyat yok ama son 1 yılda temettü var → düşük ama var sinyali
            return 30
        }
        let totalPerShare = recent.reduce(0.0) { $0 + $1.perShare }
        let yieldPct = (totalPerShare / price) * 100.0

        // BIST temettü kültürü yüksek
        if yieldPct > 10     { return 90 }
        else if yieldPct > 7 { return 75 }
        else if yieldPct > 4 { return 55 }
        else if yieldPct > 2 { return 35 }
        else                 { return 20 }
    }

    // MARK: - Result Builder

    private func buildResult(
        symbol: String,
        financials: BistFinancials?,
        dividends: [BistDividend]?,
        bistQuote: BistQuote?,
        totalScore: Double,
        valuationScore: Double,
        profitabilityScore: Double,
        growthScore: Double,
        healthScore: Double,
        cashScore: Double,
        dividendScore: Double,
        warnings: [String]
    ) -> AtlasV2Result {
        let price = bistQuote?.last
        let mc = financials?.marketCap

        // Nested metric types
        let valData = buildValuation(f: financials, price: price)
        let profData = buildProfitability(f: financials)
        let growData = buildGrowth(f: financials)
        let healthData = buildHealth(f: financials)
        let cashData = buildCash(f: financials)
        let divData = buildDividend(dividends: dividends, price: price)
        let riskData = AtlasRiskData(beta: noData("risk_beta", "Beta"), week52High: nil, week52Low: nil, volatility: nil)

        let profile = AtlasCompanyProfile(
            symbol: symbol,
            name: symbol,
            sector: "BIST",
            industry: nil,
            marketCap: mc,
            formattedMarketCap: AtlasMetric.format(mc),
            employees: nil,
            description: nil,
            currency: "TRY"
        )

        var highlights: [String] = []
        if valuationScore >= 70  { highlights.append("Değerleme cazip (\(Int(valuationScore)))") }
        if profitabilityScore >= 70 { highlights.append("Karlılık güçlü (\(Int(profitabilityScore)))") }
        if growthScore >= 70     { highlights.append("Büyüme güçlü (\(Int(growthScore)))") }

        let summary: String
        if totalScore >= 70      { summary = "[\(symbol)] BIST fundamental tablo olumlu — \(Int(totalScore))/100" }
        else if totalScore >= 55 { summary = "[\(symbol)] BIST fundamental tablo orta-üstü — \(Int(totalScore))/100" }
        else if totalScore >= 45 { summary = "[\(symbol)] BIST fundamental tablo nötr — \(Int(totalScore))/100" }
        else if totalScore >= 30 { summary = "[\(symbol)] BIST fundamental tablo orta-altı — \(Int(totalScore))/100" }
        else                     { summary = "[\(symbol)] BIST fundamental tablo zayıf — \(Int(totalScore))/100" }

        return AtlasV2Result(
            symbol: symbol,
            profile: profile,
            totalScore: totalScore,
            valuationScore: valuationScore,
            profitabilityScore: profitabilityScore,
            growthScore: growthScore,
            healthScore: healthScore,
            cashScore: cashScore,
            dividendScore: dividendScore,
            valuation: valData,
            profitability: profData,
            growth: growData,
            health: healthData,
            cash: cashData,
            dividend: divData,
            risk: riskData,
            summary: summary,
            highlights: highlights,
            warnings: warnings
        )
    }

    private func buildValuation(f: BistFinancials?, price: Double?) -> AtlasValuationData {
        let peScore   = f?.pe.map { scoreFromPE($0) } ?? 50
        let pbScore   = f?.pb.map { scoreFromPB($0) } ?? 50
        let evScore: Double = {
            guard let eb = f?.ebitda, eb > 0, let mc = f?.marketCap, mc > 0 else { return 50 }
            let nd = (f?.totalDebt ?? 0) - (f?.cash ?? 0)
            let r = (mc + nd) / eb
            return r < 4 ? 85 : r < 8 ? 65 : r < 12 ? 45 : r < 20 ? 25 : 10
        }()

        return AtlasValuationData(
            pe:        metric("val_pe",  "F/K (P/E)", value: f?.pe, score: peScore, explanation: bistPEExplanation(f?.pe), formula: "Fiyat / Hisse Başı Kâr"),
            pb:        metric("val_pb",  "PD/DD (P/B)", value: f?.pb, score: pbScore, explanation: bistPBExplanation(f?.pb), formula: "Piyasa Değeri / Defter Değeri"),
            evEbitda:  metric("val_ev",  "EV/EBITDA", value: evEBITDA(f), score: evScore, explanation: "BIST için 4–12 arası makul", formula: "(PD + Net Borç) / FAVÖK"),
            peg:          noData("val_peg", "PEG Oranı"),
            forwardPE:    noData("val_fpe", "İleriye Dönük F/K"),
            priceToSales: noData("val_ps",  "Fiyat/Satış")
        )
    }

    private func buildProfitability(f: BistFinancials?) -> AtlasProfitabilityData {
        let roeScore = f?.roe.map { $0 > 0.30 ? 90.0 : $0 > 0.20 ? 75.0 : $0 > 0.10 ? 55.0 : $0 > 0 ? 35.0 : 10.0 } ?? 50
        let roaScore = f?.roa.map { $0 > 0.15 ? 85.0 : $0 > 0.10 ? 70.0 : $0 > 0.05 ? 50.0 : $0 > 0 ? 30.0 : 10.0 } ?? 50
        let nmScore  = f?.netMargin.map { $0 > 0.20 ? 90.0 : $0 > 0.10 ? 70.0 : $0 > 0.05 ? 50.0 : $0 > 0 ? 30.0 : 10.0 } ?? 50
        let gmScore  = f?.grossMargin.map { $0 > 0.50 ? 85.0 : $0 > 0.30 ? 65.0 : $0 > 0.15 ? 45.0 : $0 > 0 ? 25.0 : 10.0 }

        return AtlasProfitabilityData(
            roe:         metric("prof_roe", "Özkaynak Kârlılığı (ROE)", value: f?.roe.map { $0 * 100 }, score: roeScore, explanation: "ROE > %20 BIST için güçlü"),
            roa:         metric("prof_roa", "Aktif Kârlılığı (ROA)", value: f?.roa.map { $0 * 100 }, score: roaScore, explanation: "ROA > %10 verimli varlık kullanımı"),
            netMargin:   metric("prof_nm",  "Net Kâr Marjı", value: f?.netMargin.map { $0 * 100 }, score: nmScore, explanation: "Net Kâr / Ciro"),
            grossMargin: gmScore.map { metric("prof_gm", "Brüt Kâr Marjı", value: f?.grossMargin.map { $0 * 100 }, score: $0, explanation: "Brüt Kâr / Ciro") },
            roic:        nil
        )
    }

    private func buildGrowth(f: BistFinancials?) -> AtlasGrowthData {
        // BIST: %80+ nominal büyüme reel büyüme sinyali (enflasyon ~%50)
        let rgScore = f?.revenueGrowth.map { $0 > 0.80 ? 90.0 : $0 > 0.50 ? 70.0 : $0 > 0.30 ? 50.0 : $0 > 0 ? 30.0 : 10.0 } ?? 50
        let ngScore = f?.netProfitGrowth.map { $0 > 1.00 ? 90.0 : $0 > 0.60 ? 70.0 : $0 > 0.30 ? 50.0 : $0 > 0 ? 30.0 : 10.0 } ?? 50

        return AtlasGrowthData(
            revenueCAGR:     metric("grow_rev",  "Ciro Büyümesi", value: f?.revenueGrowth.map { $0 * 100 }, score: rgScore, explanation: "Nominal >%80 → enflasyon üzeri büyüme"),
            netIncomeCAGR:   metric("grow_np",   "Net Kâr Büyümesi", value: f?.netProfitGrowth.map { $0 * 100 }, score: ngScore, explanation: "Net kâr nominal büyüme"),
            forwardGrowth:   noData("grow_fwd",  "Tahmin Büyüme"),
            revenueGrowthYoY: nil
        )
    }

    private func buildHealth(f: BistFinancials?) -> AtlasHealthData {
        let deScore = f?.debtToEquity.map { de -> Double in
            if de < 0 { return 50 }
            return de < 0.30 ? 90 : de < 0.70 ? 70 : de < 1.50 ? 50 : de < 3.00 ? 30 : 10
        } ?? 50
        let crScore = f?.currentRatio.map { $0 > 2.0 ? 90.0 : $0 > 1.5 ? 70.0 : $0 > 1.0 ? 50.0 : $0 > 0.7 ? 30.0 : 10.0 } ?? 50

        return AtlasHealthData(
            debtToEquity:    metric("health_de", "Borç/Özkaynak", value: f?.debtToEquity, score: deScore, explanation: "BIST için < 1.5 makul"),
            currentRatio:    metric("health_cr", "Cari Oran", value: f?.currentRatio, score: crScore, explanation: "> 1.5 kısa vadeli yükümlülükler karşılanabilir"),
            interestCoverage: nil,
            altmanZScore:    nil
        )
    }

    private func buildCash(f: BistFinancials?) -> AtlasCashData {
        let ocfScore = f?.operatingCashFlow.map { $0 > 0 ? 70.0 : 20.0 } ?? 50
        let crScore  = f?.cashRatio.map { $0 > 1.0 ? 90.0 : $0 > 0.5 ? 70.0 : $0 > 0.2 ? 45.0 : 20.0 } ?? 50
        let ocfRatio: Double? = {
            guard let ocf = f?.operatingCashFlow, let np = f?.netProfit, np != 0 else { return nil }
            return ocf / np
        }()
        let ocfRatioScore: Double = ocfRatio.map { $0 > 1.0 ? 85 : $0 > 0.5 ? 65 : $0 > 0 ? 45 : 20 } ?? 50

        return AtlasCashData(
            freeCashFlow:    metric("cash_ocf",  "İşletme Nakit Akışı", value: f?.operatingCashFlow, score: ocfScore, explanation: "Pozitif OCF temel yeterlilik"),
            ocfToNetIncome:  metric("cash_ratio","Nakit/Net Kâr Oranı", value: ocfRatio, score: ocfRatioScore, explanation: "> 1.0 kâr nakde dönüşüyor"),
            cashPosition:    metric("cash_pos",  "Nakit Pozisyonu", value: f?.cash, score: crScore, explanation: "Nakit / Kısa Vadeli Borç"),
            netDebt:         nil
        )
    }

    private func buildDividend(dividends: [BistDividend]?, price: Double?) -> AtlasDividendData {
        let oneYearAgo = Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? Date()
        let recent = dividends?.filter { $0.date > oneYearAgo } ?? []
        let totalPerShare = recent.reduce(0.0) { $0 + $1.perShare }

        let yield: Double? = (price ?? 0) > 0 ? (totalPerShare / price!) * 100.0 : nil
        let yieldScore: Double = yield.map { y in
            y > 10 ? 90 : y > 7 ? 75 : y > 4 ? 55 : y > 2 ? 35 : 20
        } ?? 50

        return AtlasDividendData(
            dividendYield: metric("div_yield", "Temettü Verimi", value: yield, score: yieldScore, explanation: "Son 1 yıl hisse başı temettü / fiyat", formula: "Temettü / Fiyat × 100"),
            payoutRatio:   nil,
            dividendGrowth: nil
        )
    }

    // MARK: - Score Helpers

    private func scoreFromPE(_ pe: Double) -> Double {
        if pe < 0  { return 5 }
        if pe < 5  { return 90 }
        if pe < 10 { return 75 }
        if pe < 20 { return 50 }
        if pe < 35 { return 30 }
        return 10
    }

    private func scoreFromPB(_ pb: Double) -> Double {
        if pb <= 0 { return 50 }
        if pb < 0.7 { return 90 }
        if pb < 1.5 { return 70 }
        if pb < 3.0 { return 50 }
        if pb < 5.0 { return 30 }
        return 10
    }

    private func evEBITDA(_ f: BistFinancials?) -> Double? {
        guard let eb = f?.ebitda, eb > 0, let mc = f?.marketCap, mc > 0 else { return nil }
        let nd = (f?.totalDebt ?? 0) - (f?.cash ?? 0)
        return (mc + nd) / eb
    }

    private func bistPEExplanation(_ pe: Double?) -> String {
        guard let pe else { return "F/K verisi mevcut değil" }
        if pe < 0  { return "Zarar eden şirket" }
        if pe < 5  { return "BIST'te derin değer (F/K < 5)" }
        if pe < 10 { return "Değer fırsatı (F/K < 10)" }
        if pe < 20 { return "Makul fiyatlama" }
        return "Pahalı (F/K > 20)"
    }

    private func bistPBExplanation(_ pb: Double?) -> String {
        guard let pb else { return "PD/DD verisi mevcut değil" }
        if pb < 0.7 { return "Defter değerinin altında işlem görüyor" }
        if pb < 1.5 { return "Defter değerine yakın, cazip" }
        return "Defter değerinin üzerinde"
    }

    // MARK: - Metric Factory

    private func metric(_ id: String, _ name: String, value: Double?, score: Double, explanation: String, formula: String? = nil) -> AtlasMetric {
        let status: AtlasMetricStatus
        if value == nil { status = .noData }
        else if score >= 75 { status = .excellent }
        else if score >= 60 { status = .good }
        else if score >= 45 { status = .neutral }
        else if score >= 30 { status = .warning }
        else                { status = .bad }

        return AtlasMetric(
            id: id, name: name, value: value,
            status: status, score: score,
            explanation: explanation, educationalNote: "",
            formula: formula
        )
    }

    private func noData(_ id: String, _ name: String) -> AtlasMetric {
        AtlasMetric(id: id, name: name, value: nil, status: .noData, score: 50, explanation: "BIST için veri mevcut değil", educationalNote: "")
    }

    private func fmtS(_ v: Double?) -> String { v.map { "\(Int($0))" } ?? "N/A" }
}
