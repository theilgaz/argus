import Foundation
import Combine
import SwiftUI

/// AppStateCoordinator+Bindings
/// Sets up proper Combine bindings between AppStateCoordinator and child stores/ViewModels
///
/// 2026-05-06 — Aşama A refactor: typed state struct'lara migration sonrası,
/// `assign(to: &$X)` pattern'i (publisher → @Published) struct field'larına
/// doğrudan kullanılamaz. `sink` ile setter pattern'e geçildi.
extension AppStateCoordinator {

    /// Sets up all data bindings from child stores to coordinator properties
    func setupDataBindings() {
        setupWatchlistBindings()
        setupMarketBindings()
        setupExecutionBindings()
        setupLoadingAggregation()
    }

    // MARK: - Watchlist

    private func setupWatchlistBindings() {
        WatchlistViewModel.shared.$watchlist
            .dropFirst()
            .sink { [weak self] symbols in
                Task { @MainActor in
                    for symbol in symbols {
                        if self?.watchlistQuotes[symbol] == nil {
                            await self?.watchlist.loadQuote(for: symbol)
                        }
                    }
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Market Data

    private func setupMarketBindings() {
        MarketDataStore.shared.$quotes
            .receive(on: RunLoop.main)
            .sink { [weak self] storeQuotes in
                self?.portfolio.handleQuoteUpdates(storeQuotes)
            }
            .store(in: &cancellables)
    }

    // MARK: - Execution State
    // AppStateCoordinator is the SINGLE SUBSCRIBER to ExecutionStateViewModel.
    // TradingViewModel reads these from coordinator (not directly from ExecutionStateViewModel).

    private func setupExecutionBindings() {
        ExecutionStateViewModel.shared.$planAlerts
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.executionMirror.planAlerts = $0 }
            .store(in: &cancellables)

        ExecutionStateViewModel.shared.$agoraSnapshots
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.executionMirror.agoraSnapshots = $0 }
            .store(in: &cancellables)

        ExecutionStateViewModel.shared.$lastTradeTimes
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.executionMirror.lastTradeTimes = $0 }
            .store(in: &cancellables)
    }

    // MARK: - Loading State Aggregation

    private func setupLoadingAggregation() {
        Publishers.CombineLatest4(
            WatchlistViewModel.shared.$isLoading,
            SignalStateViewModel.shared.$isOrionLoading,
            $environment.map(\.isLoadingEtf).removeDuplicates(),
            $backtest.map(\.isLoadingSarTsi).removeDuplicates()
        )
        .map { $0 || $1 || $2 || $3 }
        .receive(on: RunLoop.main)
        .sink { [weak self] aggregated in
            self?.environment.isGlobalLoading = aggregated
        }
        .store(in: &cancellables)
    }
}
