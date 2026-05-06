import Foundation

/// Sirkiye Engine için Türkiye geneli haber snapshot'ı üretir.
///
/// Eski sürümde 5 farklı callsite (`AutoPilotStore.prepareSirkiyeInput` ×3 path,
/// `SanctumViewModel`, `SanctumBistHoloPanelView`, `TCMBDataService.getSirkiyeInput`)
/// `SirkiyeEngine.SirkiyeInput.newsSnapshot`'ı **HARDCODED nil** olarak geçiyordu.
/// Sonuç: SirkiyeEngine'in `analyzePoliticalAtmosphere(news:)` fonksiyonu
/// `guard let news = news, !news.insights.isEmpty else { return (50, .neutral, ...) }`
/// guard'ında early return yapıyor → Türkçe siyasi keyword tablosu (siyasi yasak,
/// kayyum, darbe, görevden alma, yaptırım, ...) **hiç çalışmıyordu**, siyasi
/// risk skoru her zaman nötr (50) dönüyordu. Politik kriz olsa bile motor görmüyor.
///
/// Bu helper `BISTSentimentEngine.analyzeSentimentPayload(for: "BIST")` çağrısı yapar.
/// "BIST" sembolü `companyNames` map'inde olmadığı için engine otomatik olarak
/// **general market sentiment** moduna düşer (`isGeneralMarketSentiment = true`),
/// tüm BIST RSS haberlerini kullanır. Sonuç `BISTSentimentAdapter.adapt(...)` ile
/// `HermesNewsSnapshot`'a dönüştürülür ve SirkiyeEngine bunu siyasi keyword'lerle tarar.
///
/// Cache 15 dk (BISTSentimentEngine içi) — paralel callsite'lar aynı snapshot'ı paylaşır,
/// gereksiz fetch yok.
enum SirkiyeNewsHelper {
    /// Türkiye geneli haber snapshot'ı. Veri yoksa nil — caller `SirkiyeEngine.analyze()`
    /// için bu değeri olduğu gibi geçer; engine zaten nil-safe.
    static func snapshotForTurkey() async -> HermesNewsSnapshot? {
        do {
            let payload = try await BISTSentimentEngine.shared.analyzeSentimentPayload(for: "BIST")
            // RSS hiç haber dönmediyse (RSS provider hata aldı/network yok),
            // adapter fallback insight üretir ama articles boş olur.
            // Snapshot insights'ı en az 1 olduğunda anlamlı (SirkiyeEngine guard let news, !insights.isEmpty).
            let snapshot = BISTSentimentAdapter.adapt(result: payload.result, articles: payload.articles)
            return snapshot.insights.isEmpty ? nil : snapshot
        } catch {
            print("⚠️ SirkiyeNewsHelper: Türkiye haber snapshot'ı alınamadı: \(error.localizedDescription)")
            return nil
        }
    }
}
