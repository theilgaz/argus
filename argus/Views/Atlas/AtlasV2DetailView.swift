import SwiftUI

// MARK: - Bilanço Detay Ekranı (eski adıyla Atlas V2 Detail)
// Şirketi A'dan Z'ye öğreten arayüz.
//
// 2026-04-30 H-58 — sade refactor.
// Eski yapı V5: "ATLAS · TEMEL ANALİZ" caps subtitle + "ATLAS" pill +
// ArgusOrb + 84pt motor-tinted ring + caps mono captions her yerde
// ("ATLAS ÇEKİRDEĞİ", "POZİTİF SİNYALLER", "KARLILIK" mini grid).
// Yeni dil: "Bilanço analizi" sentence subtitle, mitoloji pill kalktı,
// orb + ring gitti, sade hairline kartlar, sentence başlıklar.
// Public API ve loadData() flow korundu.

struct AtlasV2DetailView: View {
    let symbol: String
    @State private var result: AtlasV2Result?
    @State private var isLoading = true
    @State private var error: String?
    @State private var detailedError: String? // Additional debug info
    @State private var expandedSections: Set<String> = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            ArgusNavHeader(
                title: symbol.replacingOccurrences(of: ".IS", with: ""),
                subtitle: "Bilanço analizi",
                leadingDeco: .back(onTap: { dismiss() }),
                titlePill: nil,
                status: headerStatus
            )

