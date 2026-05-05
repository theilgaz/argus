import SwiftUI

/// Pozisyon detay ekranı — portföyde bir hisseye tıklayınca açılır.
///
/// 2026-05-04 H-61 — tasarımın kralı sade refactor (önceden 602 satır,
/// 7 ayrı section, 42pt heavy mono sembol, 40pt mono PnL, "POPÜLER"
/// caps, motor ikonları + renkli section başlıkları, gölgeli kırmızı
/// kapat butonu vardı).
///
/// Yeni yapı (~340 satır, 6 sade kart):
///   1. Üst nav — back / sembol / xmark
///   2. Künye (kompakt) — logo + isim/durum + anlık fiyat + günlük %
///   3. K/Z hero kartı — büyük tutar + yüzde + giriş/adet/değer detay
///   4. Plan kartı — adım sayısı + bar + sıradaki adım + Stop/Hedef/R/R
///   5. Tez kartı — tez + geçersizlik
///   6. Konsey kartı — verdict + güven + 4 modül bar listesi
///   7. Senaryo kartı — aktif highlighted, diğerleri muted (varsa)
///   8. Risk uyarısı — eventRisk shouldAvoid/shouldReduce ise
///   9. İki butonlu alt — "Planı düzenle" outline + "Pozisyonu kapat" outline
///
/// Veri kaynakları:
///   • Trade modeli — entryPrice, quantity, entryDate, source, currency
///   • Quote — currentPrice, percentChange (günlük)
///   • PositionPlan — thesis, invalidation, scenarios, nextPendingStep,
///                    completedStepCount, totalStepCount, intent
///   • EntrySnapshot (plan.originalSnapshot) — councilAction/Confidence,
///                    orionScore, atlasScore (gerçek), aetherStance,
///                    hermesScore (gerçek)
///   • EventCalendarService — shouldAvoidNewPosition, shouldReducePosition
///
/// Public API korundu: `init(trade:, viewModel:)`.

struct TradeDetailSheet: View {
    let trade: Trade
    @ObservedObject var viewModel: TradingViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var plan: PositionPlan?
    @State private var eventRisk: EventCalendarService.EventRiskAssessment?
    @State private var showPlanEditor = false

    // MARK: - Computed

    private var quote: Quote? {
        viewModel.quotes[trade.symbol]
    }

    private var currentPrice: Double {
        quote?.currentPrice ?? trade.entryPrice
    }

    private var pnlValue: Double {
        (currentPrice - trade.entryPrice) * trade.quantity
    }

    private var pnlPercent: Double {
        guard trade.entryPrice > 0 else { return 0 }
        return ((currentPrice - trade.entryPrice) / trade.entryPrice) * 100
    }

    private var pnlColor: Color {
        pnlValue >= 0 ? InstitutionalTheme.Colors.aurora : InstitutionalTheme.Colors.crimson
    }

    private var holdingDays: Int {
        Calendar.current.dateComponents([.day], from: trade.entryDate, to: Date()).day ?? 0
    }

    private var snapshot: EntrySnapshot? {
        plan?.originalSnapshot ?? EntrySnapshotStore.shared.getSnapshot(for: trade.id)
    }

    private var nextStep: PlannedAction? {
        plan?.nextPendingStep
    }

    private var suggestedStop: Double? {
        guard let plan else { return nil }
        let bearishSteps = plan.bearishScenario.steps.sorted { $0.priority < $1.priority }
        for step in bearishSteps {
            if let price = triggerPrice(step.trigger) {
                return price
            }
        }
        return nil
    }

    private var suggestedTarget: Double? {
        guard let plan else { return nil }
        let bullishSteps = plan.bullishScenario.steps.sorted { $0.priority < $1.priority }
        for step in bullishSteps {
            if let price = triggerPrice(step.trigger) {
                return price
            }
        }
        return nil
    }

