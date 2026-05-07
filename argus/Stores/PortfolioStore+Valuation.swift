import Foundation

// MARK: - Portfolio Valuation Helpers
/// PortfolioStore'un equity ve P&L hesaplamaları. Read-only — state mutate etmez.
/// Caller'lar quote map'i geçer, helper hesaplama yapar.
extension PortfolioStore {

    func getGlobalEquity(quotes: [String: Quote]) -> Double {
        let positionValue = globalOpenTrades.reduce(0.0) { sum, trade in
            let currentPrice = quotes[trade.symbol]?.currentPrice ?? trade.entryPrice
            return sum + (trade.quantity * currentPrice)
        }
        return globalBalance + positionValue
    }

    func getBistEquity(quotes: [String: Quote]) -> Double {
        let positionValue = bistOpenTrades.reduce(0.0) { sum, trade in
            let currentPrice = quotes[trade.symbol]?.currentPrice ?? trade.entryPrice
            return sum + (trade.quantity * currentPrice)
        }
        return bistBalance + positionValue
    }

    func getGlobalUnrealizedPnL(quotes: [String: Quote]) -> Double {
        globalOpenTrades.reduce(0.0) { sum, trade in
            let currentPrice = quotes[trade.symbol]?.currentPrice ?? trade.entryPrice
            return sum + ((currentPrice - trade.entryPrice) * trade.quantity)
        }
    }

    func getBistUnrealizedPnL(quotes: [String: Quote]) -> Double {
        bistOpenTrades.reduce(0.0) { sum, trade in
            let currentPrice = quotes[trade.symbol]?.currentPrice ?? trade.entryPrice
            return sum + ((currentPrice - trade.entryPrice) * trade.quantity)
        }
    }

    func getRealizedPnL(currency: Currency? = nil) -> Double {
        let relevantTransactions: [Transaction]
        if let currency = currency {
            relevantTransactions = transactions.filter { tx in
                guard tx.type == .sell, let _ = tx.pnl else { return false }
                let isBist = isBistSymbol(tx.symbol)
                return currency == .TRY ? isBist : !isBist
            }
        } else {
            relevantTransactions = transactions.filter { $0.type == .sell }
        }
        return relevantTransactions.compactMap { $0.pnl }.reduce(0.0, +)
    }
}
