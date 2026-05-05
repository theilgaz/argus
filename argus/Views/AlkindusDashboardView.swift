import SwiftUI

/// Alkindus — öğrenme paneli.
///
/// 2026-05-03 H-60: tam UI redesign + öğrenme akışı görünür hale getirildi.
///
/// Önceki yapı (880 satır, 9 ayrı bölüm) berbattı:
///   • headerCard, insights, dataTools, correlations, moduleCalibration,
///     regimeInsights, AlkindusTimeCard, marketComparison, pending
///     — kullanıcı hangi sayıya bakacağını bilmiyordu
///   • "Eventlerden öğren" butonu sadece konsola print yapıyordu
///     (`AlkindusEventProcessor.saveLearnings` calibration'a yazmıyor!)
///   • Veritabanı boyutu, blob temizle gibi dev-tool detayları kullanıcının
///     önündeydi
///   • "Bekleyen" sayısı en altta — esas KPI olması gereken bilgi gizliydi
///
/// Yeni yapı (~280 satır, 4 bölüm):
///   1. Özet KPI grid — gözlem, olgun, doğruluk, bekleyen
///   2. Modül performansı — sade bar listesi
///   3. Son değerlendirilen kararlar — verdict listesi
///   4. Manuel olgunlaştırma butonu + nasıl çalışıyor açıklaması
///
/// Public API korundu: `init(symbol: String? = nil)`.

struct AlkindusDashboardView: View {
    var symbol: String? = nil

    @State private var stats: AlkindusStats?
    @State private var verdicts: [AlkindusVerdict] = []
    @State private var pendingCount: Int = 0
    @State private var symbolInsight: SymbolInsight?
    @State private var isLoading = true
    @State private var isMaturing = false
    @State private var lastMatureRun: Date?
    @State private var showDrawer = false

    @StateObject private var deepLinkManager = DeepLinkManager.shared
    @EnvironmentObject private var router: NavigationRouter
    @Environment(\.dismiss) private var dismiss

    private var isPushed: Bool { !router.navigationStack.isEmpty }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            ArgusNavHeader(
                title: "Öğrenme paneli",
                subtitle: symbol == nil ? "Argus karar geçmişi" : "Sembol: \(symbol!)",
                leadingDeco: isPushed ? .back(onTap: { dismiss() }) : .none,
                actions: isPushed
                    ? [.custom(sfSymbol: "arrow.clockwise", action: refresh)]
                    : [
                        .menu({ withAnimation(ArgusDrawerView.toggleAnimation) { showDrawer = true } }),
                        .custom(sfSymbol: "arrow.clockwise", action: refresh)
                      ]
            )

