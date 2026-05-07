import SwiftUI

// MARK: - StockDetailView (silindi)
//
// 2026-05-05 H-67 — komple silindi.
//
// Eski sembol detay shell'i. StockDetailV5Body'yi sarmalayan ince
// wrapper'dı (~200 satır). Hiçbir yerden çağrılmıyor — sembol
// detayı artık `ArgusSanctumView(symbol:viewModel:)` üzerinden
// NavigationLink push'larıyla açılıyor.
//
// Dosya bu satıra düşürüldü; gelecek refactor turunda dosya silinebilir.
