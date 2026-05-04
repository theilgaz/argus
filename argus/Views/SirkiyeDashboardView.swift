import SwiftUI

/// Sirkiye nabız özet kartı (ana sayfa Sirkiye tab).
///
/// 2026-05-03 H-60: Global tab'daki AetherDashboardHUD ile aynı yapıya
/// çekildi — kullanıcı sekme değiştirince zihinsel haritası bozulmuyor.
///
/// Eski yapı (3 sütun: 56pt gradient ring + Duruş bloğu + BIST 100 + delta,
/// üstünde ayrı "Sirkiye nabzı" header + statusPill) tutarsızdı. Global
/// tarafta sade "Bugün + sıfat + skor" 2 sütun varken Sirkiye'de her şey
/// vardı.
///
/// Yeni yapı:
///   • Üst kart (Global'la aynı dilde): "Bugün" başlık + "mod · duruş"
///     sıfat zinciri + sağda "Nabız" + büyük skor (skora göre tonlu)
///   • Alt strip: BIST 100 sade satır (caption + değer + delta)
///
/// Tap → SirkiyeAetherView detay sheet (mevcut davranış aynen).
/// Public API korundu: `init(viewModel: TradingViewModel)`.

struct SirkiyeDashboardView: View {
    @ObservedObject var viewModel: TradingViewModel

    @State private var showDetails = false
    @State private var xu100Value: Double = 0
    @State private var xu100Change: Double = 0
    @State private var fallbackMacroScore: Double = 50
    @State private var fallbackMacroReady = false

    // MARK: - Derived data

    private var atmosphere: (score: Double, mode: MarketMode, reason: String) {
        if let decision = viewModel.bistAtmosphere {
            let score = decision.netSupport * 100.0
            let reason = decision.winningProposal?.reasoning ?? "Analiz tamamlandı"
            return (score, decision.marketMode, reason)
        } else {
            return (fallbackMacroScore, modeFrom(score: fallbackMacroScore), "TCMB makro snapshot")
        }
    }

