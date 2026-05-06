import Foundation

// MARK: - Aether Council
/// The Macro Council - evaluates market conditions and macro environment.
///
/// ⚠️ **DEPRECATED — 2026-05-05 (Round 7B):** Production karar yolundan çıkarıldı.
/// `ArgusGrandCouncil` artık `AetherV2Engine` + `AetherV2DecisionAdapter` çağırıyor.
/// Bu sınıf hâlâ derlenir, 2026-Q3'te kaldırılacak.
///
/// Yeni motor: `argus/Services/AetherV2/AetherV2Engine.swift`
/// - 5 İngilizce "Engine" (MonetaryPolicy/MarketSentiment/SectorRotation/EconomicCycle/CrossAsset)
///   yerine 5 Türkçe bölüm (Likidite/Risk Modu/Sektör Rotasyonu/Cross-Asset/Hissiyat)
/// - Static heuristic yerine MacroSnapshot field-bazlı section skorları
/// - Veri eksikse "Makro veri yetersiz" warning (silent fail değil)
@available(*, deprecated, message: "AetherV2Engine kullan. Bu sınıf 2026-Q3'te kaldırılacak.")
actor AetherCouncil {
    static let shared = AetherCouncil()
    
    private let members: [any MacroCouncilMember]
    
    private init() {
        self.members = [
            MonetaryPolicyEngine(),
            MarketSentimentEngine(),
            SectorRotationEngine(),
            EconomicCycleEngine(),
            CrossAssetEngine()
        ]
    }
    
    // MARK: - Public API
    
    func convene(macro: MacroSnapshot) async -> AetherDecision {
        let timestamp = Date()
        
        print("🏛️ Aether Konseyi Toplanıyor")
        
        // 1. Collect proposals
        let proposals = await collectProposals(macro: macro)
        print("   📋 \(proposals.count) öneri toplandı")
        
        // 2. Default stance based on market mode
        let defaultStance: MacroStance
        switch macro.marketMode {
        case .panic, .extremeFear:
            defaultStance = .riskOff
        case .fear:
            defaultStance = .defensive
        case .complacency, .extremeGreed:
            defaultStance = .cautious
        default:
            defaultStance = .cautious
        }
        
        // 3. If no proposals, return default
        guard !proposals.isEmpty else {
            return AetherDecision(
                stance: defaultStance,
                marketMode: macro.marketMode,
                netSupport: 0,
                isStrongSignal: false,
                winningProposal: nil,
                votes: [],
                warnings: [],
                timestamp: timestamp
            )
        }
        
        // 4. Best proposal
        let bestProposal = proposals.max(by: { $0.confidence < $1.confidence })!
        print("   🎯 En iyi öneri: \(bestProposal.proposerName) → \(bestProposal.stance.rawValue)")
        
        // 5. Voting
        let votes = conductVoting(proposal: bestProposal, macro: macro)
        
        // 6. Calculate decision
        let decision = calculateDecision(
            proposal: bestProposal,
            votes: votes,
            marketMode: macro.marketMode,
            timestamp: timestamp
        )
        
        print("   📊 Sonuç: \(decision.summary)")
        
        return decision
    }
    
    // MARK: - Proposal Collection
    
    private func collectProposals(macro: MacroSnapshot) async -> [MacroProposal] {
        var proposals: [MacroProposal] = []
        
        for member in members {
            if let proposal = await member.analyze(macro: macro) {
                proposals.append(proposal)
            }
        }
        
        return proposals
    }
    
    // MARK: - Voting
    
    private func conductVoting(proposal: MacroProposal, macro: MacroSnapshot) -> [MacroVote] {
        var votes: [MacroVote] = []
        let weights = AetherMemberWeights.defaultWeights
        
        for member in members {
            if member.id == proposal.proposer { continue }
            
            var vote = member.vote(on: proposal, macro: macro)
            let memberWeight = weights.weight(for: member.id)
            vote = MacroVote(
                voter: vote.voter,
                voterName: vote.voterName,
                decision: vote.decision,
                reasoning: vote.reasoning,
                weight: memberWeight * vote.weight
            )
            
            votes.append(vote)
            print("      \(vote.decision.emoji) \(vote.voterName): \(vote.decision.rawValue) - \(vote.reasoning ?? "")")
        }
        
        return votes
    }
    
    // MARK: - Decision
    
    private func calculateDecision(
        proposal: MacroProposal,
        votes: [MacroVote],
        marketMode: MarketMode,
        timestamp: Date
    ) -> AetherDecision {
        
        var approveWeight = 0.0
        var vetoWeight = 0.0
        var warnings: [String] = []
        
        for vote in votes {
            switch vote.decision {
            case .approve:
                approveWeight += vote.weight
            case .veto:
                vetoWeight += vote.weight
                if let reason = vote.reasoning {
                    warnings.append("\(vote.voterName): \(reason)")
                }
            case .abstain:
                break
            }
        }
        
        approveWeight += proposal.confidence * 0.5
        let netSupport = approveWeight - vetoWeight
        let isStrongSignal = netSupport >= 0.30
        
        let finalStance: MacroStance
        if netSupport >= 0.10 {
            finalStance = proposal.stance
        } else if vetoWeight > 0.40 {
            // Strong opposition - go defensive
            finalStance = .defensive
        } else {
            finalStance = .cautious
        }
        
        return AetherDecision(
            stance: finalStance,
            marketMode: marketMode,
            netSupport: netSupport,
            isStrongSignal: isStrongSignal,
            winningProposal: proposal,
            votes: votes,
            warnings: warnings,
            timestamp: timestamp
        )
    }
}
