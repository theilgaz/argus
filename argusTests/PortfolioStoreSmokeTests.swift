import XCTest
@testable import argus

/// PortfolioStore davranış kontratı smoke testleri.
///
/// God Object Aşama B — Adım B.3: extension-based decomposition öncesi/sonrası
/// davranışın 1:1 korunduğunu kanıtlayan test ızgarası. Bu testler refactor
/// sırasında "veri sessizce bozuldu" senaryosunu engeller (lessons L87).
///
/// Kapsam:
/// - buy: trade ekleme + balance düşme + guard'lar
/// - sell: kapatma + revenue + PnL
/// - trim: kısmi satış
/// - handleQuoteUpdates: SL/TP tetikleyicileri (hot path)
/// - valuation: getGlobalEquity, getRealizedPnL
///
/// Kapsam dışı (cascade async work test edilmez):
/// - Chiron/Council/TradeBrain/RAG learning hooks (Task.detached, sync return değer test edilebilir)
/// - V5→V6 persistence migration (UserDefaults state mutation, ayrı test fixture gerek)
/// - Cross-process disk I/O race condition'ları
@MainActor
final class PortfolioStoreSmokeTests: XCTestCase {

    let store = PortfolioStore.shared

    override func setUp() async throws {
        try await super.setUp()
        // Test isolation — her test temiz portföyle başlasın.
        store.resetPortfolio()
        store.flushNow()
    }

    // MARK: - Buy

    func testBuy_AddsTradeAndDeductsBalance() {
        let initialBalance = store.globalBalance
        let trade = store.buy(symbol: "AAPL", quantity: 10, price: 150)

        XCTAssertNotNil(trade)
        XCTAssertEqual(store.openTrades.count, 1)
        XCTAssertEqual(store.openTrades.first?.symbol, "AAPL")
        XCTAssertEqual(store.openTrades.first?.quantity ?? 0, 10, accuracy: 0.0001)

        // 10 * 150 = 1500 cost + commission. Balance kesin 1500'den fazla düştü.
        XCTAssertLessThan(store.globalBalance, initialBalance - 1499)
    }

    func testBuy_RejectsZeroQuantity() {
        let trade = store.buy(symbol: "AAPL", quantity: 0, price: 150)
        XCTAssertNil(trade)
        XCTAssertEqual(store.openTrades.count, 0)
    }

    func testBuy_RejectsZeroPrice() {
        let trade = store.buy(symbol: "AAPL", quantity: 10, price: 0)
        XCTAssertNil(trade)
        XCTAssertEqual(store.openTrades.count, 0)
    }

    // MARK: - Sell

    func testSell_ClosesTradeAndAddsRevenueToBalance() {
        guard let trade = store.buy(symbol: "AAPL", quantity: 10, price: 150) else {
            XCTFail("Buy başarısız")
            return
        }
        let balanceAfterBuy = store.globalBalance

        let pnl = store.sell(tradeId: trade.id, currentPrice: 160)
        XCTAssertNotNil(pnl)
        // 10 * 10 = 100 gross gain. Commission davranışına göre 90-100 aralığı.
        XCTAssertGreaterThan(pnl!, 90)
        XCTAssertLessThanOrEqual(pnl!, 100)

        XCTAssertEqual(store.openTrades.count, 0)
        XCTAssertEqual(store.closedTrades.count, 1)
        XCTAssertEqual(store.closedTrades.first?.exitPrice, 160)
        XCTAssertGreaterThan(store.globalBalance, balanceAfterBuy)
    }

    func testSell_NonexistentTradeReturnsNil() {
        let result = store.sell(tradeId: UUID(), currentPrice: 100)
        XCTAssertNil(result)
    }

    // MARK: - Trim

    func testTrim_ReducesQuantityKeepsTradeOpen() {
        guard let trade = store.buy(symbol: "AAPL", quantity: 10, price: 150) else {
            XCTFail("Buy başarısız")
            return
        }

        let pnl = store.trim(tradeId: trade.id, percentage: 50, currentPrice: 160)
        XCTAssertNotNil(pnl)
        XCTAssertGreaterThan(pnl!, 0)  // 50% kazanç realized

        let updated = store.openTrades.first { $0.id == trade.id }
        XCTAssertNotNil(updated)
        XCTAssertEqual(updated?.quantity ?? 0, 5, accuracy: 0.0001)
        XCTAssertEqual(updated?.isOpen, true)
    }

