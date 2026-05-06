import XCTest
@testable import argus

// MARK: - Test Fixtures

private func noDataMetric(_ id: String, _ name: String) -> AtlasMetric {
    AtlasMetric(id: id, name: name, value: nil, status: .noData, score: 50,
                explanation: "—", educationalNote: "—")
}

private func makeAtlasResult(
    symbol: String = "TEST",
    totalScore: Double,
    valuationScore: Double = 50,
    profitabilityScore: Double = 50,
    growthScore: Double = 50,
    healthScore: Double = 50,
    cashScore: Double = 50,
    dividendScore: Double = 50
) -> AtlasV2Result {
    let noMet = noDataMetric
    let val = AtlasValuationData(
        pe: noMet("pe", "F/K"), pb: noMet("pb", "PD/DD"),
        evEbitda: noMet("ev", "EV/EBITDA"), peg: noMet("peg", "PEG"),
        forwardPE: noMet("fpe", "İleriye F/K"), priceToSales: nil
    )
    let prof = AtlasProfitabilityData(
        roe: noMet("roe", "ROE"), roa: noMet("roa", "ROA"),
        netMargin: noMet("nm", "Net Marj"), grossMargin: nil, roic: nil
    )
    let grow = AtlasGrowthData(
        revenueCAGR: noMet("rev", "Gelir CAGR"), netIncomeCAGR: noMet("ni", "Kar CAGR"),
        forwardGrowth: nil, revenueGrowthYoY: nil
    )
    let health = AtlasHealthData(
        debtToEquity: noMet("de", "D/E"), currentRatio: noMet("cr", "Cari Oran"),
        interestCoverage: nil, altmanZScore: nil
    )
    let cash = AtlasCashData(
        freeCashFlow: noMet("fcf", "FCF"), ocfToNetIncome: noMet("ocf", "OCF/NI"),
        cashPosition: nil, netDebt: nil
    )
    let div = AtlasDividendData(dividendYield: noMet("div", "Temettü"), payoutRatio: nil, dividendGrowth: nil)
    let risk = AtlasRiskData(beta: noMet("beta", "Beta"), week52High: nil, week52Low: nil, volatility: nil)
    let profile = AtlasCompanyProfile(
        symbol: symbol, name: symbol, sector: nil, industry: nil,
        marketCap: nil, formattedMarketCap: "—", employees: nil,
        description: nil, currency: "USD"
    )
    return AtlasV2Result(
        symbol: symbol, profile: profile,
        totalScore: totalScore,
        valuationScore: valuationScore, profitabilityScore: profitabilityScore,
        growthScore: growthScore, healthScore: healthScore,
        cashScore: cashScore, dividendScore: dividendScore,
        valuation: val, profitability: prof, growth: grow, health: health,
        cash: cash, dividend: div, risk: risk,
        summary: "Test", highlights: [], warnings: []
    )
}

private func makeOrionResult(
    symbol: String = "TEST",
    totalScore: Double,
    trendScore: Double? = nil,
    momentumScore: Double? = nil,
    volumeScore: Double? = nil,
    validSectionCount: Int = 3
) -> OrionV2Result {
    OrionV2Result(
        symbol: symbol, totalScore: totalScore,
        trendScore: trendScore, momentumScore: momentumScore,
        volumeScore: volumeScore, patternScore: nil, srScore: nil, volatilityScore: nil,
        trendDetails: [], momentumDetails: [], volumeDetails: [],
        patternDetails: [], srDetails: [], volatilityDetails: [],
        summary: "Test", highlights: [], warnings: [], validSectionCount: validSectionCount
    )
}

// MARK: - AtlasV2DecisionAdapter Tests

final class AtlasV2AdapterTests: XCTestCase {

    // Eşik testi: totalScore == 60.0 → BUY (boundary)
    func testAtlas_score60_returnsBuy() {
        let result = makeAtlasResult(totalScore: 60.0)
        let decision = AtlasV2DecisionAdapter.adapt(result, engine: .corse)
        XCTAssertEqual(decision.action, .buy, "60.0 → BUY eşiği (≥60)")
    }

