import Foundation
import Combine
import SwiftUI

/// Risk & Portfolio Manager
/// Extracted from TradingViewModel (Phase 2)
/// Handles: Portfolio, Balance, Backtesting, Whales, ETFs
@MainActor
final class RiskViewModel: ObservableObject {
    static let shared = RiskViewModel()

    // MARK: - Portfolio State
    @Published var portfolio: [Trade] = []
    @Published var balance: Double = 100000.0 // USD Balance
    @Published var bistBalance: Double = 1000000.0 // 1M TL BIST demo balance
    @Published var usdTryRate: Double = 35.0
    @Published var transactionHistory: [Transaction] = []
    
    // MARK: - Risk & Analysis Data
    @Published var activeBacktestResult: BacktestResult?
    
    // Orion SAR+TSI Lab
    @Published var sarTsiBacktestResult: OrionSarTsiBacktestResult?
    @Published var isLoadingSarTsiBacktest: Bool = false
    @Published var sarTsiErrorMessage: String?
    
    // Poseidon (Whale)
    @Published var poseidonWhaleScores: [String: WhaleScore] = [:]
    
    // ETF Summaries
    @Published var etfSummaries: [String: ArgusEtfSummary] = [:]
    @Published var isLoadingEtf = false

    init() {
        let store = PortfolioStore.shared
        store.$trades.assign(to: &$portfolio)
        store.$globalBalance.assign(to: &$balance)
        store.$bistBalance.assign(to: &$bistBalance)
        store.$transactions.assign(to: &$transactionHistory)
    }
    
    // Logic for loading ETFs or Whales could move here in future steps.
}
