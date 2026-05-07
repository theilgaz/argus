import SwiftUI

// MARK: - Piyasa Rejimi Kartı
/// Genel piyasa rejimini (Boğa/Nötr/Ayı) gösteren kart.
/// Rejim skoru ve eğitim notu içerir.

struct PiyasaRejimiCard: View {
    let rejimScore: Double // 0-100
    let rejimLabel: String // "Boğa", "Nötr", "Ayı"
    let stance: String // "riskOn", "cautious", "defensive", "riskOff"

    @State private var showEducation = false

    private var rejimColor: Color {
        if rejimScore >= 60 { return InstitutionalTheme.Colors.positive }
        if rejimScore <= 40 { return InstitutionalTheme.Colors.negative }
        return InstitutionalTheme.Colors.warning
    }

    private var rejimIcon: String {
        if rejimScore >= 60 { return "arrow.up.right.circle.fill" }
        if rejimScore <= 40 { return "arrow.down.right.circle.fill" }
        return "minus.circle.fill"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("PİYASA REJİMİ")
                        .font(InstitutionalTheme.Typography.micro)
                        .foregroundColor(InstitutionalTheme.Colors.textTertiary)
                    Text("Genel Trend Yönü")
                        .font(DesignTokens.Fonts.custom(size: 11))
                        .foregroundColor(InstitutionalTheme.Colors.textSecondary)
                }
                Spacer()
                Button(action: { withAnimation(.snappy) { showEducation.toggle() } }) {
                    Image(systemName: showEducation ? "lightbulb.fill" : "lightbulb")
                        .foregroundColor(.orange)
                        .font(DesignTokens.Fonts.custom(size: 14))
                }
            }
            .padding(16)

            Divider().background(InstitutionalTheme.Colors.borderSubtle)

            // Rejim Badge
            VStack(spacing: 16) {
                HStack(spacing: 20) {
                    rejimBadge("BOĞA", isActive: rejimScore >= 60, color: InstitutionalTheme.Colors.positive)
                    rejimBadge("NÖTR", isActive: rejimScore > 40 && rejimScore < 60, color: InstitutionalTheme.Colors.warning)
                    rejimBadge("AYI", isActive: rejimScore <= 40, color: InstitutionalTheme.Colors.negative)
                }
                .padding(.top, 16)

                // Score Bar
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: rejimIcon)
                            .foregroundColor(rejimColor)
                            .font(DesignTokens.Fonts.custom(size: 16))
                        Text("Rejim Skoru: \(Int(rejimScore))/100")
                            .font(InstitutionalTheme.Typography.data)
                            .foregroundColor(InstitutionalTheme.Colors.textPrimary)
                        Spacer()
                        Text(rejimLabel)
                            .font(InstitutionalTheme.Typography.micro)
                            .foregroundColor(rejimColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(rejimColor.opacity(0.15))
                            .cornerRadius(6)
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(InstitutionalTheme.Colors.surface2)
                                .frame(height: 8)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(rejimColor)
                                .frame(width: geo.size.width * max(0, min(rejimScore, 100)) / 100, height: 8)
                        }
                    }
                    .frame(height: 8)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }

            // Eğitim Notu
            if showEducation {
                VStack(alignment: .leading, spacing: 8) {
                    Divider().background(InstitutionalTheme.Colors.borderSubtle)
                    HStack(alignment: .top, spacing: 8) {
                        Text("💡")
                            .font(DesignTokens.Fonts.custom(size: 14))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Ne Demek?")
                                .font(DesignTokens.Fonts.custom(size: 12, weight: .semibold))
                                .foregroundColor(.orange)
                            Text("Piyasa rejimi, genel trendin yönünü gösterir. 60 üzeri skorlar boğa piyasasına işaret eder ve alım fırsatları daha güçlüdür. 40 altı skorlar ayı piyasasını, aradaki değerler ise belirsizliği yansıtır.")
                                .font(DesignTokens.Fonts.custom(size: 11))
                                .foregroundColor(InstitutionalTheme.Colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(InstitutionalTheme.Colors.surface1)
        .cornerRadius(InstitutionalTheme.Radius.md)
        .overlay(
            RoundedRectangle(cornerRadius: InstitutionalTheme.Radius.md)
                .stroke(InstitutionalTheme.Colors.borderSubtle, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func rejimBadge(_ label: String, isActive: Bool, color: Color) -> some View {
        Text(label)
            .font(DesignTokens.Fonts.custom(size: 13, weight: .bold))
            .foregroundColor(isActive ? .white : InstitutionalTheme.Colors.textTertiary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isActive ? color.opacity(0.85) : InstitutionalTheme.Colors.surface2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isActive ? color : Color.clear, lineWidth: 1)
            )
    }
}

// MARK: - Makro Göstergeler Kartı
/// Öncelik: TCMBDataService (EVDS / resmi kaynaklar), fallback: BorsaPy.
/// Enflasyon, faiz, USD/TRY, BIST 100, Brent, Altın vb.

struct MakroGostergelerCard: View {
    @State private var inflation: BistInflationData?
    @State private var policyRate: Double?
    @State private var xu100: BistQuote?
    @State private var brent: FXRate?
    @State private var gold: FXRate?
    @State private var usdTry: Double?
    @State private var isLoading = true
    @State private var showEducation = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("MAKRO GÖSTERGELER")
                        .font(InstitutionalTheme.Typography.micro)
                        .foregroundColor(InstitutionalTheme.Colors.textTertiary)
                    Text("Türkiye Ekonomi Verileri")
                        .font(DesignTokens.Fonts.custom(size: 11))
                        .foregroundColor(InstitutionalTheme.Colors.textSecondary)
                }
                Spacer()
                Button(action: { withAnimation(.snappy) { showEducation.toggle() } }) {
                    Image(systemName: showEducation ? "lightbulb.fill" : "lightbulb")
                        .foregroundColor(.orange)
                        .font(DesignTokens.Fonts.custom(size: 14))
                }
            }
            .padding(16)

            Divider().background(InstitutionalTheme.Colors.borderSubtle)

            if isLoading {
                ProgressView()
                    .tint(InstitutionalTheme.Colors.primary)
                    .padding(32)
            } else {
                VStack(spacing: 0) {
                    // Enflasyon & Faiz
                    if let inf = inflation {
                        makroRow(
                            icon: "chart.line.downtrend.xyaxis",
                            label: "Enflasyon (TÜFE)",
                            value: "%\(String(format: "%.2f", inf.yearlyInflation))",
                            trend: inf.yearlyInflation < 50 ? true : false,
                            color: inf.yearlyInflation < 40 ? InstitutionalTheme.Colors.positive : InstitutionalTheme.Colors.negative
                        )
                    }

                    if let rate = policyRate {
                        let realRate = rate - (inflation?.yearlyInflation ?? 0)
                        makroRow(
                            icon: "building.columns",
                            label: "Politika Faizi",
                            value: "%\(String(format: "%.2f", rate))",
                            trend: nil,
                            color: InstitutionalTheme.Colors.textPrimary
                        )
                        makroRow(
                            icon: "checkmark.shield",
                            label: "Reel Faiz",
                            value: "%\(String(format: "%.2f", realRate))",
                            trend: realRate > 0 ? true : false,
                            color: realRate > 0 ? InstitutionalTheme.Colors.positive : InstitutionalTheme.Colors.negative
                        )
                    }

                    Divider().background(InstitutionalTheme.Colors.borderSubtle).padding(.horizontal, 16)

                    // Piyasa Verileri
                    if let usd = usdTry {
                        makroRow(
                            icon: "dollarsign.circle",
                            label: "USD/TRY",
                            value: "₺\(String(format: "%.2f", usd))",
                            trend: nil,
                            color: InstitutionalTheme.Colors.textPrimary
                        )
                    }

                    if let xu = xu100 {
                        let change = xu.open > 0 ? ((xu.last - xu.open) / xu.open) * 100 : 0
                        makroRow(
                            icon: "chart.bar.fill",
                            label: "BIST 100",
                            value: String(format: "%.0f", xu.last),
                            trend: change >= 0,
                            color: change >= 0 ? InstitutionalTheme.Colors.positive : InstitutionalTheme.Colors.negative,
                            detail: String(format: "%+.1f%%", change)
                        )
                    }

                    if let b = brent {
                        makroRow(
                            icon: "drop.fill",
                            label: "Brent Petrol",
                            value: "$\(String(format: "%.2f", b.last))",
                            trend: nil,
                            color: InstitutionalTheme.Colors.textPrimary
                        )
                    }

                    if let g = gold {
                        makroRow(
                            icon: "sparkles",
                            label: "Gram Altın",
                            value: "₺\(String(format: "%.0f", g.last))",
                            trend: nil,
                            color: InstitutionalTheme.Colors.warning
                        )
                    }
                }
            }

            // Eğitim Notu
            if showEducation {
                VStack(alignment: .leading, spacing: 8) {
                    Divider().background(InstitutionalTheme.Colors.borderSubtle)
                    HStack(alignment: .top, spacing: 8) {
                        Text("💡")
                            .font(DesignTokens.Fonts.custom(size: 14))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Ne Demek?")
                                .font(DesignTokens.Fonts.custom(size: 12, weight: .semibold))
                                .foregroundColor(.orange)
                            Text("Reel faiz pozitif olduğunda TL varlıklar cazip hale gelir. Enflasyonun düşüş trendi borsa için olumludur. BIST 100 endeksi Türk borsasının genel barometresidir.")
                                .font(DesignTokens.Fonts.custom(size: 11))
                                .foregroundColor(InstitutionalTheme.Colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(InstitutionalTheme.Colors.surface1)
        .cornerRadius(InstitutionalTheme.Radius.md)
        .overlay(
            RoundedRectangle(cornerRadius: InstitutionalTheme.Radius.md)
                .stroke(InstitutionalTheme.Colors.borderSubtle, lineWidth: 1)
        )
        .task { await loadData() }
    }

    @ViewBuilder
    private func makroRow(icon: String, label: String, value: String, trend: Bool?, color: Color, detail: String? = nil) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(DesignTokens.Fonts.custom(size: 12))
                .foregroundColor(color.opacity(0.8))
                .frame(width: 20)

            Text(label)
                .font(InstitutionalTheme.Typography.caption)
                .foregroundColor(InstitutionalTheme.Colors.textSecondary)

            Spacer()

            Text(value)
                .font(InstitutionalTheme.Typography.data)
                .foregroundColor(color)

            if let detail = detail {
                Text(detail)
                    .font(InstitutionalTheme.Typography.dataSmall)
                    .foregroundColor(color)
            }

            if let trend = trend {
                Image(systemName: trend ? "arrow.up.right" : "arrow.down.right")
                    .font(DesignTokens.Fonts.custom(size: 10, weight: .bold))
                    .foregroundColor(trend ? InstitutionalTheme.Colors.positive : InstitutionalTheme.Colors.negative)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func loadData() async {
        // Paralel veri çekimi (hatalar loglanıyor)
        let snapshot = await TCMBDataService.shared.getMacroSnapshot(forceRefresh: true)
        var inf: BistInflationData?
        var rate: Double?
        var xu: BistQuote?
        var br: FXRate?
        var gld: FXRate?

        if let infl = snapshot.inflation {
            let monthly = snapshot.coreInflation ?? 0
            inf = BistInflationData(
                date: ISO8601DateFormatter().string(from: snapshot.timestamp),
                yearlyInflation: infl,
                monthlyInflation: monthly,
                type: "TUFE"
            )
        } else {
            do { inf = try await BorsaPyProvider.shared.getInflationData() }
            catch { print("⚠️ MakroGostergeler: Enflasyon verisi alınamadı — \(error)") }
        }

        if let snapshotRate = snapshot.policyRate {
            rate = snapshotRate
        } else {
            do { rate = try await BorsaPyProvider.shared.getPolicyRate() }
            catch { print("⚠️ MakroGostergeler: Politika faizi alınamadı — \(error)") }
        }

        do { xu = try await BorsaPyProvider.shared.getXU100() }
        catch { print("⚠️ MakroGostergeler: XU100 verisi alınamadı — \(error)") }

        do { br = try await BorsaPyProvider.shared.getBrentPrice() }
        catch { print("⚠️ MakroGostergeler: Brent verisi alınamadı — \(error)") }

        do { gld = try await BorsaPyProvider.shared.getGoldPrice() }
        catch { print("⚠️ MakroGostergeler: Altın verisi alınamadı — \(error)") }

        // USD/TRY: snapshot öncelikli, store fallback
        let usdFromStore = await MainActor.run { MarketDataStore.shared.liveQuotes["USD/TRY"]?.currentPrice }
        let usd = snapshot.usdTry ?? usdFromStore

        // Güvenlik filtresi: bariz bozuk politika faizi gösterme
        if let candidateRate = rate,
           let yearlyInflation = inf?.yearlyInflation,
           candidateRate < 10,
           yearlyInflation > 15 {
            print("⚠️ MakroGostergeler: Politika faizi şüpheli (\(candidateRate)); gizleniyor")
            rate = nil
        }

        await MainActor.run {
            self.inflation = inf
            self.policyRate = rate
            self.xu100 = xu
            self.brent = br
            self.gold = gld
            self.usdTry = usd
            self.isLoading = false
        }
    }
}

// MARK: - Teknik Konsensüs Kartı
/// BorsaPy ta-signals endpoint'inden 28 gösterge analizi.

struct TeknikKonsensusCard: View {
    let symbol: String

    @State private var signals: BistTechnicalSignals?
    @State private var isLoading = true
    @State private var showEducation = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("TEKNİK KONSENSÜS")
                        .font(InstitutionalTheme.Typography.micro)
                        .foregroundColor(InstitutionalTheme.Colors.textTertiary)
                    Text("28 Gösterge Sinyali")
                        .font(DesignTokens.Fonts.custom(size: 11))
                        .foregroundColor(InstitutionalTheme.Colors.textSecondary)
                }
                Spacer()
                Button(action: { withAnimation(.snappy) { showEducation.toggle() } }) {
                    Image(systemName: showEducation ? "lightbulb.fill" : "lightbulb")
                        .foregroundColor(.orange)
                        .font(DesignTokens.Fonts.custom(size: 14))
                }
            }
            .padding(16)

            Divider().background(InstitutionalTheme.Colors.borderSubtle)

            if isLoading {
                ProgressView()
                    .tint(InstitutionalTheme.Colors.primary)
                    .padding(32)
            } else if let s = signals {
                VStack(spacing: 16) {
                    // Ana Sinyal
                    HStack(spacing: 12) {
                        signalBadge(s.sinyalTurkce, color: sinyalColor(s.summary.recommendation))
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(s.summary.buy)/\(s.totalIndicators) AL")
                                .font(InstitutionalTheme.Typography.data)
                                .foregroundColor(InstitutionalTheme.Colors.positive)
                            Text("\(s.summary.sell) SAT · \(s.summary.neutral) NÖTR")
                                .font(InstitutionalTheme.Typography.dataSmall)
                                .foregroundColor(InstitutionalTheme.Colors.textSecondary)
                        }
                    }

                    // Sinyal Barı
                    signalBar(buy: s.summary.buy, sell: s.summary.sell, neutral: s.summary.neutral)

                    // Alt Gruplar
                    HStack(spacing: 16) {
                        groupIndicator(label: "Osilatörler", value: s.oscillators.sinyalTurkce, recommendation: s.oscillators.recommendation)
                        Divider().frame(height: 30).background(InstitutionalTheme.Colors.borderSubtle)
                        groupIndicator(label: "H. Ortalamaları", value: s.movingAverages.sinyalTurkce, recommendation: s.movingAverages.recommendation)
                    }

                    // Öne Çıkan Göstergeler
                    if !s.oscillators.values.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Öne Çıkan Göstergeler:")
                                .font(DesignTokens.Fonts.custom(size: 11, weight: .semibold))
                                .foregroundColor(InstitutionalTheme.Colors.textSecondary)

                            if let rsi = s.oscillators.values["RSI"], let rsiVal = rsi.value {
                                indicatorRow("RSI(14)", value: String(format: "%.1f", rsiVal), signal: rsi.sinyalTurkce, warning: rsiVal > 70 ? "Aşırı Alım" : (rsiVal < 30 ? "Aşırı Satım" : nil))
                            }
                            if let macd = s.oscillators.values["MACD"], let macdVal = macd.value {
                                indicatorRow("MACD", value: String(format: "%.2f", macdVal), signal: macd.sinyalTurkce, warning: nil)
                            }
                            if let adx = s.oscillators.values["ADX"], let adxVal = adx.value {
                                indicatorRow("ADX", value: String(format: "%.1f", adxVal), signal: adx.sinyalTurkce, warning: adxVal > 25 ? "Güçlü Trend" : "Zayıf Trend")
                            }
                        }
                    }
                }
                .padding(16)
            } else {
                Text("Teknik veri yüklenemedi")
                    .font(.caption)
                    .foregroundColor(InstitutionalTheme.Colors.textSecondary)
                    .padding(24)
            }

            // Eğitim Notu
            if showEducation {
                VStack(alignment: .leading, spacing: 8) {
                    Divider().background(InstitutionalTheme.Colors.borderSubtle)
                    HStack(alignment: .top, spacing: 8) {
                        Text("💡")
                            .font(DesignTokens.Fonts.custom(size: 14))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Ne Demek?")
                                .font(DesignTokens.Fonts.custom(size: 12, weight: .semibold))
                                .foregroundColor(.orange)
                            Text("28 teknik gösterge (RSI, MACD, hareketli ortalamalar vb.) analiz edilir. Çoğunluk AL diyorsa teknik görünüm olumludur. RSI 70 üzeri aşırı alım, 30 altı aşırı satım bölgesini gösterir. Tek başına yeterli olmaz, diğer modüllerle birlikte değerlendirilmelidir.")
                                .font(DesignTokens.Fonts.custom(size: 11))
                                .foregroundColor(InstitutionalTheme.Colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(InstitutionalTheme.Colors.surface1)
        .cornerRadius(InstitutionalTheme.Radius.md)
        .overlay(
            RoundedRectangle(cornerRadius: InstitutionalTheme.Radius.md)
                .stroke(InstitutionalTheme.Colors.borderSubtle, lineWidth: 1)
        )
        .task { await loadSignals() }
    }

    // MARK: - Subviews

    @ViewBuilder
    private func signalBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(DesignTokens.Fonts.custom(size: 14, weight: .bold))
            .foregroundColor(DesignTokens.Colors.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(color.opacity(0.85))
            )
    }

    @ViewBuilder
    private func signalBar(buy: Int, sell: Int, neutral: Int) -> some View {
        let total = max(buy + sell + neutral, 1)
        GeometryReader { geo in
            HStack(spacing: 2) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(InstitutionalTheme.Colors.positive)
                    .frame(width: geo.size.width * CGFloat(buy) / CGFloat(total))
                RoundedRectangle(cornerRadius: 3)
                    .fill(InstitutionalTheme.Colors.textTertiary)
                    .frame(width: geo.size.width * CGFloat(neutral) / CGFloat(total))
                RoundedRectangle(cornerRadius: 3)
                    .fill(InstitutionalTheme.Colors.negative)
                    .frame(width: geo.size.width * CGFloat(sell) / CGFloat(total))
            }
        }
        .frame(height: 8)
    }

    @ViewBuilder
    private func groupIndicator(label: String, value: String, recommendation: String) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(DesignTokens.Fonts.custom(size: 10))
                .foregroundColor(InstitutionalTheme.Colors.textTertiary)
            Text(value)
                .font(DesignTokens.Fonts.custom(size: 12, weight: .semibold))
                .foregroundColor(sinyalColor(recommendation))
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func indicatorRow(_ name: String, value: String, signal: String, warning: String?) -> some View {
        HStack(spacing: 8) {
            Text(name)
                .font(InstitutionalTheme.Typography.dataSmall)
                .foregroundColor(InstitutionalTheme.Colors.textSecondary)
                .frame(width: 60, alignment: .leading)
            Text(value)
                .font(InstitutionalTheme.Typography.dataSmall)
                .foregroundColor(InstitutionalTheme.Colors.textPrimary)
            Text("(\(signal))")
                .font(DesignTokens.Fonts.custom(size: 10))
                .foregroundColor(signal == "Al" ? InstitutionalTheme.Colors.positive : (signal == "Sat" ? InstitutionalTheme.Colors.negative : InstitutionalTheme.Colors.textTertiary))
            Spacer()
            if let w = warning {
                Text(w)
                    .font(DesignTokens.Fonts.custom(size: 9, weight: .semibold))
                    .foregroundColor(.orange)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.12))
                    .cornerRadius(4)
            }
        }
    }

    private func sinyalColor(_ rec: String) -> Color {
        switch rec {
        case "STRONG_BUY", "BUY": return InstitutionalTheme.Colors.positive
        case "STRONG_SELL", "SELL": return InstitutionalTheme.Colors.negative
        default: return InstitutionalTheme.Colors.warning
        }
    }

    private func loadSignals() async {
        do {
            let result = try await BorsaPyProvider.shared.getTechnicalSignals(symbol: symbol)
            await MainActor.run {
                self.signals = result
                self.isLoading = false
            }
        } catch {
            print("⚠️ TeknikKonsensus: Teknik sinyal verisi alınamadı — \(error)")
            await MainActor.run { self.isLoading = false }
        }
    }
}
