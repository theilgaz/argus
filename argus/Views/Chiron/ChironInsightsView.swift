import SwiftUI

/// Rejim öğrenme dashboard'u (eski adıyla Chiron Insights).
/// Bileşen performanslarını ve öğrenilmiş ağırlıkları gösterir.
///
/// 2026-04-30 H-58 — sade refactor.
/// Eski yapı: Theme (legacy DS) + raw .cyan/.purple/.white/.gray + emoji
/// brain icon + "Chiron Akıllı Öğrenme" başlık + caps "Win:" + cornerRadius
/// 12 yığını. Yeni: InstitutionalTheme + sentence başlık ("Rejim öğrenme") +
/// sade hairline kartlar + sentence "Yapı/Trend/Momentum..." weight isimleri.
/// Public API korundu — `init(symbol: String? = nil)`.

struct ChironInsightsView: View {
    let symbol: String?

    @State private var globalStats: [ComponentPerformanceService.ComponentStats] = []
    @State private var symbolStats: [ComponentPerformanceService.ComponentStats] = []
    @State private var learnedWeights: OrionWeightSnapshot?
    @State private var learningStatus: (hasLearning: Bool, confidence: Double, note: String)?

    init(symbol: String? = nil) {
        self.symbol = symbol
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                headerSection

                if let status = learningStatus {
                    learningStatusCard(status)
                }

                if let weights = learnedWeights {
                    learnedWeightsCard(weights)
                }

                if !symbolStats.isEmpty || !globalStats.isEmpty {
                    componentPerformanceSection
                }

                Color.clear.frame(height: 24)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
        }
        .background(InstitutionalTheme.Colors.background)
        .navigationTitle("Rejim öğrenme")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { loadData() }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Rejim öğrenme")
                .font(.system(size: 22, weight: .medium))
                .foregroundColor(InstitutionalTheme.Colors.textPrimary)
            Text(symbol != nil ? "Sembol: \(symbol!)" : "Tüm portföy")
                .font(.system(size: 13))
                .foregroundColor(InstitutionalTheme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 4)
    }

    // MARK: - Öğrenme Durumu Card

    private func learningStatusCard(_ status: (hasLearning: Bool, confidence: Double, note: String)) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Öğrenme durumu")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(InstitutionalTheme.Colors.textPrimary)

                Spacer()

                if status.hasLearning {
                    Text("%\(Int(status.confidence * 100))")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(confidenceColor(status.confidence))
                        .monospacedDigit()
                } else {
                    Text("Bekliyor")
                        .font(.system(size: 12))
                        .foregroundColor(InstitutionalTheme.Colors.textTertiary)
                }
            }

            Text(status.note)
                .font(.system(size: 12))
                .foregroundColor(InstitutionalTheme.Colors.textSecondary)

            if status.hasLearning {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(InstitutionalTheme.Colors.surface2)
                            .frame(height: 4)
                            .cornerRadius(2)

                        Rectangle()
                            .fill(confidenceColor(status.confidence))
                            .frame(width: geo.size.width * status.confidence, height: 4)
                            .cornerRadius(2)
                    }
                }
                .frame(height: 4)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(InstitutionalTheme.Colors.surface1)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(InstitutionalTheme.Colors.borderSubtle, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Öğrenilmiş Ağırlıklar Card

    private func learnedWeightsCard(_ weights: OrionWeightSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Öğrenilmiş ağırlıklar")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(InstitutionalTheme.Colors.textPrimary)

            VStack(spacing: 10) {
                weightBar(name: "Yapı",      value: weights.structure)
                weightBar(name: "Trend",     value: weights.trend)
                weightBar(name: "Momentum",  value: weights.momentum)
                weightBar(name: "Formasyon", value: weights.pattern)
                weightBar(name: "Volatilite", value: weights.volatility)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(InstitutionalTheme.Colors.surface1)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(InstitutionalTheme.Colors.borderSubtle, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func weightBar(name: String, value: Double) -> some View {
        HStack(spacing: 10) {
            Text(name)
                .font(.system(size: 12))
                .foregroundColor(InstitutionalTheme.Colors.textSecondary)
                .frame(width: 88, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(InstitutionalTheme.Colors.surface2)
                        .frame(height: 4)
                        .cornerRadius(2)

                    Rectangle()
                        .fill(InstitutionalTheme.Colors.textPrimary)
                        .frame(width: geo.size.width * min(1.0, value * 2.5), height: 4)
                        .cornerRadius(2)
                }
            }
            .frame(height: 4)

            Text("%\(Int(value * 100))")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(InstitutionalTheme.Colors.textPrimary)
                .monospacedDigit()
                .frame(width: 44, alignment: .trailing)
        }
    }

    // MARK: - Bileşen Performansı

    private var componentPerformanceSection: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Bileşen performansı")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(InstitutionalTheme.Colors.textPrimary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 8)

            let stats = symbol != nil && !symbolStats.isEmpty ? symbolStats : globalStats
            let sorted = stats.sorted(by: { $0.reliability > $1.reliability })

            VStack(spacing: 0) {
                ForEach(Array(sorted.enumerated()), id: \.element.component) { idx, stat in
                    if idx > 0 {
                        Rectangle()
                            .fill(InstitutionalTheme.Colors.borderSubtle)
                            .frame(height: 0.5)
                            .padding(.leading, 14)
                    }
                    componentRow(stat)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(InstitutionalTheme.Colors.surface1)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(InstitutionalTheme.Colors.borderSubtle, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func componentRow(_ stat: ComponentPerformanceService.ComponentStats) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(reliabilityColor(stat.reliability))
                .frame(width: 6, height: 6)

            Text(componentLabel(stat.component))
                .font(.system(size: 13))
                .foregroundColor(InstitutionalTheme.Colors.textPrimary)

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("Kazanma %\(Int(stat.winRate))")
                    .font(.system(size: 12))
                    .foregroundColor(stat.winRate > 50
                                     ? InstitutionalTheme.Colors.aurora
                                     : InstitutionalTheme.Colors.crimson)
                    .monospacedDigit()
                Text("\(stat.signalCount) sinyal")
                    .font(.system(size: 11))
                    .foregroundColor(InstitutionalTheme.Colors.textTertiary)
                    .monospacedDigit()
            }

            Text(reliabilityLabel(stat.reliability))
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(reliabilityColor(stat.reliability))
                .frame(width: 64, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    /// Mitoloji bileşen kodlarını sentence Türkçe'ye çevir.
    private func componentLabel(_ component: String) -> String {
        switch component.lowercased() {
        case "structure": return "Yapı"
        case "trend": return "Trend"
        case "momentum": return "Momentum"
        case "pattern": return "Formasyon"
        case "volatility": return "Volatilite"
        default: return component.capitalized
        }
    }

    // MARK: - Helpers

    private func loadData() {
        globalStats = ComponentPerformanceService.shared.analyzeGlobalPerformance()

        if let sym = symbol {
            symbolStats = ComponentPerformanceService.shared.analyzePerformance(for: sym)
            learnedWeights = ChironRegimeEngine.shared.getLearnedOrionWeights(symbol: sym)
            learningStatus = ChironRegimeEngine.shared.getLearningStatus(symbol: sym)
        } else {
            learnedWeights = ComponentPerformanceService.shared.calculateLearnedWeights(symbol: nil)
            let totalSignals = globalStats.reduce(0) { $0 + $1.signalCount }
            learningStatus = (totalSignals >= 10, Double(min(totalSignals, 20)) / 20.0, "\(totalSignals) trade analiz edildi")
        }
    }

    private func confidenceColor(_ value: Double) -> Color {
        if value >= 0.7 { return InstitutionalTheme.Colors.aurora }
        if value >= 0.5 { return InstitutionalTheme.Colors.titan }
        return InstitutionalTheme.Colors.crimson
    }

    private func reliabilityColor(_ value: Double) -> Color {
        if value >= 0.6 { return InstitutionalTheme.Colors.aurora }
        if value >= 0.45 { return InstitutionalTheme.Colors.titan }
        return InstitutionalTheme.Colors.crimson
    }

    private func reliabilityLabel(_ value: Double) -> String {
        if value >= 0.6 { return "Güvenilir" }
        if value >= 0.45 { return "Nötr" }
        return "Zayıf"
    }
}

#Preview {
    NavigationStack {
        ChironInsightsView(symbol: "AAPL")
    }
}
