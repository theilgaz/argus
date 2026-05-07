import Foundation

/// Plan/hedef/stop tetiklenmelerini ve council değişikliklerini kullanıcıya
/// ileten model. ExecutionStateVM + AlertManager üreterek toplar, TradeBrainView
/// ve UnifiedPositionCard render eder.
struct TradeBrainAlert: Identifiable, Equatable {
    let id = UUID()
    let timestamp = Date()
    let type: AlertType
    let symbol: String
    let message: String
    let actionDescription: String
    let priority: AlertPriority

    enum AlertType: String {
        case planTriggered = "PLAN"
        case targetReached = "HEDEF"
        case stopApproaching = "STOP_YAKIN"
        case councilChanged = "KONSEY"
    }

    enum AlertPriority: String {
        case low = "DÜŞÜK"
        case medium = "ORTA"
        case high = "YÜKSEK"
        case critical = "KRİTİK"
    }

    static func == (lhs: TradeBrainAlert, rhs: TradeBrainAlert) -> Bool {
        lhs.id == rhs.id
    }
}