    private var xu100DisplayValue: String {
        xu100Value > 0 ? String(format: "%.0f", xu100Value) : "—"
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 12) {
            heroCard
            xu100Strip
        }
        .onAppear {
            Task {
                if viewModel.bistAtmosphere == nil {
                    await viewModel.refreshBistAtmosphere()
                }
                await loadFallbackMacroScore()
                await loadXU100()
            }
        }
        .sheet(isPresented: $showDetails) {
            NavigationStack {
                SirkiyeAetherView(linkedDecision: viewModel.bistAtmosphere)
            }
            .preferredColorScheme(.dark)
        }
    }

    // MARK: - Hero kartı (Global AetherDashboardHUD ile aynı dil)

    private var heroCard: some View {
        Button(action: { showDetails = true }) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Bugün")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(InstitutionalTheme.Colors.textPrimary)
                        .lineLimit(1)
                    Text(adjectivePhrase)
                        .font(.system(size: 13))
                        .foregroundColor(InstitutionalTheme.Colors.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("Nabız")
                        .font(.system(size: 11))
                        .foregroundColor(InstitutionalTheme.Colors.textTertiary)
                    Text("\(Int(atmosphere.score))")
                        .font(.system(size: 30, weight: .medium))
                        .foregroundColor(scoreColor)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(InstitutionalTheme.Colors.surface1)
            .overlay(
                RoundedRectangle(cornerRadius: InstitutionalTheme.Radius.lg, style: .continuous)
                    .stroke(InstitutionalTheme.Colors.borderSubtle, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: InstitutionalTheme.Radius.lg, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityHint(Text("Sirkiye makro detayını aç"))
    }

    // MARK: - BIST 100 strip (sade tek satır)

    private var xu100Strip: some View {
        HStack(spacing: 8) {
            Text("BIST 100")
                .font(.system(size: 11))
                .foregroundColor(InstitutionalTheme.Colors.textTertiary)
            Spacer()
            if xu100Value > 0 {
                Text(xu100DisplayValue)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(InstitutionalTheme.Colors.textPrimary)
                    .monospacedDigit()
                Text(String(format: "%+.2f%%", xu100Change))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(xu100Change >= 0
                                     ? InstitutionalTheme.Colors.aurora
                                     : InstitutionalTheme.Colors.crimson)
                    .monospacedDigit()
            } else {
                Text("yükleniyor")
                    .font(.system(size: 12))
                    .foregroundColor(InstitutionalTheme.Colors.textTertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(InstitutionalTheme.Colors.surface1)
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(InstitutionalTheme.Colors.borderSubtle, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal, 16)
    }

    // MARK: - Sıfat zinciri (mod · duruş tek satır)

    /// Global'da "İyimser, hareketli" gibi 2 sıfat var. Sirkiye'de mod
    /// (Aşırı korku/Açgözlü vs) + duruş (Defansif/Risk açık vs) birleşir.
    private var adjectivePhrase: String {
        let mode = modeDisplayText.lowercased()
        let stance = stanceText.lowercased()
        if stance == "bekleniyor" { return mode }
        return "\(mode) · \(stance)"
    }

    // MARK: - Data Loading

    private func loadXU100() async {
        do {
            let quote = try await BorsaPyProvider.shared.getXU100()
            await MainActor.run {
                xu100Value = quote.last
                xu100Change = quote.changePercent
            }
        } catch {
            print("⚠️ XU100 yüklenemedi: \(error)")
        }
    }

    private func loadFallbackMacroScore() async {
        let macro = await SirkiyeAetherEngine.shared.analyze(forceRefresh: true)
        await MainActor.run {
            fallbackMacroScore = max(0, min(100, macro.overallScore))
            fallbackMacroReady = true
        }
    }

    // MARK: - Derived styling

    private var scoreColor: Color {
        if atmosphere.score >= 70 { return InstitutionalTheme.Colors.aurora }
        if atmosphere.score >= 50 { return InstitutionalTheme.Colors.holo }
        if atmosphere.score >= 30 { return InstitutionalTheme.Colors.titan }
        return InstitutionalTheme.Colors.crimson
    }

    /// 2026-04-30 H-49 — sade. Caps "PANİK MOD / AŞIRI KORKU" → sentence
    /// case ifadeler.
    private var modeDisplayText: String {
        switch atmosphere.mode {
        case .panic:        return "Panik"
        case .extremeFear:  return "Aşırı korku"
        case .fear:         return "Korku"
        case .neutral:      return "Nötr"
        case .greed:        return "Açgözlü"
        case .extremeGreed: return "Aşırı açgözlü"
        case .complacency:  return "Rehavet"
        }
    }

    private func modeFrom(score: Double) -> MarketMode {
        switch score {
        case ..<25:  return .panic
        case ..<40:  return .extremeFear
        case ..<50:  return .fear
        case ..<60:  return .neutral
        case ..<75:  return .greed
        case ..<90:  return .extremeGreed
        default:     return .complacency
        }
    }

    private var stanceText: String {
        guard let decision = viewModel.bistAtmosphere else { return "Bekleniyor" }
        switch decision.stance {
        case .riskOff:   return "Risk kapalı"
        case .defensive: return "Defansif"
        case .cautious:  return "Tedbirli"
        case .riskOn:    return "Risk açık"
        }
    }

    // MARK: - Accessibility

    private var accessibilitySummary: Text {
        let changeStr = xu100Value > 0
            ? String(format: "%+.2f yüzde", xu100Change)
            : "endeks yükleniyor"
        return Text(
            "Bugün \(modeDisplayText.lowercased()), \(stanceText.lowercased()), nabız \(Int(atmosphere.score)). " +
            "BIST 100 \(xu100DisplayValue), \(changeStr)."
        )
    }
}

// MARK: - Custom Badge Helper (legacy, korunuyor — diğer ekranlar kullanıyor olabilir)

extension View {
    func paddingbadge(_ color: Color) -> some View {
        self.padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.2))
            .foregroundColor(color)
            .cornerRadius(8)
    }
}