    func testTrim_RejectsInvalidPercentage() {
        guard let trade = store.buy(symbol: "AAPL", quantity: 10, price: 150) else {
            XCTFail()
            return
        }
        XCTAssertNil(store.trim(tradeId: trade.id, percentage: 0, currentPrice: 160))
        XCTAssertNil(store.trim(tradeId: trade.id, percentage: 100, currentPrice: 160))
        XCTAssertNil(store.trim(tradeId: trade.id, percentage: -10, currentPrice: 160))
    }

    // MARK: - handleQuoteUpdates (Hot Path)

    func testHandleQuoteUpdates_TriggersStopLoss() {
        guard let trade = store.buy(
            symbol: "AAPL",
            quantity: 10,
            price: 150,
            stopLoss: 140
        ) else {
            XCTFail("Buy başarısız")
            return
        }

        // Quote currentPrice 135 → SL (140) tetiklenmeli
        let belowStop = Quote(
            c: 135, d: nil, dp: nil, currency: "USD",
            shortName: nil, symbol: "AAPL", previousClose: 150
        )
        store.handleQuoteUpdates(["AAPL": .fresh(belowStop)])

        let result = store.trades.first { $0.id == trade.id }
        XCTAssertEqual(result?.isOpen, false, "SL altında trade kapatılmalı")
    }

    func testHandleQuoteUpdates_TriggersTakeProfit() {
        guard let trade = store.buy(
            symbol: "AAPL",
            quantity: 10,
            price: 150,
            takeProfit: 165
        ) else {
            XCTFail()
            return
        }

        let aboveTP = Quote(
            c: 170, d: nil, dp: nil, currency: "USD",
            shortName: nil, symbol: "AAPL", previousClose: 150
        )
        store.handleQuoteUpdates(["AAPL": .fresh(aboveTP)])

        let result = store.trades.first { $0.id == trade.id }
        XCTAssertEqual(result?.isOpen, false, "TP üstünde trade kapatılmalı")
    }

    func testHandleQuoteUpdates_NoTriggerWhenInsideRange() {
        guard let trade = store.buy(
            symbol: "AAPL", quantity: 10, price: 150,
            stopLoss: 140, takeProfit: 160
        ) else {
            XCTFail()
            return
        }

        // 145 — SL (140) ile TP (160) arasında
        let inRange = Quote(
            c: 145, d: nil, dp: nil, currency: "USD",
            shortName: nil, symbol: "AAPL", previousClose: 150
        )
        store.handleQuoteUpdates(["AAPL": .fresh(inRange)])

        let result = store.trades.first { $0.id == trade.id }
        XCTAssertEqual(result?.isOpen, true, "Aralık içinde trade açık kalmalı")
    }

    // MARK: - Valuation

    func testGetGlobalEquity_IncludesOpenPositions() {
        let initialBalance = store.globalBalance
        guard store.buy(symbol: "AAPL", quantity: 10, price: 150) != nil else {
            XCTFail()
            return
        }

        let quote = Quote(
            c: 160, d: nil, dp: nil, currency: "USD",
            shortName: nil, symbol: "AAPL", previousClose: 150
        )
        let equity = store.getGlobalEquity(quotes: ["AAPL": quote])

        // equity = balance (after buy) + (10 * 160 = 1600)
        // balance after buy ≈ initialBalance - 1500 - commission
        // equity ≈ initialBalance - commission + 100 (gain)
        XCTAssertGreaterThan(equity, initialBalance + 90)
        XCTAssertLessThan(equity, initialBalance + 105)
    }

    func testGetRealizedPnL_SumsClosedSells() {
        guard let trade = store.buy(symbol: "AAPL", quantity: 10, price: 150) else {
            XCTFail()
            return
        }
        _ = store.sell(tradeId: trade.id, currentPrice: 160)

        let pnl = store.getRealizedPnL(currency: .USD)
        XCTAssertGreaterThan(pnl, 90)
        XCTAssertLessThanOrEqual(pnl, 100)
    }
}
