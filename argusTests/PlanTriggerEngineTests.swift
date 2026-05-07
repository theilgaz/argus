import XCTest
@testable import argus

final class PlanTriggerEngineTests: XCTestCase {

    let engine = PlanTriggerEngine.shared

    // MARK: - Candle Fixture Helper

    private func makeCandles(
        count: Int,
        baseClose: Double = 100.0,
        step: Double = 1.0,
        spread: Double = 2.0
    ) -> [Candle] {
        (0..<count).map { i in
            let close = baseClose + Double(i) * step
            return Candle(
                date: Date().addingTimeInterval(TimeInterval(-count + i) * 86400),
                open: close - spread * 0.3,
                high: close + spread * 0.5,
                low: close - spread * 0.5,
                close: close,
                volume: 1_000_000
            )
        }
    }

    // MARK: - Moving Average

    func testMovingAverage_CalculatesCorrectly() {
        let candles = makeCandles(count: 5, baseClose: 10.0, step: 2.0)

        let sma = engine.movingAverage(from: candles, period: 5)

        XCTAssertNotNil(sma)
        XCTAssertEqual(sma!, 14.0, accuracy: 0.0001)
    }

    func testMovingAverage_Period3_UsesLastThree() {
        let candles = makeCandles(count: 10, baseClose: 50.0, step: 1.0)

        let sma = engine.movingAverage(from: candles, period: 3)

        XCTAssertNotNil(sma)
        XCTAssertEqual(sma!, 58.0, accuracy: 0.0001)
    }

    func testMovingAverage_InsufficientData_ReturnsNil() {
        let candles = makeCandles(count: 3, baseClose: 100.0)

        let sma = engine.movingAverage(from: candles, period: 5)

        XCTAssertNil(sma)
    }

    func testMovingAverage_ExactPeriod_IncludesAll() {
        let candles = makeCandles(count: 20, baseClose: 100.0, step: 0.0)

        let sma = engine.movingAverage(from: candles, period: 20)

        XCTAssertNotNil(sma)
        XCTAssertEqual(sma!, 100.0, accuracy: 0.0001)
    }

    // MARK: - ATR

    func testEstimateATR_CalculatesAverageTrueRange() {
        let candles = makeCandles(count: 16, baseClose: 100.0, step: 0.0, spread: 4.0)

        let atr = engine.estimateATR(from: candles, period: 14)

        XCTAssertNotNil(atr)
        XCTAssertGreaterThan(atr!, 0.0)
    }

    func testEstimateATR_InsufficientData_ReturnsNil() {
        let candles = makeCandles(count: 5, baseClose: 100.0)

        let atr = engine.estimateATR(from: candles, period: 14)

        XCTAssertNil(atr)
    }

    func testEstimateATR_HighVolatility_GreaterThanLow() {
        let lowVol = makeCandles(count: 16, baseClose: 100.0, step: 0.0, spread: 1.0)
        let highVol = makeCandles(count: 16, baseClose: 100.0, step: 0.0, spread: 10.0)

        let atrLow = engine.estimateATR(from: lowVol, period: 14)!
        let atrHigh = engine.estimateATR(from: highVol, period: 14)!

        XCTAssertGreaterThan(atrHigh, atrLow)
    }

    // MARK: - Support / Resistance

    func testEstimateSupportResistance_FindsMinMax() {
        let candles = makeCandles(count: 50, baseClose: 100.0, step: 1.0, spread: 3.0)

        let (support, resistance) = engine.estimateSupportResistance(from: candles, lookback: 40)

        XCTAssertNotNil(support)
        XCTAssertNotNil(resistance)
        XCTAssertLessThan(support!, resistance!)
    }

    func testEstimateSupportResistance_EmptyCandles_ReturnsNils() {
        let (support, resistance) = engine.estimateSupportResistance(from: [], lookback: 40)

        XCTAssertNil(support)
        XCTAssertNil(resistance)
    }

    func testEstimateSupportResistance_SingleCandle_SupportEqualsLow() {
        let candle = Candle(date: Date(), open: 99, high: 105, low: 95, close: 100, volume: 1000)

        let (support, resistance) = engine.estimateSupportResistance(from: [candle], lookback: 40)

        XCTAssertEqual(support, 95.0)
        XCTAssertEqual(resistance, 105.0)
    }

    // MARK: - Trend Estimation

    func testEstimateTrend_StrongUptrend() {
        let candles = makeCandles(count: 60, baseClose: 100.0, step: 1.0)
        let lastClose = candles.last!.close

        let sma20 = engine.movingAverage(from: candles, period: 20)!
        let sma50 = engine.movingAverage(from: candles, period: 50)!

        XCTAssertGreaterThan(lastClose, sma20)
        XCTAssertGreaterThan(sma20, sma50)

        let trend = engine.estimateTrend(from: candles, sma20: sma20, sma50: sma50)
        XCTAssertEqual(trend, .strongUp)
    }

    func testEstimateTrend_StrongDowntrend() {
        let candles = makeCandles(count: 60, baseClose: 200.0, step: -1.0)
        let lastClose = candles.last!.close

        let sma20 = engine.movingAverage(from: candles, period: 20)!
        let sma50 = engine.movingAverage(from: candles, period: 50)!

        XCTAssertLessThan(lastClose, sma20)
        XCTAssertLessThan(sma20, sma50)

        let trend = engine.estimateTrend(from: candles, sma20: sma20, sma50: sma50)
        XCTAssertEqual(trend, .strongDown)
    }

    func testEstimateTrend_NilSMA_ReturnsNil() {
        let candles = makeCandles(count: 5, baseClose: 100.0)
        let trend = engine.estimateTrend(from: candles, sma20: nil, sma50: nil)
        XCTAssertNil(trend)
    }

    func testEstimateTrend_EmptyCandles_ReturnsNil() {
        let trend = engine.estimateTrend(from: [], sma20: 100, sma50: 95)
        XCTAssertNil(trend)
    }
}