            ZStack {
                InstitutionalTheme.Colors.background.ignoresSafeArea()

                if isLoading {
                    ProgressView()
                } else if let stats = stats {
                    ScrollView {
                        VStack(spacing: 16) {
                            if symbol != nil {
                                symbolInsightCard
                            }

                            summaryCard(stats: stats)

                            modulePerformanceCard(stats: stats)

                            verdictsCard

                            actionsCard

                            howItWorksCard

                            Color.clear.frame(height: 40)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                    }
                } else {
                    emptyState
                }

                if showDrawer {
                    ArgusDrawerView(isPresented: $showDrawer) { openSheet in
                        drawerSections(openSheet: openSheet)
                    }
                    .zIndex(200)
                }
            }
        }
        .background(InstitutionalTheme.Colors.background.ignoresSafeArea())
        .navigationBarHidden(true)
        .task {
            await loadAll()
        }
    }

    // MARK: - Symbol bağlamı kartı

    @ViewBuilder
    private var symbolInsightCard: some View {
        if let sym = symbol {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Bu sembol için okuma")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(InstitutionalTheme.Colors.textSecondary)
                    Spacer()
                    Text(sym)
                        .font(.system(size: 12))
                        .foregroundColor(InstitutionalTheme.Colors.textTertiary)
                }

                if let insight = symbolInsight {
                    Text(insight.message)
                        .font(.system(size: 14))
                        .foregroundColor(InstitutionalTheme.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineSpacing(2)

                    Rectangle()
                        .fill(InstitutionalTheme.Colors.borderSubtle)
                        .frame(height: 0.5)

                    insightStatRow(label: "En iyi modül",
                                   value: "\(displayName(for: insight.bestModule)) · %\(Int(insight.bestHitRate * 100))",
                                   color: InstitutionalTheme.Colors.aurora)
                    insightStatRow(label: "En zayıf modül",
                                   value: "\(displayName(for: insight.worstModule)) · %\(Int(insight.worstHitRate * 100))",
                                   color: InstitutionalTheme.Colors.crimson)
                    insightStatRow(label: "Toplam karar",
                                   value: "\(insight.totalDecisions)",
                                   color: InstitutionalTheme.Colors.textPrimary)
                } else {
                    Text("Bu sembol için en az 5 karar gerekli. Veriler biriktikçe burası dolacak.")
                        .font(.system(size: 13))
                        .foregroundColor(InstitutionalTheme.Colors.textSecondary)
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
    }

    private func insightStatRow(label: String, value: String, color: Color) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(InstitutionalTheme.Colors.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(color)
                .monospacedDigit()
        }
    }

    // MARK: - 1. Özet KPI

    private func summaryCard(stats: AlkindusStats) -> some View {
        let totalEvaluated = verdicts.count
        let correctCount = verdicts.filter { $0.wasCorrect }.count
        let accuracy = totalEvaluated > 0 ? Double(correctCount) / Double(totalEvaluated) : 0

        return VStack(alignment: .leading, spacing: 12) {
            Text("Özet")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(InstitutionalTheme.Colors.textSecondary)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 8) {
                kpiTile(label: "Olgunlaşan karar",
                        value: "\(totalEvaluated)",
                        sub: totalEvaluated == 0 ? "henüz yok" : nil,
                        color: InstitutionalTheme.Colors.textPrimary)

                kpiTile(label: "Doğruluk",
                        value: totalEvaluated > 0 ? "%\(Int(accuracy * 100))" : "—",
                        sub: totalEvaluated > 0 ? "\(correctCount) / \(totalEvaluated)" : nil,
                        color: scoreColor(accuracy))

                kpiTile(label: "Bekleyen",
                        value: "\(pendingCount)",
                        sub: pendingCount == 0 ? "kuyruk boş" : "olgunlaşma bekliyor",
                        color: InstitutionalTheme.Colors.textPrimary)

                kpiTile(label: "Son güncelleme",
                        value: lastMatureLabel(stats: stats),
                        sub: nil,
                        color: InstitutionalTheme.Colors.textSecondary)
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

    private func kpiTile(label: String, value: String, sub: String?, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(InstitutionalTheme.Colors.textTertiary)
            Text(value)
                .font(.system(size: 22, weight: .medium))
                .foregroundColor(color)
                .monospacedDigit()
            if let sub = sub {
                Text(sub)
                    .font(.system(size: 11))
                    .foregroundColor(InstitutionalTheme.Colors.textTertiary)
            } else {
                Color.clear.frame(height: 13)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(InstitutionalTheme.Colors.surface2)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func lastMatureLabel(stats: AlkindusStats) -> String {
        let date = lastMatureRun ?? stats.lastUpdated
        let elapsed = Date().timeIntervalSince(date)
        if elapsed < 60 { return "şimdi" }
        if elapsed < 3600 { return "\(Int(elapsed / 60)) dk önce" }
        if elapsed < 86400 { return "\(Int(elapsed / 3600)) sa önce" }
        return "\(Int(elapsed / 86400)) gün önce"
    }

    // MARK: - 2. Modül Performansı

    private func modulePerformanceCard(stats: AlkindusStats) -> some View {
        let modules = aggregatedModulePerformance(stats: stats)

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Modül performansı")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(InstitutionalTheme.Colors.textSecondary)
                Spacer()
                if !modules.isEmpty {
                    Text("\(modules.count) modül")
                        .font(.system(size: 11))
                        .foregroundColor(InstitutionalTheme.Colors.textTertiary)
                }
            }

            if modules.isEmpty {
                Text("Henüz veri yok. Kararlar olgunlaştıkça burada modüllerin doğruluk oranı görünür.")
                    .font(.system(size: 13))
                    .foregroundColor(InstitutionalTheme.Colors.textSecondary)
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 10) {
                    ForEach(modules, id: \.module) { entry in
                        moduleRow(name: entry.module,
                                  hitRate: entry.hitRate,
                                  attempts: entry.attempts)
                    }
                }
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

    private func moduleRow(name: String, hitRate: Double, attempts: Double) -> some View {
        HStack(spacing: 10) {
            Text(displayName(for: name))
                .font(.system(size: 13))
                .foregroundColor(InstitutionalTheme.Colors.textPrimary)
                .frame(width: 88, alignment: .leading)

            ArgusBar(value: hitRate, color: scoreColor(hitRate), height: 4)

            Text("%\(Int(hitRate * 100))")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(scoreColor(hitRate))
                .monospacedDigit()
                .frame(width: 44, alignment: .trailing)

            Text("\(Int(attempts))")
                .font(.system(size: 11))
                .foregroundColor(InstitutionalTheme.Colors.textTertiary)
                .monospacedDigit()
                .frame(width: 32, alignment: .trailing)
        }
    }

    /// Modül başına tüm bracket'lerin ağırlıklı ortalama doğruluk oranı.
    private func aggregatedModulePerformance(stats: AlkindusStats)
    -> [(module: String, hitRate: Double, attempts: Double)] {
        var rows: [(String, Double, Double)] = []
        for (module, cal) in stats.calibration.modules {
            let totalAttempts = cal.brackets.values.reduce(0.0) { $0 + $1.attempts }
            let totalCorrect  = cal.brackets.values.reduce(0.0) { $0 + $1.correct }
            guard totalAttempts >= 3 else { continue }
            let rate = totalCorrect / totalAttempts
            rows.append((module, rate, totalAttempts))
        }
        return rows.sorted(by: { $0.1 > $1.1 })
    }

    // MARK: - 3. Son değerlendirilen kararlar

    private var verdictsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Son değerlendirilen kararlar")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(InstitutionalTheme.Colors.textSecondary)
                Spacer()
                if !verdicts.isEmpty {
                    Text("son \(min(8, verdicts.count))")
                        .font(.system(size: 11))
                        .foregroundColor(InstitutionalTheme.Colors.textTertiary)
                }
            }

            if verdicts.isEmpty {
                Text("Henüz olgunlaşmış karar yok. Her karar 7 ve 15 gün sonra otomatik değerlendirilir.")
                    .font(.system(size: 13))
                    .foregroundColor(InstitutionalTheme.Colors.textSecondary)
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 0) {
                    let sorted = verdicts.sorted(by: { $0.evaluationDate > $1.evaluationDate }).prefix(8)
                    ForEach(Array(sorted.enumerated()), id: \.element.id) { idx, verdict in
                        verdictRow(verdict)
                        if idx < sorted.count - 1 {
                            Rectangle()
                                .fill(InstitutionalTheme.Colors.borderSubtle)
                                .frame(height: 0.5)
                        }
                    }
                }
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

    private func verdictRow(_ verdict: AlkindusVerdict) -> some View {
        HStack(spacing: 10) {
            Image(systemName: verdict.wasCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 14))
                .foregroundColor(verdict.wasCorrect
                                 ? InstitutionalTheme.Colors.aurora
                                 : InstitutionalTheme.Colors.crimson)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(verdict.symbol)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(InstitutionalTheme.Colors.textPrimary)
                    Text(verdict.action == "BUY" ? "al" : "sat")
                        .font(.system(size: 11))
                        .foregroundColor(InstitutionalTheme.Colors.textSecondary)
                    Text("· T+\(verdict.horizon)g")
                        .font(.system(size: 11))
                        .foregroundColor(InstitutionalTheme.Colors.textTertiary)
                }
                Text("Değerlendirildi · \(timeAgo(verdict.evaluationDate))")
                    .font(.system(size: 11))
                    .foregroundColor(InstitutionalTheme.Colors.textTertiary)
            }

            Spacer()

            Text(String(format: "%+.1f%%", verdict.priceChange))
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(verdict.priceChange >= 0
                                 ? InstitutionalTheme.Colors.aurora
                                 : InstitutionalTheme.Colors.crimson)
                .monospacedDigit()
        }
        .padding(.vertical, 8)
    }

    // MARK: - 4. Aksiyonlar

    private var actionsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Aksiyon")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(InstitutionalTheme.Colors.textSecondary)

            Button(action: runMaturation) {
                HStack(spacing: 10) {
                    if isMaturing {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 16, height: 16)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 13))
                    }
                    Text(isMaturing ? "Olgunlaştırma çalışıyor" : "Şimdi olgunlaştır")
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                    Text("\(pendingCount) bekliyor")
                        .font(.system(size: 11))
                        .foregroundColor(InstitutionalTheme.Colors.textTertiary)
                        .monospacedDigit()
                }
                .foregroundColor(InstitutionalTheme.Colors.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(InstitutionalTheme.Colors.surface2)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .opacity(isMaturing ? 0.6 : 1)
            }
            .buttonStyle(.plain)
            .disabled(isMaturing)
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

    // MARK: - Nasıl çalışıyor (kısa açıklama)

    private var howItWorksCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Nasıl çalışıyor")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(InstitutionalTheme.Colors.textSecondary)
            Text("Her al/sat kararı kuyruğa girer. 7 ve 15 gün sonra fiyat değişimi gerçekle karşılaştırılır. Doğruysa modül +1, yanlışsa -1. Zamanla modüllerin gerçek doğruluk oranı çıkar.")
                .font(.system(size: 12))
                .foregroundColor(InstitutionalTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(InstitutionalTheme.Colors.surface1.opacity(0.6))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    InstitutionalTheme.Colors.borderSubtle,
                    style: StrokeStyle(lineWidth: 0.5, dash: [4, 3])
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 28))
                .foregroundColor(InstitutionalTheme.Colors.textTertiary)
            Text("Henüz veri yok")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(InstitutionalTheme.Colors.textPrimary)
            Text("Kararlar verildikçe ve olgunlaştıkça istatistikler burada görünecek.")
                .font(.system(size: 12))
                .foregroundColor(InstitutionalTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    // MARK: - Helpers

    /// Motor adından kullanıcıya gösterilecek işlev karşılığı.
    private func displayName(for moduleName: String) -> String {
        switch moduleName.lowercased() {
        case "orion":      return "Teknik"
        case "atlas":      return "Bilanço"
        case "aether":     return "Makro"
        case "hermes":     return "Haber"
        case "demeter":    return "Sektör"
        case "chiron":     return "Rejim"
        case "prometheus": return "Tahmin"
        case "athena":     return "Faktör"
        case "alkindus":   return "Alkindus"
        case "phoenix":    return "Risk"
        default:           return moduleName.capitalized
        }
    }

    private func scoreColor(_ rate: Double) -> Color {
        if rate >= 0.6 { return InstitutionalTheme.Colors.aurora }
        if rate >= 0.45 { return InstitutionalTheme.Colors.titan }
        return InstitutionalTheme.Colors.crimson
    }

    private func timeAgo(_ date: Date) -> String {
        let elapsed = Date().timeIntervalSince(date)
        if elapsed < 60 { return "şimdi" }
        if elapsed < 3600 { return "\(Int(elapsed / 60)) dk önce" }
        if elapsed < 86400 { return "\(Int(elapsed / 3600)) sa önce" }
        return "\(Int(elapsed / 86400)) gün önce"
    }

    // MARK: - Drawer

    private func drawerSections(openSheet: @escaping (ArgusDrawerView.DrawerSheet) -> Void) -> [ArgusDrawerView.DrawerSection] {
        let dismiss = ArgusDrawerView.dismissClosure($showDrawer)

        return [
            ArgusDrawerView.commonScreensSection(excluding: [.alkindus], dismiss: dismiss),
            ArgusDrawerView.commonToolsSection(openSheet: openSheet)
        ]
    }

    // MARK: - Data loading

    private func loadAll() async {
        isLoading = true
        async let s = AlkindusCalibrationEngine.shared.getCurrentStats()
        async let v = AlkindusMemoryStore.shared.loadVerdicts()
        async let p = AlkindusMemoryStore.shared.loadPendingObservations()

        let (stats, verdicts, pending) = await (s, v, p)

        if let sym = symbol {
            self.symbolInsight = await AlkindusSymbolLearner.shared.getSymbolInsights(for: sym)
        }

        await MainActor.run {
            self.stats = stats
            self.verdicts = verdicts
            self.pendingCount = pending.count
            self.isLoading = false
        }
    }

    private func refresh() {
        Task { await loadAll() }
    }

    /// Manuel olgunlaştırma — bekleyen tüm gözlemleri olgunluk durumuna göre
    /// değerlendirir. Eski "Eventlerden öğren" butonu (sadece print yapıyordu)
    /// yerine gerçek öğrenme tetikleyicisi.
    private func runMaturation() {
        isMaturing = true
        Task {
            await AlkindusCalibrationEngine.shared.periodicMatureCheck()
            await MainActor.run {
                self.lastMatureRun = Date()
                self.isMaturing = false
            }
            await loadAll()
        }
    }
}

#Preview {
    AlkindusDashboardView()
}
