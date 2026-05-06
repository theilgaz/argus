import Foundation
import Combine

/// Trade execution error tracking + decision context building (audit trail).
/// God Object Aşama A — ExecutionStateViewModel'den çıkarıldı.
@MainActor
final class ExecutionLogger: ObservableObject {
    static let shared = ExecutionLogger()

    /// Last trade execution error — UI surface.
    @Published var lastTradeError: String? = nil

    /// Symbol → last trade time. AGORA cooldown ve recency check'leri için.
    @Published var lastTradeTimes: [String: Date] = [:]

    private init() {}

    /// 2026-05-04: "Simplified for now" stub'ları kaldırıldı. moduleVotes'ta
    /// gerçek veri üretiliyor — trade detay ekranında modül skorları artık dolu.
    func makeDecisionContext(fromTrace trace: DecisionTraceSnapshot) -> DecisionContext {
        return DecisionContext(
            decisionId: UUID().uuidString,
            overallAction: "BUY",
            dominantSignals: trace.reasonsTop3.compactMap { $0.note },
            conflicts: [],
            moduleVotes: ModuleVotes(
                atlas:  ModuleVote(score: trace.scores.atlas  ?? 50, direction: "BUY",     confidence: (trace.scores.atlas  ?? 50) / 100),
                orion:  ModuleVote(score: trace.scores.orion  ?? 50, direction: "BUY",     confidence: (trace.scores.orion  ?? 50) / 100),
                aether: ModuleVote(score: trace.scores.aether ?? 50, direction: "NEUTRAL", confidence: 0.5),
                hermes: ModuleVote(score: trace.scores.hermes ?? 50, direction: "NEUTRAL", confidence: 0.5),
                chiron: nil
            )
        )
    }

    func makeDecisionContext(from snapshot: DecisionSnapshot) -> DecisionContext {
        let findVote: (String) -> ModuleVote? = { module in
            guard let ev = snapshot.evidence.first(where: { $0.module == module }) else { return nil }
            return ModuleVote(score: ev.confidence, direction: ev.direction, confidence: ev.confidence)
        }

        return DecisionContext(
            decisionId: snapshot.id.uuidString,
            overallAction: snapshot.action.rawValue,
            dominantSignals: snapshot.dominantSignals,
            conflicts: snapshot.conflicts.map {
                DecisionConflict(moduleA: $0.moduleA, moduleB: $0.moduleB, topic: $0.topic, severity: 0.5)
            },
            moduleVotes: ModuleVotes(
                atlas:  findVote("Atlas"),
                orion:  findVote("Orion"),
                aether: findVote("Aether"),
                hermes: findVote("Hermes"),
                chiron: findVote("Chiron")
            )
        )
    }
}
