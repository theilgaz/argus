import SwiftUI

/// Anasayfada görünen makro durum kartı.
///
/// 2026-04-30 H-58 — sade refactor:
///   • "MAKRO" caps mono caption gitti, yerine sentence "Makro"
///   • Skor: 22pt semibold mono → 22pt medium mono, regime-tinted
///   • Border: 1pt → 0.5pt borderSubtle (hairline)
///   • "Bugün" başlık + iki sıfat phrase aynen kaldı (P3 onaylı)
///
/// Bu kart hem makro skoru hem rejim bilgisini sıfat zinciri olarak
/// taşır — anasayfada iki ayrı kart yerine tek kart. Detay sheet'inde
/// tam rejim adı, aktif strateji ("salınım/hücum") ve üç dilimlik
/// makro skor (leading/coincident/lagging) yaşar.
///
/// Tap → makro detay sheet.
struct AetherDashboardHUD: View {
    let rating: MacroEnvironmentRating?
    let onTap: () -> Void

    var body: some View {
        // 2026-05-03 H-60.2: ölçeklendirme fix (build incelemesi sonrası).
        //   • Skor 22pt → 30pt: ana sayfa hero kartı, sayı "yamuk" duruyordu;
        //     başlık 17pt ile birlikte 30pt sayı dengeli görsel ağırlık verir.
        //   • Vertical padding 14 → 18: sayı büyüdüğü için kart yüksekliği
        //     genişliyor, dış nefes boşluğu da artırıldı.
        //   • Horizontal padding 14 → 16: iç içerik diğer kartlarla aynı
        //     iç boşluk standardına geldi.
        //   • HStack(alignment: .firstTextBaseline) — "Bugün" başlığı +
        //     büyük skor sayısı baseline'ı ortalanır, "yana sürünmüş" his
        //     gider.
        //   • Sıfat satırı altta hâlâ küçük 13pt, baseline'a değil hizalanır.
        Button(action: onTap) {
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

                scoreBlock
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
    }

    // MARK: - Score block (sağ — büyük skor, üstte "Makro" caption inline)

    @ViewBuilder
    private var scoreBlock: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("Makro")
                .font(.system(size: 11))
                .foregroundColor(InstitutionalTheme.Colors.textTertiary)
            if let r = rating {
                Text("\(Int(r.numericScore))")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundColor(scoreColor(r.numericScore))
                    .monospacedDigit()
            } else {
                Text("—")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundColor(InstitutionalTheme.Colors.textTertiary)
            }
        }
    }

    private func scoreColor(_ score: Double) -> Color {
        if score >= 70 { return InstitutionalTheme.Colors.aurora }
        if score >= 45 { return InstitutionalTheme.Colors.textPrimary }
        return InstitutionalTheme.Colors.crimson
    }

    // MARK: - Adjective dictionary
    //
    // Trader jargonu (yatay seyir / salınım / risk-on) yerine yeni
    // indiren biri için anlaşılır iki sıfat. Detay sayfasında tam
    // rejim adı + aktif strateji yine var.
    private var adjectivePhrase: String {
        guard let r = rating else { return "Hesaplanıyor" }
        switch r.numericScore {
        case 70...:   return "İyimser, hareketli"
        case 55...:   return "Sakin, dengeli"
        case 40..<55: return "Tedirgin, dalgalı"
        default:      return "Riskli, savunmada"
        }
    }
}