    // Eşik altı: 59.9 → HOLD
    func testAtlas_score59_9_returnsHold() {
        let result = makeAtlasResult(totalScore: 59.9)
        let decision = AtlasV2DecisionAdapter.adapt(result, engine: .corse)
        XCTAssertEqual(decision.action, .hold, "59.9 → HOLD (60'ın altı)")
    }

    // SELL eşiği: 40.0 → SELL (boundary)
    func testAtlas_score40_returnsSell() {
        let result = makeAtlasResult(totalScore: 40.0)
        let decision = AtlasV2DecisionAdapter.adapt(result, engine: .corse)
        XCTAssertEqual(decision.action, .sell, "40.0 → SELL (≤40)")
    }

    // SELL eşiği üstü: 40.1 → HOLD
    func testAtlas_score40_1_returnsHold() {
        let result = makeAtlasResult(totalScore: 40.1)
        let decision = AtlasV2DecisionAdapter.adapt(result, engine: .corse)
        XCTAssertEqual(decision.action, .hold, "40.1 → HOLD (40'ın üstü)")
    }

    // Güçlü sinyal: 80+ → isStrongSignal = true
    func testAtlas_score80_isStrongSignal() {
        let result = makeAtlasResult(totalScore: 80.0)
        let decision = AtlasV2DecisionAdapter.adapt(result, engine: .corse)
        XCTAssertTrue(decision.isStrongSignal, "80.0 → güçlü sinyal")
    }

    // Güçlü sinyal: 20 ve altı → isStrongSignal = true
    func testAtlas_score20_isStrongSignal() {
        let result = makeAtlasResult(totalScore: 20.0)
        let decision = AtlasV2DecisionAdapter.adapt(result, engine: .corse)
        XCTAssertTrue(decision.isStrongSignal, "20.0 → güçlü sinyal (aşağı yön)")
    }

    // Orta bant: 50 → isStrongSignal = false
    func testAtlas_score50_isNotStrong() {
        let result = makeAtlasResult(totalScore: 50.0)
        let decision = AtlasV2DecisionAdapter.adapt(result, engine: .corse)
        XCTAssertFalse(decision.isStrongSignal, "50.0 → güçlü sinyal değil")
    }

    // netSupport normalize: 100 → 1.0
    func testAtlas_score100_netSupportIsOne() {
        let result = makeAtlasResult(totalScore: 100.0)
        let decision = AtlasV2DecisionAdapter.adapt(result, engine: .corse)
        XCTAssertEqual(decision.netSupport, 1.0, accuracy: 0.001)
    }

    // 6 section proposal üretilmeli
    func testAtlas_proposalCount_isSix() {
        let result = makeAtlasResult(totalScore: 70.0)
        let decision = AtlasV2DecisionAdapter.adapt(result, engine: .corse)
        XCTAssertEqual(decision.allProposals.count, 6, "AtlasV2 6 section → 6 proposal")
    }

    // Warnings → vetoReasons aktarımı
    func testAtlas_warningsPassedAsVetoReasons() {
        let warned = AtlasV2Result(
            symbol: "WARN",
            profile: AtlasCompanyProfile(symbol: "WARN", name: "WARN", sector: nil, industry: nil,
                                         marketCap: nil, formattedMarketCap: "—", employees: nil,
                                         description: nil, currency: "USD"),
            totalScore: 50,
            valuationScore: 50, profitabilityScore: 50, growthScore: 50,
            healthScore: 50, cashScore: 50, dividendScore: 50,
            valuation: makeAtlasResult(totalScore: 50).valuation,
            profitability: makeAtlasResult(totalScore: 50).profitability,
            growth: makeAtlasResult(totalScore: 50).growth,
            health: makeAtlasResult(totalScore: 50).health,
            cash: makeAtlasResult(totalScore: 50).cash,
            dividend: makeAtlasResult(totalScore: 50).dividend,
            risk: makeAtlasResult(totalScore: 50).risk,
            summary: "Test", highlights: [], warnings: ["Borç yüksek", "Büyüme yavaş"]
        )
        let decision = AtlasV2DecisionAdapter.adapt(warned, engine: .corse)
        XCTAssertEqual(decision.vetoReasons, ["Borç yüksek", "Büyüme yavaş"])
    }
}

