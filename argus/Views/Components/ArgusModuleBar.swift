import SwiftUI

struct ArgusModuleBar: View {
    let onSelectAtlas: () -> Void
    let onSelectOrion: () -> Void
    let onSelectAether: () -> Void
    let onSelectHermes: () -> Void
    
    // Context
    let assetType: SafeAssetType // Added context
    
    // Optional Scores for badging
    let atlasScore: Double?
    let orionScore: Double?
    let aetherScore: Double?
    let hermesScore: Double?
    
    var body: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ], spacing: 12) {
            
            // Atlas (Fundamental)
            // Logic: Only fully active for Stocks.
            // For ETFs: Active if we have holdings data.
            // For Commodities/Crypto: Disabled/NA.
            if assetType == .stock || (assetType == .etf) {
                ModuleCard(
                    module: .atlas,
                    score: atlasScore,
                    action: onSelectAtlas,
                    isDisabled: atlasScore == nil && assetType == .etf ? false : false // Allow clicking to see "No Holdings" msg
                )
            } else {
                 // Commodities/Crypto/Indices -> Show "N/A" Card
                 DisabledModuleCard(module: .atlas, reason: "N/A")
            }
            
            ModuleCard(
                module: .orion,
                score: orionScore,
                action: onSelectOrion
            )
            
            ModuleCard(
                module: .aether,
                score: aetherScore,
                action: onSelectAether
            )
            
            ModuleCard(
                module: .hermes,
                score: hermesScore,
                action: onSelectHermes
            )
        }
    }
}

// 2026-04-30 H-57 — sade. ArgusEyeView gözü + 16pt bold rounded başlık +
// 36pt tinted skor circle + shadow → sade kart: sentence başlık + alt
// muted etiket + sağda renkli text skor (circle yok). Hairline border,
// shadow yok.

struct DisabledModuleCard: View {
    let module: ArgusModule
    let reason: String

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(ArgusScoreSystem.moduleTitle(module))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(InstitutionalTheme.Colors.textTertiary)
                Text(reason)
                    .font(.system(size: 11))
                    .foregroundColor(InstitutionalTheme.Colors.textTertiary)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(InstitutionalTheme.Colors.surface1.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct ModuleCard: View {
    let module: ArgusModule
    let score: Double?
    let action: () -> Void
    var isDisabled: Bool = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(ArgusScoreSystem.moduleTitle(module))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(InstitutionalTheme.Colors.textPrimary)
                        .lineLimit(1)
                    Text(ArgusScoreSystem.moduleSubtitle(module))
                        .font(.system(size: 11))
                        .foregroundColor(InstitutionalTheme.Colors.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                // Sade skor — circle ve gradient yok, renkli text + opsiyonel
                // küçük dot
                if let s = score {
                    HStack(spacing: 4) {
                        Text("\(Int(s))")
                            .font(.system(size: 16, weight: .medium, design: .monospaced))
                            .foregroundColor(ArgusScoreSystem.color(for: s))
                            .monospacedDigit()
                    }
                } else {
                    Text("—")
                        .font(.system(size: 16, design: .monospaced))
                        .foregroundColor(InstitutionalTheme.Colors.textTertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(InstitutionalTheme.Colors.surface1)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(InstitutionalTheme.Colors.borderSubtle, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
