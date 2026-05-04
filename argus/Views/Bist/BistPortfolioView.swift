import SwiftUI

// MARK: - BIST Portfolio View (Refactored to use main PortfolioEngine)
// MARK: - BIST Portfolio View (Refactored to use main PortfolioStore)
// Artık TradingViewModel ve PortfolioStore kullanıyor

struct BistPortfolioView: View {
    @EnvironmentObject var viewModel: TradingViewModel
    @EnvironmentObject private var router: NavigationRouter
    @Environment(\.dismiss) private var dismiss
    @State private var showSearch = false
    @State private var showDrawer = false
    @StateObject private var deepLinkManager = DeepLinkManager.shared

    private var isPushed: Bool { !router.navigationStack.isEmpty }

    // BIST trades from PortfolioStore
    var bistTrades: [Trade] {
        PortfolioStore.shared.bistOpenTrades
    }

    var bistBalance: Double {
        PortfolioStore.shared.bistBalance
    }

    var body: some View {
        // 2026-05-03 H-59: nested NavigationStack kaldırıldı.
        VStack(spacing: 0) {
                ArgusNavHeader(
                    title: "BIST portföyü",
                    subtitle: "Nakit, hisse, otopilot",
                    leadingDeco: isPushed
                        ? .back(onTap: { dismiss() })
                        : .bars3([.holo, .text, .text]),
                    actions: isPushed
                        ? [.plus({ showSearch = true })]
                        : [
                            .menu({ withAnimation(ArgusDrawerView.toggleAnimation) { showDrawer = true } }),
                            .plus({ showSearch = true })
                          ]
                )
                ScrollView {
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("BIST değeri")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(InstitutionalTheme.Colors.textSecondary)
                            Spacer()
                            Text("TL")
                                .font(.system(size: 11))
                                .foregroundColor(InstitutionalTheme.Colors.textTertiary)
                        }

                        Text("₺\(String(format: "%.2f", bistBalance + portfolioValue))")
                            .font(.system(size: 30, weight: .medium))
                            .foregroundColor(InstitutionalTheme.Colors.textPrimary)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)

                        Rectangle()
                            .fill(InstitutionalTheme.Colors.borderSubtle)
                            .frame(height: 0.5)

                        HStack(spacing: 8) {
                            sadeStatTile(title: "Nakit",
                                         value: "₺\(String(format: "%.2f", bistBalance))",
                                         tone: InstitutionalTheme.Colors.textPrimary)
                            sadeStatTile(title: "Hisse değeri",
                                         value: "₺\(String(format: "%.2f", portfolioValue))",
                                         tone: InstitutionalTheme.Colors.textPrimary)
                        }

                        Rectangle()
                            .fill(InstitutionalTheme.Colors.borderSubtle)
                            .frame(height: 0.5)

                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Otopilot")
                                    .font(.system(size: 11))
                                    .foregroundColor(InstitutionalTheme.Colors.textTertiary)
                                Text(viewModel.isAutoPilotEnabled
                                     ? "Aktif · piyasa taranıyor"
                                     : "Pasif · manuel mod")
                                    .font(.system(size: 13))
                                    .foregroundColor(viewModel.isAutoPilotEnabled
                                                     ? InstitutionalTheme.Colors.aurora
                                                     : InstitutionalTheme.Colors.textSecondary)
                            }
                            Spacer()
                            Toggle("", isOn: $viewModel.isAutoPilotEnabled)
                                .labelsHidden()
                                .tint(InstitutionalTheme.Colors.aurora)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(InstitutionalTheme.Colors.surface1)
                    .overlay(
                        RoundedRectangle(cornerRadius: InstitutionalTheme.Radius.lg, style: .continuous)
                            .stroke(InstitutionalTheme.Colors.borderSubtle, lineWidth: 0.5)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: InstitutionalTheme.Radius.lg, style: .continuous))
                    .padding(.horizontal)
                    
                    // MARK: - Portfolio List (V5)
                    if bistTrades.isEmpty {
                        VStack(spacing: 14) {
                            Image(systemName: "case")
                                .font(.system(size: 28))
                                .foregroundColor(InstitutionalTheme.Colors.textTertiary)
                            VStack(spacing: 4) {
                                Text("Portföyün boş")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(InstitutionalTheme.Colors.textPrimary)
                                Text("BIST hisseleri ekleyerek başla.")
                                    .font(.system(size: 12))
                                    .foregroundColor(InstitutionalTheme.Colors.textSecondary)
                            }
                            Button(action: { showSearch = true }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "plus")
                                        .font(.system(size: 12))
                                    Text("Hisse ekle")
                                        .font(.system(size: 13, weight: .medium))
                                }
                                .foregroundColor(InstitutionalTheme.Colors.textPrimary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .background(InstitutionalTheme.Colors.surface2)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.top, 40)
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(bistTrades) { trade in
                                UnifiedPositionCard(
                                    trade: trade,
                                    currentPrice: viewModel.quotes[trade.symbol]?.currentPrice ?? trade.entryPrice,
                                    market: .bist,
                                    onEdit: {
                                        // Plan düzenleme sayfasına git (TODO)
                                        print("Edit plan for \(trade.symbol)")
                                    },
                                    onSell: {
                                        // Satış işlemi (TODO)
                                        print("Sell \(trade.symbol)")
                                    }
                                )
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.top)
                }
            }
        .background(InstitutionalTheme.Colors.background.ignoresSafeArea())
        .navigationBarHidden(true)
        .sheet(isPresented: $showSearch) {
            BistMarketView()
                .environmentObject(viewModel)
        }
        .overlay {
            if showDrawer {
                ArgusDrawerView(isPresented: $showDrawer) { openSheet in
                    drawerSections(openSheet: openSheet)
                }
                .zIndex(200)
            }
        }
    }
    
    // Computed
    var portfolioValue: Double {
        bistTrades.reduce(0) { total, trade in
            let price = viewModel.quotes[trade.symbol]?.currentPrice ?? trade.entryPrice
            return total + (trade.quantity * price)
        }
    }

    /// Sade stat tile — sentence başlık + medium değer.
    private func sadeStatTile(title: String, value: String, tone: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 11))
                .foregroundColor(InstitutionalTheme.Colors.textTertiary)
            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(tone)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(InstitutionalTheme.Colors.surface2)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func drawerSections(openSheet: @escaping (ArgusDrawerView.DrawerSheet) -> Void) -> [ArgusDrawerView.DrawerSection] {
        var sections: [ArgusDrawerView.DrawerSection] = []
        
        sections.append(
            ArgusDrawerView.DrawerSection(
                title: "Ekranlar",
                items: [
                    ArgusDrawerView.DrawerItem(title: "Alkindus Merkez", subtitle: "Yapay zeka merkezi", icon: "AlkindusIcon") {
                        NavigationRouter.shared.navigate(to: .alkindusDashboard)
                        showDrawer = false
                    },
                    ArgusDrawerView.DrawerItem(title: "Piyasalar", subtitle: "Kokpit ekranı", icon: "chart.line.uptrend.xyaxis") {
                        deepLinkManager.navigate(to: .kokpit)
                        showDrawer = false
                    },
                    ArgusDrawerView.DrawerItem(title: "Portföy", subtitle: "Pozisyonlar", icon: "briefcase.fill") {
                        deepLinkManager.navigate(to: .portfolio)
                        showDrawer = false
                    },
                    ArgusDrawerView.DrawerItem(title: "Ayarlar", subtitle: "Tercihler", icon: "gearshape") {
                        deepLinkManager.navigate(to: .settings)
                        showDrawer = false
                    }
                ]
            )
        )
        
        sections.append(
            ArgusDrawerView.DrawerSection(
                title: "BIST portföyü",
                items: [
                    ArgusDrawerView.DrawerItem(title: "Hisse Ekle", subtitle: "BIST hissesi ekle", icon: "plus.circle") {
                        showSearch = true
                        showDrawer = false
                    }
                ]
            )
        )
        
        sections.append(ArgusDrawerView.commonToolsSection(openSheet: openSheet))

        return sections
    }
}

// MARK: - Subviews
// MARK: - Subviews Removed (Replaced by UnifiedPositionCard)