// MARK: - OrionV2DecisionAdapter Tests

final class OrionV2AdapterTests: XCTestCase {

    // BUY eşiği: 55.0 → BUY (boundary)
    func testOrion_score55_returnsBuy() {
        let result = makeOrionResult(totalScore: 55.0)
        let decision = OrionV2DecisionAdapter.adapt(result)
        XCTAssertEqual(decision.action, .buy, "55.0 → BUY eşiği (≥55)")
    }

    // BUY eşiği altı: 54.9 → HOLD
    func testOrion_score54_9_returnsHold() {
        let result = makeOrionResult(totalScore: 54.9)
        let decision = OrionV2DecisionAdapter.adapt(result)
        XCTAssertEqual(decision.action, .hold, "54.9 → HOLD (55'in altı)")
    }

    // SELL eşiği: 45.0 → SELL (boundary)
    func testOrion_score45_returnsSell() {
        let result = makeOrionResult(totalScore: 45.0)
        let decision = OrionV2DecisionAdapter.adapt(result)
        XCTAssertEqual(decision.action, .sell, "45.0 → SELL (≤45)")
    }

    // SELL üstü: 45.1 → HOLD (nötr bant 45.1–54.9)
    func testOrion_score45_1_returnsHold() {
        let result = makeOrionResult(totalScore: 45.1)
        let decision = OrionV2DecisionAdapter.adapt(result)
        XCTAssertEqual(decision.action, .hold, "45.1 → HOLD (nötr bant)")
    }

    // Güçlü sinyal: 75+ → isStrongSignal
    func testOrion_score75_isStrongSignal() {
        let result = makeOrionResult(totalScore: 75.0)
        let decision = OrionV2DecisionAdapter.adapt(result)
        XCTAssertTrue(decision.isStrongSignal, "75.0 → güçlü sinyal")
    }

    // Güçlü sinyal: 25 ve altı
    func testOrion_score25_isStrongSignal() {
        let result = makeOrionResult(totalScore: 25.0)
        let decision = OrionV2DecisionAdapter.adapt(result)
        XCTAssertTrue(decision.isStrongSignal, "25.0 → güçlü sinyal (aşağı yön)")
    }

    // Zayıf sinyal bandı: 60.0 → isWeakSignal (55-74 arası, strong değil)
    func testOrion_score60_isWeakBuySignal() {
        let result = makeOrionResult(totalScore: 60.0)
        let decision = OrionV2DecisionAdapter.adapt(result)
        XCTAssertFalse(decision.isStrongSignal, "60.0 → güçlü değil (75'in altı)")
        XCTAssertTrue(decision.isWeakSignal, "60.0 → zayıf AL sinyali (55-74 bandı)")
    }

    // netSupport normalize: merkezden offset → (score - 50) / 50
    func testOrion_score75_netSupportIsHalf() {
        let result = makeOrionResult(totalScore: 75.0)
        let decision = OrionV2DecisionAdapter.adapt(result)
        XCTAssertEqual(decision.netSupport, 0.5, accuracy: 0.001, "(75-50)/50 = 0.5")
    }

    func testOrion_score25_netSupportIsNegativeHalf() {
        let result = makeOrionResult(totalScore: 25.0)
        let decision = OrionV2DecisionAdapter.adapt(result)
        XCTAssertEqual(decision.netSupport, -0.5, accuracy: 0.001, "(25-50)/50 = -0.5")
    }

    // Nil section'lara sahip result'ta section'lar proposal'lara dahil edilmemeli
    func testOrion_nilSections_producesOnlyPresentProposals() {
        let result = makeOrionResult(totalScore: 60.0, trendScore: 70.0, momentumScore: nil, volumeScore: nil)
        let decision = OrionV2DecisionAdapter.adapt(result)
        XCTAssertEqual(decision.allProposals.count, 1, "1 nil olmayan section → 1 proposal")
    }
}
