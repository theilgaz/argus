import Foundation
import Combine

// MARK: - SSoT Store Bindings (extracted from TradingViewModel)
//
// 2026-05-06 — Aşama A 4B: Eski sink relay subscription'ları silindi.
//
// Niye: TVM'in mirror @Published'ları (planAlerts, agoraSnapshots,
// lastTradeTimes, universeCache, lastAction) computed pass-through'a
// dönüştürüldü — artık AppStateCoordinator/HermesNewsViewModel'den
// doğrudan okunuyorlar. Çift state ve circular relay ortadan kalktı.
//
// Geride sadece child VM'lerin objectWillChange'ını parent'a forward
// eden minimum relay kaldı (L61: computed property reaktif zinciri).

extension TradingViewModel {

    func setupStoreBindings() {
        // Child VM objectWillChange relay — TVM'i observe eden view'lar
        // child değişimlerinde re-render olsun (planAlerts, agoraSnapshots,
        // lastTradeTimes, universeCache vb. computed pass-through olduğu için
        // parent'ın objectWillChange'ı otomatik tetiklenmez).
        AppStateCoordinator.shared.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)

        HermesNewsViewModel.shared.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)

        AlertManager.shared.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)

        ScanOrchestrator.shared.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)

        ExecutionLogger.shared.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }
}
