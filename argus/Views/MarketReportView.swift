import SwiftUI

/// V5 piyasa raporu — trend / tepki / breakout fırsatları.
/// 2026-04-22 V5.E-3: Legacy `Theme` tokenları temizlendi, ArgusChip /
/// ArgusBar / ArgusSectionCaption dili uygulandı.
struct MarketReportView: View {
    let report: MarketAnalysisReport
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var router: NavigationRouter
    @State private var showDrawer = false
    @StateObject private var deepLinkManager = DeepLinkManager.shared

    private var isPushed: Bool { !router.navigationStack.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            ArgusNavHeader(
                title: "Piyasa raporu",
                subtitle: "Trend, tepki, breakout",
                leadingDeco: isPushed
                    ? .back(onTap: { dismiss() })
                    : .bars3([.holo, .text, .text]),
                actions: isPushed
                    ? []
                    : [
                        .menu({ withAnimation(ArgusDrawerView.toggleAnimation) { showDrawer = true } }),
                        .custom(sfSymbol: "xmark", action: { dismiss() })
                      ]
            )
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    timestampRibbon

                    if !report.trendOpportunities.isEmpty {
                        ReportSignalSection(
                            title: "Trend fırsatları",
                            caption: "MACD / SMA — güçlü trendde, trend takipçisi indikatörler en iyi sonucu verir.",
                            signals: report.trendOpportunities,
                            tone: .aurora
                        )
                    }

                    if !report.reversalOpportunities.isEmpty {
                        ReportSignalSection(
                            title: "Tepki fırsatları",
                            caption: "RSI / Bollinger — aşırı alım/satım bölgesinde, dönüş sinyalleri takip edilmeli.",
                            signals: report.reversalOpportunities,
                            tone: .titan
                        )
                    }

                    if !report.breakoutOpportunities.isEmpty {
                        ReportSignalSection(
                            title: "Sert hareket edenler",
                            caption: "Fiyat ve hacimde ani değişim — volatilite stratejileri uygun.",
                            signals: report.breakoutOpportunities,
                            tone: .holo
                        )
                    }
                }
                .padding(.vertical)
            }
        }
        .background(InstitutionalTheme.Colors.background.ignoresSafeArea())
        .navigationBarHidden(true)
        .overlay {
            if showDrawer {
                ArgusDrawerView(isPresented: $showDrawer) { openSheet in
                    drawerSections(openSheet: openSheet)
                }
                .zIndex(200)
            }
        }
    }

    // MARK: - Timestamp ribbon
    private var timestampRibbon: some View {
        HStack(spacing: 10) {
            Text("Son güncelleme")
                .font(.system(size: 11))
                .foregroundColor(InstitutionalTheme.Colors.textTertiary)
            Spacer()
            Text(report.timestamp, style: .time)
                .font(.system(size: 11))
                .foregroundColor(InstitutionalTheme.Colors.textSecondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .overlay(
            Rectangle()
                .fill(InstitutionalTheme.Colors.borderSubtle)
                .frame(height: 0.5),
            alignment: .bottom
        )
    }

    // MARK: - Drawer
    private func drawerSections(openSheet: @escaping (ArgusDrawerView.DrawerSheet) -> Void) -> [ArgusDrawerView.DrawerSection] {
        let closeDrawer = ArgusDrawerView.dismissClosure($showDrawer)

        return [
            ArgusDrawerView.commonScreensSection(dismiss: closeDrawer),
            ArgusDrawerView.DrawerSection(
                title: "Rapor",
                items: [
                    ArgusDrawerView.DrawerItem(title: "Kapat", subtitle: "Raporu kapat", icon: "xmark.circle") {
                        closeDrawer()
                        dismiss()
                    }
                ]
            ),
            ArgusDrawerView.commonToolsSection(openSheet: openSheet)
        ]
    }
}

// MARK: - Report Signal Section

struct ReportSignalSection: View {
    let title: String
    let caption: String?
    let signals: [AnalysisSignal]
    let tone: ArgusChipTone

    init(title: String, caption: String? = nil, signals: [AnalysisSignal], tone: ArgusChipTone) {
        self.title = title
        self.caption = caption
        self.signals = signals
        self.tone = tone
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                ArgusSectionCaption(title)
                Spacer()
                ArgusChip("\(signals.count)", tone: tone)
            }
            .padding(.horizontal, 16)

            if let caption {
                Text(caption)
                    .font(InstitutionalTheme.Typography.caption)
                    .foregroundColor(InstitutionalTheme.Colors.textSecondary)
                    .padding(.horizontal, 16)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(signals) { signal in
                        AnalysisSignalCard(signal: signal, tone: tone)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

// MARK: - Analysis Signal Card

struct AnalysisSignalCard: View {
    let signal: AnalysisSignal
    let tone: ArgusChipTone

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(signal.symbol)
                    .font(.system(size: 18, weight: .black, design: .monospaced))
                    .foregroundColor(InstitutionalTheme.Colors.textPrimary)
                Spacer()
                Text("\(Int(signal.score))")
                    .font(.system(size: 18, weight: .black, design: .monospaced))
                    .foregroundColor(tone.foreground)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(tone.background)
                    )
            }

            ArgusHair()

            Text(signal.reason)
                .font(InstitutionalTheme.Typography.caption)
                .foregroundColor(InstitutionalTheme.Colors.textSecondary)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(signal.keyFactors.prefix(3), id: \.self) { factor in
                    HStack(spacing: 6) {
                        ArgusDot(color: tone.foreground, size: 4)
                        Text(factor)
                            .font(.system(size: 10))
                            .foregroundColor(InstitutionalTheme.Colors.textPrimary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(width: 260, height: 220, alignment: .topLeading)
        .background(InstitutionalTheme.Colors.surface1)
        .overlay(
            RoundedRectangle(cornerRadius: InstitutionalTheme.Radius.lg, style: .continuous)
                .stroke(tone.foreground.opacity(0.35), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: InstitutionalTheme.Radius.lg, style: .continuous))
    }
}
