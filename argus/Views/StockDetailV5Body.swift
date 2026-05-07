import SwiftUI

// MARK: - StockDetailV5Body (silindi)
//
// 2026-05-05 H-67 — komple silindi.
//
// Bu dosya V5 mockup HTML'sinden türetilmiş eski sembol detay
// gövdesiydi (~3000+ satır). Render path'i: StockDetailView →
// StockDetailV5Body. StockDetailView kendisi de hiçbir yerden
// çağrılmıyor (DeepLinkManager.openStockDetail sadece function
// adı eşleşmesi, gerçek struct çağrısı yok). Sembol detayı artık
// ArgusSanctumView üzerinden açılıyor (modül chip'leriyle).
//
// Dosya bu satıra düşürüldü; gelecek refactor turunda dosya silinebilir.