    private var riskRewardText: String? {
        guard let stop = suggestedStop, let target = suggestedTarget,
              trade.entryPrice > stop else { return nil }
        let risk = trade.entryPrice - stop
        guard risk > 0 else { return nil }
        let reward = target - trade.entryPrice
        guard reward > 0 else { return nil }
        return String(format: "1 : %.2f", reward / risk)
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            topNav
            ScrollView {
                VStack(spacing: 12) {
                    identityCard
                    pnlCard
                    if plan != nil { planCard }
                    if let plan, !plan.thesis.isEmpty { thesisCard(plan) }
                    if snapshot != nil { councilCard }
                    if let plan, !plan.orderedScenarios.isEmpty { scenarioCard(plan) }
                    if let eventRisk, hasEventWarning(eventRisk) { riskWarningCard(eventRisk) }
                    actionButtons
                    Color.clear.frame(height: 32)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
        }
        .background(InstitutionalTheme.Colors.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onAppear(perform: loadContext)
        .sheet(isPresented: $showPlanEditor) {
            if let plan = plan {
                PlanEditorSheet(
                    trade: trade,
                    currentPrice: currentPrice,
                    plan: plan
                )
                .preferredColorScheme(.dark)
            }
        }
    }

    // MARK: - 1. Top nav

    private var topNav: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(InstitutionalTheme.Colors.textPrimary)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer()

            Text(cleanedSymbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(InstitutionalTheme.Colors.textPrimary)

            Spacer()

            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 14))
                    .foregroundColor(InstitutionalTheme.Colors.textSecondary)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(InstitutionalTheme.Colors.borderSubtle)
                .frame(height: 0.5)
        }
    }

    // MARK: - 2. Künye

    private var identityCard: some View {
        HStack(spacing: 12) {
            CompanyLogoView(symbol: trade.symbol, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(InstitutionalTheme.Colors.textPrimary)
                    .lineLimit(1)
                Text(subtitleText)
                    .font(.system(size: 12))
                    .foregroundColor(InstitutionalTheme.Colors.textSecondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(formatCurrency(currentPrice))
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(InstitutionalTheme.Colors.textPrimary)
                    .monospacedDigit()
                if let q = quote {
                    Text(String(format: "%+.2f%% bugün", q.percentChange))
                        .font(.system(size: 11))
                        .foregroundColor(q.percentChange >= 0
                                         ? InstitutionalTheme.Colors.aurora
                                         : InstitutionalTheme.Colors.crimson)
                        .monospacedDigit()
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - 3. K/Z hero

    private var pnlCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Net K/Z")
                        .font(.system(size: 11))
                        .foregroundColor(InstitutionalTheme.Colors.textTertiary)
                    Text((pnlValue >= 0 ? "+" : "") + formatCurrency(pnlValue))
                        .font(.system(size: 28, weight: .medium))
                        .foregroundColor(pnlColor)
                        .monospacedDigit()
                }
                Spacer()
                Text(String(format: "%@%.2f%%", pnlPercent >= 0 ? "+" : "", pnlPercent))
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(pnlColor)
                    .monospacedDigit()
            }

            Rectangle()
                .fill(InstitutionalTheme.Colors.borderSubtle)
                .frame(height: 0.5)
                .padding(.vertical, 12)

            HStack(spacing: 14) {
                detailColumn(title: "Giriş", value: formatCurrency(trade.entryPrice))
                detailColumn(title: "Adet", value: formatQuantity(trade.quantity))
                detailColumn(title: "Değer", value: formatCurrency(currentPrice * trade.quantity))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private func detailColumn(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 11))
                .foregroundColor(InstitutionalTheme.Colors.textTertiary)
            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(InstitutionalTheme.Colors.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 4. Plan kartı

    private var planCard: some View {
        guard let plan else { return AnyView(EmptyView()) }

        return AnyView(
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Plan")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(InstitutionalTheme.Colors.textSecondary)
                    Spacer()
                    Text("\(plan.completedStepCount) / \(plan.totalStepCount) adım")
                        .font(.system(size: 12))
                        .foregroundColor(InstitutionalTheme.Colors.textTertiary)
                        .monospacedDigit()
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(InstitutionalTheme.Colors.surface2)
                            .frame(height: 4)
                        Rectangle()
                            .fill(InstitutionalTheme.Colors.holo)
                            .frame(width: geo.size.width * plan.completionRatio, height: 4)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
                }
                .frame(height: 4)

                if let nextStep {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Sıradaki adım")
                            .font(.system(size: 11))
                            .foregroundColor(InstitutionalTheme.Colors.textTertiary)
                        Text("\(nextStep.trigger.displayText) → \(nextStep.action.displayText)")
                            .font(.system(size: 13))
                            .foregroundColor(InstitutionalTheme.Colors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                            .lineSpacing(2)
                    }
                }

                HStack(spacing: 8) {
                    metricTile(title: "Stop",
                               value: suggestedStop.map(formatCurrency) ?? "—",
                               color: InstitutionalTheme.Colors.crimson)
                    metricTile(title: "Hedef",
                               value: suggestedTarget.map(formatCurrency) ?? "—",
                               color: InstitutionalTheme.Colors.aurora)
                    metricTile(title: "R/R",
                               value: riskRewardText ?? "—",
                               color: InstitutionalTheme.Colors.titan)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBackground)
        )
    }

    private func metricTile(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 11))
                .foregroundColor(InstitutionalTheme.Colors.textTertiary)
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(color)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(InstitutionalTheme.Colors.surface2)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - 5. Tez kartı

    private func thesisCard(_ plan: PositionPlan) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tez")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(InstitutionalTheme.Colors.textSecondary)
            Text(plan.thesis)
                .font(.system(size: 13))
                .foregroundColor(InstitutionalTheme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)

            if !plan.invalidation.isEmpty {
                Rectangle()
                    .fill(InstitutionalTheme.Colors.borderSubtle)
                    .frame(height: 0.5)
                    .padding(.vertical, 4)
                Text("Geçersizlik")
                    .font(.system(size: 11))
                    .foregroundColor(InstitutionalTheme.Colors.textTertiary)
                Text(plan.invalidation)
                    .font(.system(size: 12))
                    .foregroundColor(InstitutionalTheme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    // MARK: - 6. Konsey kartı (gerçek modül skorları)

    private var councilCard: some View {
        guard let snap = snapshot else { return AnyView(EmptyView()) }

        return AnyView(
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Konsey kararı")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(InstitutionalTheme.Colors.textSecondary)
                    Spacer()
                    Text("\(councilLabel(snap.councilAction)) · güven %\(Int(snap.councilConfidence * 100))")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(councilColor(snap.councilAction))
                        .monospacedDigit()
                }

                Rectangle()
                    .fill(InstitutionalTheme.Colors.borderSubtle)
                    .frame(height: 0.5)

                VStack(spacing: 8) {
                    moduleRow(name: "Bilanço",
                              score: snap.atlasScore,
                              suffix: nil)
                    moduleRow(name: "Teknik",
                              score: snap.orionScore,
                              suffix: nil)
                    macroRow(stance: snap.aetherStance)
                    moduleRow(name: "Haber",
                              score: snap.hermesScore,
                              suffix: nil)
                }

                if !snap.councilReasoning.isEmpty {
                    Rectangle()
                        .fill(InstitutionalTheme.Colors.borderSubtle)
                        .frame(height: 0.5)
                        .padding(.top, 2)
                    Text(snap.councilReasoning)
                        .font(.system(size: 12))
                        .foregroundColor(InstitutionalTheme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineSpacing(2)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBackground)
        )
    }

    private func moduleRow(name: String, score: Double?, suffix: String?) -> some View {
        Group {
            if let s = score {
                let normalized = max(0, min(1, s / 100))
                let color = scoreColorForRate(normalized)
                HStack(spacing: 10) {
                    Text(name)
                        .font(.system(size: 12))
                        .foregroundColor(InstitutionalTheme.Colors.textSecondary)
                        .frame(width: 76, alignment: .leading)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(InstitutionalTheme.Colors.surface2)
                            Rectangle()
                                .fill(color)
                                .frame(width: geo.size.width * normalized)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
                    }
                    .frame(height: 4)
                    Text("\(Int(s))")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(color)
                        .monospacedDigit()
                        .frame(width: 32, alignment: .trailing)
                }
            } else {
                EmptyView()
            }
        }
    }

    private func macroRow(stance: MacroStance) -> some View {
        HStack(spacing: 10) {
            Text("Makro")
                .font(.system(size: 12))
                .foregroundColor(InstitutionalTheme.Colors.textSecondary)
                .frame(width: 76, alignment: .leading)
            Spacer()
            Text(stanceLabel(stance))
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(stanceColor(stance))
        }
    }

    // MARK: - 7. Senaryo kartı

    private func scenarioCard(_ plan: PositionPlan) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Senaryolar")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(InstitutionalTheme.Colors.textSecondary)

            HStack(spacing: 6) {
                ForEach(plan.orderedScenarios) { scenario in
                    let isActive = scenario.isActive
                    Text("\(isActive ? "Aktif: " : "")\(scenarioLabel(scenario.type))")
                        .font(.system(size: 11, weight: isActive ? .medium : .regular))
                        .foregroundColor(isActive ? scenarioColor(scenario.type) : InstitutionalTheme.Colors.textTertiary)
                        .padding(.horizontal, isActive ? 8 : 4)
                        .padding(.vertical, 3)
                        .background(
                            Capsule().fill(isActive
                                           ? scenarioColor(scenario.type).opacity(0.16)
                                           : Color.clear)
                        )
                }
            }

            if let active = plan.activeScenario {
                let total = active.steps.count
                let done = active.steps.filter { plan.executedSteps.contains($0.id) }.count
                Text("\(scenarioLabel(active.type)) senaryosunda \(total) adımdan \(done) tamamlandı.")
                    .font(.system(size: 12))
                    .foregroundColor(InstitutionalTheme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    // MARK: - 8. Risk uyarısı

    private func riskWarningCard(_ risk: EventCalendarService.EventRiskAssessment) -> some View {
        // Gerçek warning mesajları (örn. "⚠️ Bilanço yarın/bugün!"). Birden
        // fazla varsa hepsini liste olarak göster, ilk 3 ile sınırla.
        let messages: [String] = {
            if !risk.warnings.isEmpty {
                return Array(risk.warnings.prefix(3))
            }
            if risk.shouldAvoidNewPosition {
                return ["Yüksek riskli olay yaklaşıyor — yeni pozisyon önerilmez."]
            }
            if risk.shouldReducePosition {
                return ["Olay riski artıyor — pozisyon küçültme düşünülebilir."]
            }
            return []
        }()

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 13))
                    .foregroundColor(InstitutionalTheme.Colors.titan)
                Text("Risk uyarısı")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(InstitutionalTheme.Colors.titan)
                Spacer()
            }

            ForEach(messages, id: \.self) { msg in
                Text(msg)
                    .font(.system(size: 12))
                    .foregroundColor(InstitutionalTheme.Colors.titan)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(11)
        .background(InstitutionalTheme.Colors.titan.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(InstitutionalTheme.Colors.titan.opacity(0.3), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - 9. Aksiyon butonları

    private var actionButtons: some View {
        HStack(spacing: 8) {
            Button(action: { showPlanEditor = true }) {
                Text("Planı düzenle")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(InstitutionalTheme.Colors.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(InstitutionalTheme.Colors.surface1)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(InstitutionalTheme.Colors.borderSubtle, lineWidth: 0.5)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(plan == nil)
            .opacity(plan == nil ? 0.45 : 1)

            Button(action: closePosition) {
                Text("Pozisyonu kapat")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(InstitutionalTheme.Colors.crimson)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(InstitutionalTheme.Colors.surface1)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(InstitutionalTheme.Colors.crimson.opacity(0.4), lineWidth: 0.5)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 4)
    }

    // MARK: - Helpers

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(InstitutionalTheme.Colors.surface1)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(InstitutionalTheme.Colors.borderSubtle, lineWidth: 0.5)
            )
    }

    private var cleanedSymbol: String {
        trade.symbol.uppercased().replacingOccurrences(of: ".IS", with: "")
    }

    private var displayName: String {
        if let name = quote?.shortName, !name.isEmpty, name != trade.symbol {
            return name
        }
        return cleanedSymbol
    }

    private var subtitleText: String {
        let source = trade.source == .autoPilot ? "Otopilot" : "Manuel"
        return "\(source) · \(holdingDays) gün"
    }

    private func formatCurrency(_ value: Double) -> String {
        let prefix = trade.currency.symbol
        let absValue = abs(value)
        let sign = value < 0 ? "-" : ""
        if absValue >= 10000 {
            return "\(sign)\(prefix)\(Int(absValue))"
        }
        return "\(sign)\(prefix)\(String(format: "%.2f", absValue))"
    }

    private func formatQuantity(_ qty: Double) -> String {
        if qty == qty.rounded() {
            return "\(Int(qty))"
        }
        return String(format: "%.2f", qty)
    }

    private func triggerPrice(_ trigger: ActionTrigger) -> Double? {
        switch trigger {
        case .priceAbove(let price): return price
        case .priceBelow(let price): return price
        default: return nil
        }
    }

    private func scoreColorForRate(_ rate: Double) -> Color {
        if rate >= 0.6 { return InstitutionalTheme.Colors.aurora }
        if rate >= 0.45 { return InstitutionalTheme.Colors.titan }
        return InstitutionalTheme.Colors.crimson
    }

    private func councilLabel(_ action: ArgusAction) -> String {
        switch action {
        case .aggressiveBuy: return "Güçlü al"
        case .accumulate:    return "Al"
        case .neutral:       return "Tut"
        case .trim:          return "Trim"
        case .liquidate:     return "Sat"
        }
    }

    private func councilColor(_ action: ArgusAction) -> Color {
        switch action {
        case .aggressiveBuy: return InstitutionalTheme.Colors.aurora
        case .accumulate:    return InstitutionalTheme.Colors.aurora
        case .neutral:       return InstitutionalTheme.Colors.textSecondary
        case .trim:          return InstitutionalTheme.Colors.titan
        case .liquidate:     return InstitutionalTheme.Colors.crimson
        }
    }

    private func stanceLabel(_ stance: MacroStance) -> String {
        switch stance {
        case .riskOn:    return "Risk açık"
        case .cautious:  return "Tedbirli"
        case .defensive: return "Defansif"
        case .riskOff:   return "Risk kapalı"
        }
    }

    private func stanceColor(_ stance: MacroStance) -> Color {
        switch stance {
        case .riskOn:    return InstitutionalTheme.Colors.aurora
        case .cautious:  return InstitutionalTheme.Colors.textPrimary
        case .defensive: return InstitutionalTheme.Colors.titan
        case .riskOff:   return InstitutionalTheme.Colors.crimson
        }
    }

    private func scenarioLabel(_ type: ScenarioType) -> String {
        switch type {
        case .bullish: return "boğa"
        case .bearish: return "ayı"
        case .neutral: return "nötr"
        }
    }

    private func scenarioColor(_ type: ScenarioType) -> Color {
        switch type {
        case .bullish: return InstitutionalTheme.Colors.aurora
        case .neutral: return InstitutionalTheme.Colors.textSecondary
        case .bearish: return InstitutionalTheme.Colors.crimson
        }
    }

    private func hasEventWarning(_ risk: EventCalendarService.EventRiskAssessment) -> Bool {
        risk.shouldAvoidNewPosition || risk.shouldReducePosition || !risk.warnings.isEmpty
    }

    // MARK: - Data

    private func loadContext() {
        plan = PositionPlanStore.shared.getPlan(for: trade.id)
        eventRisk = EventCalendarService.shared.assessPositionRisk(symbol: trade.symbol)
    }

    private func closePosition() {
        if let price = viewModel.quotes[trade.symbol]?.currentPrice {
            viewModel.sell(tradeId: trade.id, currentPrice: price)
            dismiss()
        }
    }
}