            ScrollView {
                VStack(spacing: 20) {
                    if isLoading {
                        loadingView
                    } else if let error = error {
                        errorView(error)
                    } else if let result = result {
                    // Başlık ve Genel Skor
                    headerCard(result)
                    educationalRationaleCard(result)
                    
                    // Öne Çıkanlar & Uyarılar
                    if !result.highlights.isEmpty || !result.warnings.isEmpty {
                        highlightsCard(result)
                    }
                    
                    // VALUE ALERT SYSTEM (BIST-ÖZEL)
                    if symbol.hasSuffix(".IS"), hasValueAlerts(result) {
                        valueAlertCard(result)
                    }
                    
                    // Bölüm Kartları
                    sectionCard(
                        title: "Değerleme",
                        icon: "dollarsign.circle.fill",
                        iconColor: InstitutionalTheme.Colors.warning,
                        score: result.valuationScore,
                        metrics: result.valuation.allMetrics,
                        sectionId: "valuation"
                    )
                    
                    sectionCard(
                        title: "Karlılık",
                        icon: "chart.line.uptrend.xyaxis",
                        iconColor: InstitutionalTheme.Colors.positive,
                        score: result.profitabilityScore,
                        metrics: result.profitability.allMetrics,
                        sectionId: "profitability"
                    )
                    
                    sectionCard(
                        title: "Büyüme",
                        icon: "arrow.up.right.circle.fill",
                        iconColor: InstitutionalTheme.Colors.primary,
                        score: result.growthScore,
                        metrics: result.growth.allMetrics,
                        sectionId: "growth"
                    )
                    
                    sectionCard(
                        title: "Finansal Sağlık",
                        icon: "shield.checkered",
                        iconColor: InstitutionalTheme.Colors.primary,
                        score: result.healthScore,
                        metrics: result.health.allMetrics,
                        sectionId: "health"
                    )
                    
                    sectionCard(
                        title: "Nakit Kalitesi",
                        icon: "banknote.fill",
                        iconColor: InstitutionalTheme.Colors.positive,
                        score: result.cashScore,
                        metrics: result.cash.allMetrics,
                        sectionId: "cash"
                    )
                    
                    sectionCard(
                        title: "Temettü",
                        icon: "gift.fill",
                        iconColor: InstitutionalTheme.Colors.warning,
                        score: result.dividendScore,
                        metrics: result.dividend.allMetrics,
                        sectionId: "dividend"
                    )
                    
                    // YENİ: Risk Kartı
                    sectionCard(
                        title: "Risk Analizi",
                        icon: "exclamationmark.triangle.fill",
                        iconColor: InstitutionalTheme.Colors.negative,
                        score: 100 - (result.risk.beta.value ?? 1.0) * 20,
                        metrics: result.risk.allMetrics,
                        sectionId: "risk"
                    )
                    
                    // Özet
                    summaryCard(result)
                }
            }
                .padding()
            }
        }
        .background(InstitutionalTheme.Colors.background)
        .navigationBarHidden(true)
        .task {
            await loadData()
        }
    }

    private var headerStatus: ArgusNavHeader.Status {
        if isLoading {
            return .custom(dotColor: InstitutionalTheme.Colors.textTertiary,
                           label: "Analiz ediliyor",
                           trailing: symbol.uppercased())
        }
        if error != nil {
            return .custom(dotColor: InstitutionalTheme.Colors.crimson,
                           label: "Hata",
                           trailing: symbol.uppercased())
        }
        if let r = result {
            let score = Int(r.totalScore.rounded())
            return .custom(dotColor: atlasScoreTone(r.totalScore).foreground,
                           label: "Skor \(score)",
                           trailing: r.qualityBand.rawValue)
        }
        return .none
    }
    
    // MARK: - Header Card
    
    private func headerCard(_ result: AtlasV2Result) -> some View {
        // 2026-04-30 H-58 — sade. Orb + 84pt ring + caps "ATLAS ÇEKİRDEĞİ"
        // gitti. Yerine: şirket adı + sektör + market cap (sentence) +
        // skor satırı (32pt medium + /100 + kalite bandı sentence).
        VStack(alignment: .leading, spacing: 14) {

            // Şirket künyesi
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(result.profile.name)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(InstitutionalTheme.Colors.textPrimary)
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        Text(result.symbol)
                            .font(.system(size: 12))
                            .foregroundColor(InstitutionalTheme.Colors.textSecondary)
                        if let sector = result.profile.sector {
                            Text("·")
                                .foregroundColor(InstitutionalTheme.Colors.textTertiary)
                            Text(sector)
                                .font(.system(size: 12))
                                .foregroundColor(InstitutionalTheme.Colors.textSecondary)
                                .lineLimit(1)
                        }
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(result.profile.formattedMarketCap)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(InstitutionalTheme.Colors.textPrimary)
                        .monospacedDigit()
                    Text(result.profile.marketCapTier.lowercased())
                        .font(.system(size: 11))
                        .foregroundColor(InstitutionalTheme.Colors.textTertiary)
                }
            }

            if let industry = result.profile.industry {
                Text(industry)
                    .font(.system(size: 12))
                    .foregroundColor(InstitutionalTheme.Colors.textTertiary)
            }

            Rectangle()
                .fill(InstitutionalTheme.Colors.borderSubtle)
                .frame(height: 0.5)

            // Skor satırı — sade
            HStack(alignment: .firstTextBaseline) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(Int(result.totalScore))")
                        .font(.system(size: 32, weight: .medium))
                        .foregroundColor(atlasScoreColor(result.totalScore))
                        .monospacedDigit()
                    Text("/ 100")
                        .font(.system(size: 13))
                        .foregroundColor(InstitutionalTheme.Colors.textSecondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(result.qualityBand.rawValue)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(atlasScoreColor(result.totalScore))
                    Text(result.qualityBand.description)
                        .font(.system(size: 11))
                        .foregroundColor(InstitutionalTheme.Colors.textTertiary)
                        .lineLimit(1)
                }
            }

            Text(result.summary)
                .font(.system(size: 13))
                .foregroundColor(InstitutionalTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(InstitutionalTheme.Colors.surface1)
        .overlay(
            RoundedRectangle(cornerRadius: InstitutionalTheme.Radius.lg, style: .continuous)
                .stroke(InstitutionalTheme.Colors.borderSubtle, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: InstitutionalTheme.Radius.lg, style: .continuous))
    }

    private func atlasScoreColor(_ score: Double) -> Color {
        if score >= 65 { return InstitutionalTheme.Colors.aurora }
        if score >= 45 { return InstitutionalTheme.Colors.titan }
        return InstitutionalTheme.Colors.crimson
    }

    private func atlasScoreTone(_ score: Double) -> ArgusChipTone {
        if score >= 65 { return .aurora }
        if score >= 45 { return .titan }
        return .crimson
    }
    
    // MARK: - Highlights Card
    
    // 2026-04-23 V5.C: Image(systemName) + raw Circle.fill(.opacity(0.9)) →
    // MotorLogo/ArgusSectionCaption/ArgusDot + ArgusChip yığınına geçti.
    private func highlightsCard(_ result: AtlasV2Result) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if !result.highlights.isEmpty {
                highlightBlock(
                    title: "Pozitif sinyaller",
                    items: result.highlights,
                    color: InstitutionalTheme.Colors.aurora
                )
            }

            if !result.warnings.isEmpty {
                highlightBlock(
                    title: "Kritik notlar",
                    items: result.warnings,
                    color: InstitutionalTheme.Colors.titan
                )
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
    }

    private func highlightBlock(title: String,
                                 items: [String],
                                 color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(color)
                Spacer()
                Text("\(items.count)")
                    .font(.system(size: 11))
                    .foregroundColor(InstitutionalTheme.Colors.textTertiary)
                    .monospacedDigit()
            }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(color)
                            .frame(width: 4, height: 4)
                            .padding(.top, 6)
                        Text(item)
                            .font(.system(size: 13))
                            .foregroundColor(InstitutionalTheme.Colors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                            .lineSpacing(2)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    // MARK: - Section Card
    
    private func sectionCard(title: String, icon: String = "", iconColor: Color = InstitutionalTheme.Colors.textPrimary, score: Double, metrics: [AtlasMetric], sectionId: String) -> some View {
        VStack(spacing: 0) {
            // Header
            Button {
                // FIX: withAnimation kaldırıldı - main thread blocking önleniyor
                if expandedSections.contains(sectionId) {
                    expandedSections.remove(sectionId)
                } else {
                    expandedSections.insert(sectionId)
                }
            } label: {
                HStack {
                    if !icon.isEmpty {
                        Image(systemName: icon)
                            .font(.caption.weight(.semibold))
                            .frame(width: 24, height: 24)
                            .background(iconColor.opacity(0.16))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .foregroundColor(iconColor)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.headline)
                            .foregroundColor(InstitutionalTheme.Colors.textPrimary)
                        Text(sectionSubtitle(sectionId))
                            .font(.caption2)
                            .foregroundColor(InstitutionalTheme.Colors.textTertiary)
                    }
                    
                    Spacer()
                    
                    // Mini Progress Bar
                    miniProgressBar(score: score)
                    
                    // Score
                    Text("\(Int(score))")
                        .font(.headline)
                        .foregroundColor(scoreColor(score))
                        .monospacedDigit()
                    
                    // Chevron
                    Image(systemName: expandedSections.contains(sectionId) ? "chevron.up" : "chevron.down")
                        .foregroundColor(InstitutionalTheme.Colors.textSecondary)
                }
                .padding()
            }
            .buttonStyle(.plain)

            if let strongest = metrics.max(by: { $0.score < $1.score }),
               let weakest = metrics.min(by: { $0.score < $1.score }) {
                HStack(spacing: 8) {
                    SectionMetricChip(
                        label: "Güçlü",
                        metric: strongest,
                        color: InstitutionalTheme.Colors.positive
                    )
                    SectionMetricChip(
                        label: "İzle",
                        metric: weakest,
                        color: explanationColor(weakest.status)
                    )
                }
                .padding(.horizontal)
                .padding(.bottom, expandedSections.contains(sectionId) ? 8 : 12)
            }

            let sectionDrivers = topDrivers(from: metrics, limit: 3)
            if !sectionDrivers.isEmpty {
                sectionDriverStrip(sectionDrivers)
                    .padding(.horizontal)
                    .padding(.bottom, expandedSections.contains(sectionId) ? 8 : 12)
            }
            
            // Expanded Content
            if expandedSections.contains(sectionId) {
                VStack(spacing: 16) {
                    ForEach(metrics) { metric in
                        metricRow(metric)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom)
                .padding(.top, 4)
                // transition kaldırıldı - performans optimizasyonu
            }
        }
        .background(cardBackground)
    }
    
    // MARK: - Metric Row
    
    private func metricRow(_ metric: AtlasMetric) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Üst satır: İsim, Değer, Durum
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(metric.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(InstitutionalTheme.Colors.textPrimary)
                    Text("Skor \(Int(metric.score)) / 100")
                        .font(.caption2)
                        .foregroundColor(InstitutionalTheme.Colors.textTertiary)
                }
                
                Spacer()
                
                Text(metric.formattedValue)
                    .font(.subheadline.bold())
                    .foregroundColor(InstitutionalTheme.Colors.textPrimary)
                    .monospacedDigit()
                
                Text(metric.status.label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(explanationColor(metric.status))
            }

            ArgusBar(value: max(0, min(1, metric.score / 100)),
                     color: explanationColor(metric.status),
                     height: 4)

            // Sektör karşılaştırması
            if let sectorAvg = metric.sectorAverage {
                HStack(spacing: 6) {
                    Text("Sektör ort.")
                        .font(.system(size: 11))
                        .foregroundColor(InstitutionalTheme.Colors.textTertiary)
                    Text(AtlasMetric.format(sectorAvg))
                        .font(.system(size: 11))
                        .foregroundColor(InstitutionalTheme.Colors.textSecondary)
                        .monospacedDigit()
                    if let deltaText = metricDeltaText(metric) {
                        Text(deltaText)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(explanationColor(metric.status))
                            .monospacedDigit()
                    }
                }
            }
            
            // Açıklama
            Text(metric.explanation)
                .font(.caption)
                .foregroundColor(explanationColor(metric.status))
                .lineSpacing(1)
            
            // Eğitici not (varsa)
            if !metric.educationalNote.isEmpty {
                HStack(alignment: .top, spacing: 4) {
                    Image(systemName: "book.fill")
                        .font(.caption)
                        .foregroundColor(InstitutionalTheme.Colors.primary)
                    Text(metric.educationalNote)
                        .font(.caption)
                        .foregroundColor(InstitutionalTheme.Colors.textSecondary)
                        .italic()
                }
                .padding(.top, 4)
            }

            if let formula = metric.formula, !formula.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "function")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(InstitutionalTheme.Colors.primary)
                    Text(formula)
                        .font(.caption2)
                        .foregroundColor(InstitutionalTheme.Colors.textSecondary)
                        .lineLimit(1)
                }
                .padding(.top, 2)
            }
            
            ArgusHair()
        }
        .padding(12)
        .background(InstitutionalTheme.Colors.surface2)
        .overlay(
            RoundedRectangle(cornerRadius: InstitutionalTheme.Radius.md, style: .continuous)
                .stroke(InstitutionalTheme.Colors.borderSubtle, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: InstitutionalTheme.Radius.md, style: .continuous))
    }

    /// AtlasMetricStatus → chip tone (sade — motor tint yerine nötr).
    private func statusTone(_ status: AtlasMetricStatus) -> ArgusChipTone {
        switch status {
        case .excellent, .good: return .aurora
        case .neutral:          return .neutral
        case .warning:          return .titan
        case .bad, .critical:   return .crimson
        case .noData:           return .neutral
        }
    }
    
    // MARK: - Summary Card
    
    private func summaryCard(_ result: AtlasV2Result) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Yatırımcı için özet")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(InstitutionalTheme.Colors.textSecondary)

            Text(result.summary)
                .font(.system(size: 13))
                .foregroundColor(InstitutionalTheme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)

            Rectangle()
                .fill(InstitutionalTheme.Colors.borderSubtle)
                .frame(height: 0.5)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 10) {
                miniScoreCard("Karlılık", result.profitabilityScore)
                miniScoreCard("Değerleme", result.valuationScore)
                miniScoreCard("Sağlık", result.healthScore)
                miniScoreCard("Büyüme", result.growthScore)
                miniScoreCard("Nakit", result.cashScore)
                miniScoreCard("Temettü", result.dividendScore)
            }

            if symbol.hasSuffix(".IS") {
                BistSectorComparisonCard(symbol: symbol, result: result)
                    .padding(.top, 4)
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
    }
    
    // MARK: - Value Alert System (BIST-ÖZEL)
    
    private func valueAlertCard(_ result: AtlasV2Result) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Değer uyarıları")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(InstitutionalTheme.Colors.textSecondary)

            if isDeepValue(result) {
                alertLine(
                    title: "Derin değer fırsatı",
                    icon: "star",
                    color: InstitutionalTheme.Colors.aurora
                )
            }
            if isValueTrap(result) {
                alertLine(
                    title: "Value trap uyarısı",
                    icon: "exclamationmark.triangle",
                    color: InstitutionalTheme.Colors.crimson
                )
            }
            if isHighDividendRisky(result) {
                alertLine(
                    title: "Sürdürülemez temettü",
                    icon: "exclamationmark.octagon",
                    color: InstitutionalTheme.Colors.titan
                )
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
    }
    
    private func isDeepValue(_ result: AtlasV2Result) -> Bool {
        guard let pe = result.valuation.allMetrics.first(where: { $0.name.contains("F/K") }),
              let peVal = pe.value else { return false }
        return peVal < 5.0 && result.profitabilityScore > 60
    }
    
    private func isValueTrap(_ result: AtlasV2Result) -> Bool {
        guard let pb = result.valuation.allMetrics.first(where: { $0.name.contains("PD/DD") }),
              let pbVal = pb.value else { return false }
        return pbVal < 1.0 && result.profitabilityScore < 40
    }
    
    private func isHighDividendRisky(_ result: AtlasV2Result) -> Bool {
        guard let div = result.dividend.allMetrics.first(where: { $0.name.contains("Verim") }),
              let divVal = div.value else { return false }
        return divVal > 10.0 && result.cashScore < 40
    }

    private func hasValueAlerts(_ result: AtlasV2Result) -> Bool {
        isDeepValue(result) || isValueTrap(result) || isHighDividendRisky(result)
    }

    private func alertLine(title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(color)
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(InstitutionalTheme.Colors.textPrimary)
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Helpers Extension
extension AtlasV2DetailView {
    
    private func miniScoreCard(_ title: String, _ score: Double) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 11))
                .foregroundColor(InstitutionalTheme.Colors.textSecondary)
                .lineLimit(1)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(Int(score))")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(scoreColor(score))
                    .monospacedDigit()
                Text(sectionGrade(score))
                    .font(.system(size: 10))
                    .foregroundColor(InstitutionalTheme.Colors.textTertiary)
            }
            ArgusBar(value: max(0, min(1, score / 100)),
                     color: scoreColor(score),
                     height: 3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
    }

    // 2026-04-23 V5.C: metricScoreBar kaldırıldı — çağrıldığı yerlerde
    // doğrudan `ArgusBar` kullanılıyor (ortak primitif).

    private func sectionGrade(_ score: Double) -> String {
        switch score {
            case 85...: return "A+"
            case 70..<85: return "A"
            case 55..<70: return "B"
            case 40..<55: return "C"
            case 25..<40: return "D"
            default: return "F"
        }
    }

    private func metricDeltaText(_ metric: AtlasMetric) -> String? {
        guard let value = metric.value, let sector = metric.sectorAverage, sector != 0 else { return nil }
        let delta = ((value - sector) / abs(sector)) * 100
        let sign = delta > 0 ? "+" : ""
        return "\(sign)\(Int(delta.rounded()))%"
    }

    @ViewBuilder
    private func educationalRationaleCard(_ result: AtlasV2Result) -> some View {
        let drivers = topDrivers(from: combinedMetrics(from: result), limit: 5)
        if !drivers.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Skoru ne belirledi")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(InstitutionalTheme.Colors.textSecondary)
                    Spacer()
                    Text("ilk \(min(3, drivers.count)) etken")
                        .font(.system(size: 11))
                        .foregroundColor(InstitutionalTheme.Colors.textTertiary)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(drivers.prefix(3))) { driver in
                            AtlasDriverChip(
                                title: driver.name,
                                subtitle: driver.explanation,
                                impactText: String(format: "%+.0f", driver.score - 50),
                                tint: driverColor(for: driver.impact)
                            )
                        }
                    }
                }

                Rectangle()
                    .fill(InstitutionalTheme.Colors.borderSubtle)
                    .frame(height: 0.5)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Katkı dağılımı")
                        .font(.system(size: 11))
                        .foregroundColor(InstitutionalTheme.Colors.textTertiary)
                    ForEach(Array(drivers.prefix(3))) { driver in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(driverColor(for: driver.impact))
                                .frame(width: 5, height: 5)
                            Text(driver.name)
                                .font(.system(size: 12))
                                .foregroundColor(InstitutionalTheme.Colors.textPrimary)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            Text(String(format: "%+.0f", driver.score - 50))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(driverColor(for: driver.impact))
                                .monospacedDigit()
                        }
                    }
                }
            }
            .padding(14)
            .background(cardBackground)
        }
    }

    private func sectionDriverStrip(_ drivers: [AtlasDriverInsight]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(drivers) { driver in
                    AtlasDriverChip(
                        title: driver.name,
                        subtitle: driver.explanation,
                        impactText: String(format: "%+.0f", driver.score - 50),
                        tint: driverColor(for: driver.impact)
                    )
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func topDrivers(from metrics: [AtlasMetric], limit: Int) -> [AtlasDriverInsight] {
        metrics
            .map { metric in
                AtlasDriverInsight(
                    id: metric.id,
                    name: metric.name,
                    impact: max(-1, min(1, (metric.score - 50.0) / 50.0)),
                    score: metric.score,
                    explanation: metric.explanation
                )
            }
            .sorted { abs($0.impact) > abs($1.impact) }
            .prefix(limit)
            .map { $0 }
    }

    private func donutSlices(from drivers: [AtlasDriverInsight]) -> [AtlasDonutSlice] {
        let magnitudes = drivers.map { max(abs($0.impact), 0.05) }
        let total = max(magnitudes.reduce(0, +), 0.001)
        var cursor = 0.0

        return zip(drivers, magnitudes).map { driver, magnitude in
            let start = cursor / total
            cursor += magnitude
            let end = cursor / total
            return AtlasDonutSlice(
                id: driver.id,
                start: start,
                end: end,
                color: driverColor(for: driver.impact)
            )
        }
    }

    private func combinedMetrics(from result: AtlasV2Result) -> [AtlasMetric] {
        result.valuation.allMetrics
            + result.profitability.allMetrics
            + result.growth.allMetrics
            + result.health.allMetrics
            + result.cash.allMetrics
            + result.dividend.allMetrics
            + result.risk.allMetrics
    }

    private func driverColor(for impact: Double) -> Color {
        if impact > 0.08 { return InstitutionalTheme.Colors.positive }
        if impact < -0.08 { return InstitutionalTheme.Colors.negative }
        return InstitutionalTheme.Colors.warning
    }
    
    // MARK: - Helper Views
    
    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Bilanço analiz ediliyor")
                .font(.system(size: 13))
                .foregroundColor(InstitutionalTheme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 240)
        .padding()
        .background(cardBackground)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 24))
                .foregroundColor(InstitutionalTheme.Colors.crimson)
            Text("Analiz hatası")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(InstitutionalTheme.Colors.textPrimary)
            Text(message)
                .font(.subheadline)
                .foregroundColor(InstitutionalTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
            
            // Debug Info Button
            if let detailedError = detailedError {
                DisclosureGroup("Debug Detayları") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(detailedError)
                            .font(.caption)
                            .foregroundColor(InstitutionalTheme.Colors.textSecondary)
                            .textSelection(.enabled)
                    }
                    .padding(.top, 8)
                }
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 300)
        .padding()
        .background(cardBackground)
    }
    
    private func miniProgressBar(score: Double) -> some View {
        ArgusBar(value: max(0, min(1, score / 100)),
                 color: scoreColor(score),
                 height: 5)
            .frame(width: 60)
    }

    private func sectionSubtitle(_ sectionId: String) -> String {
        switch sectionId {
            case "valuation": return "F/K, PD/DD ve iskonto profili"
            case "profitability": return "Marjlar, verimlilik ve getiri kalitesi"
            case "growth": return "Gelir ve kâr büyüme ivmesi"
            case "health": return "Borçluluk, kaldıraç ve bilanço dengesi"
            case "cash": return "Nakit üretimi ve sürdürülebilirlik"
            case "dividend": return "Temettü verimi ve devamlılık riski"
            case "risk": return "Beta, oynaklık ve kırılganlık haritası"
            default: return "Çekirdek metrikler"
        }
    }
    
    /// 2026-04-30 H-58 — sade. Motor tint border gitti, hairline borderSubtle.
    /// Kullanıldığı yerler: section card, educational rationale card,
    /// loadingView, errorView.
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: InstitutionalTheme.Radius.lg, style: .continuous)
            .fill(InstitutionalTheme.Colors.surface1)
            .overlay(
                RoundedRectangle(cornerRadius: InstitutionalTheme.Radius.lg, style: .continuous)
                    .stroke(InstitutionalTheme.Colors.borderSubtle, lineWidth: 0.5)
            )
    }
    
    private func scoreColor(_ score: Double) -> Color {
        switch score {
            case 70...: return InstitutionalTheme.Colors.positive
            case 50..<70: return InstitutionalTheme.Colors.warning
            case 30..<50: return InstitutionalTheme.Colors.warning.opacity(0.85)
            default: return InstitutionalTheme.Colors.negative
        }
    }
    
    private func explanationColor(_ status: AtlasMetricStatus) -> Color {
        switch status {
            case .excellent, .good: return InstitutionalTheme.Colors.positive
            case .neutral: return InstitutionalTheme.Colors.textPrimary
            case .warning: return InstitutionalTheme.Colors.warning
            case .bad, .critical: return InstitutionalTheme.Colors.negative
            case .noData: return InstitutionalTheme.Colors.textSecondary
        }
    }
    
    // MARK: - Data Loading
    
    private func loadData() async {
        // FIX: Timeout ekleyerek sonsuz beklemeyi önle
        let symbolToAnalyze = symbol
        
        // 60 saniye timeout ile analiz yap (increased from 30 to 60)
        print(" AtlasV2DetailView: Starting analysis for \(symbol)...")
        let loadTask = Task { () -> Result<AtlasV2Result, Error> in
            do {
                // Timeout protection - increased timeout for better reliability
                let result = try await withTimeout(seconds: 60) {
                    try await AtlasV2Engine.shared.analyze(symbol: symbolToAnalyze)
                }
                print("✅ AtlasV2DetailView: Analysis completed for \(symbol)")
                return .success(result)
            } catch {
                // Timeout veya diğer hatalar
                print("❌ AtlasV2DetailView: Analysis failed for \(symbol): \(error)")
                return .failure(error)
            }
        }
        
        let taskResult = await loadTask.value
        
        await MainActor.run {
            switch taskResult {
                case .success(let analysisResult):
                self.result = analysisResult
                self.isLoading = false
                case .failure(let err):
                self.error = err.localizedDescription
                self.detailedError = String(describing: err)
                self.isLoading = false
            }
        }
    }
    
    // MARK: - Timeout Helper
    
    private enum TimeoutError: Error {
        case timeout
    }
    
    private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        return try await withThrowingTaskGroup(of: T.self) { group in
            // Ana işlem
            group.addTask {
                try await operation()
            }
            
            // Timeout task
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw TimeoutError.timeout
            }
            
            // İlk tamamlanan task'ı al
            guard let result = try await group.next() else {
                throw TimeoutError.timeout
            }
            
            // Diğer task'ı iptal et
            group.cancelAll()
            
            return result
        }
    }
}

private struct AtlasDriverInsight: Identifiable {
    let id: String
    let name: String
    let impact: Double
    let score: Double
    let explanation: String
}

private struct AtlasDonutSlice: Identifiable {
    let id: String
    let start: CGFloat
    let end: CGFloat
    let color: Color

    init(id: String, start: Double, end: Double, color: Color) {
        self.id = id
        self.start = CGFloat(start)
        self.end = CGFloat(end)
        self.color = color
    }
}

private struct AtlasDriverChip: View {
    let title: String
    let subtitle: String
    let impactText: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(InstitutionalTheme.Colors.textPrimary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(InstitutionalTheme.Colors.textSecondary)
                    .lineLimit(1)
            }
            Text(impactText)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(tint)
                .monospacedDigit()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(InstitutionalTheme.Colors.surface2)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

// MARK: - BIST SECTOR COMPARISON CARD (NEW)
struct BistSectorAverage: Sendable {
    let profitabilityAvg: Double
    let valuationAvg: Double
    let growthAvg: Double
    let healthAvg: Double
    let cashAvg: Double
    let dividendAvg: Double
}

// MARK: - Preview

#Preview {
    NavigationStack {
        AtlasV2DetailView(symbol: "AAPL")
    }
}
