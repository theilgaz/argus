import SwiftUI

/// Risk radarı kartı (eski adıyla Phoenix Radar).
///
/// 2026-04-30 H-58 — sade refactor.
/// Eski: raw .orange/.white/.gray + Color(white:0.1) + flame.fill +
/// .symbolEffect(.pulse) + heavy başlık. Yeni: InstitutionalTheme tokenları,
/// sade dil, sentence başlık ("Risk radarı"), pulse animasyonu kalktı.

struct PhoenixRadarCard: View {
    @ObservedObject var scanner = PhoenixScannerService.shared

    var body: some View {
        VStack(spacing: 0) {
            header

            if scanner.latestCandidates.isEmpty {
                if scanner.isScanning {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text(scanner.currentStatus)
                            .font(.system(size: 12))
                            .foregroundColor(InstitutionalTheme.Colors.textSecondary)
                    }
                    .frame(height: 120)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 28))
                            .foregroundColor(InstitutionalTheme.Colors.textTertiary)
                        Text("Henüz sinyal yok")
                            .font(.system(size: 12))
                            .foregroundColor(InstitutionalTheme.Colors.textSecondary)
                        Text("Analizi başlatmak için \"Tara\" butonuna basın.")
                            .font(.system(size: 11))
                            .foregroundColor(InstitutionalTheme.Colors.textTertiary)
                    }
                    .frame(height: 120)
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(scanner.latestCandidates.prefix(5)) { candidate in
                            PhoenixCandidateItem(candidate: candidate)
                        }
                    }
                    .padding(12)
                }
            }
        }
        .background(InstitutionalTheme.Colors.surface1)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(InstitutionalTheme.Colors.borderSubtle, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Header (sade)

    private var header: some View {
        HStack {
            Text("Risk radarı")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(InstitutionalTheme.Colors.textPrimary)

            Spacer()

            if scanner.isScanning {
                Text("%\(Int(scanner.progress * 100))")
                    .font(.system(size: 12))
                    .foregroundColor(InstitutionalTheme.Colors.textSecondary)
                    .monospacedDigit()
            } else {
                Button(action: {
                    Task { await scanner.runPipeline(mode: .balanced) }
                }) {
                    Text("Tara")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(InstitutionalTheme.Colors.textPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(InstitutionalTheme.Colors.surface2)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .overlay(
            Rectangle()
                .fill(InstitutionalTheme.Colors.borderSubtle)
                .frame(height: 0.5),
            alignment: .bottom
        )
    }
}

struct PhoenixCandidateItem: View {
    let candidate: PhoenixCandidate

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(candidate.symbol)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(InstitutionalTheme.Colors.textPrimary)

                Spacer()

                if let score = candidate.evidence?.trendScore {
                    Text(String(format: "%.1f", score))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(score > 0
                                         ? InstitutionalTheme.Colors.aurora
                                         : InstitutionalTheme.Colors.crimson)
                        .monospacedDigit()
                }
            }

            Text(candidate.assetType.rawValue)
                .font(.system(size: 11))
                .foregroundColor(InstitutionalTheme.Colors.textTertiary)
                .lineLimit(1)

            Text("$\(String(format: "%.2f", candidate.lastPrice))")
                .font(.system(size: 12))
                .foregroundColor(InstitutionalTheme.Colors.textSecondary)
                .monospacedDigit()

            Rectangle()
                .fill(InstitutionalTheme.Colors.borderSubtle)
                .frame(height: 0.5)

            Text(candidate.level0Reason)
                .font(.system(size: 10))
                .foregroundColor(InstitutionalTheme.Colors.textTertiary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(height: 24, alignment: .topLeading)
        }
        .padding(12)
        .frame(width: 140, height: 130)
        .background(InstitutionalTheme.Colors.surface2)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
