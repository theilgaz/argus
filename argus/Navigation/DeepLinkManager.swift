import SwiftUI
import Combine

enum TabItem: String, CaseIterable {
    case home = "Ana Sayfa"
    case kokpit = "Kokpit"
    case portfolio = "Portföy"
    case settings = "Ayarlar"

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .kokpit: return "gauge.with.dots.needle.bottom.50percent"  // Terminal gauge
        case .portfolio: return "briefcase.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

@MainActor
class DeepLinkManager: ObservableObject {
    static let shared = DeepLinkManager()

    @Published var selectedTab: TabItem = .home // Default to Home view

    // Sayfa içi navigasyon için kullanılabilir (örn. belirli bir hisseye git)
    @Published var selectedStockSymbol: String?

    private init() {}

    /// Tab'a geçiş yapar. Eğer kullanıcı şu anki tab'da bir push'lu detay
    /// ekrandaysa, navigation stack'i de boşaltır — drawer'dan "Ana sayfa"
    /// gibi item'lara basıldığında push'lu ekranda sıkışmayı önler.
    ///
    /// 2026-05-03 H-59 fix: önceden sadece `selectedTab = tab` yapıyordu.
    /// Aynı tab'da push'lu ekrandayken aynı tab'a gitmeye çalışınca
    /// `onChange(selectedTab)` tetiklenmediği için `popToRoot()` çağrılmıyor,
    /// kullanıcı detay ekranında kalıp sanki link çalışmıyormuş gibi
    /// hissediyordu. Şimdi her zaman önce stack temizlenir, sonra tab set'lenir.
    func navigate(to tab: TabItem) {
        NavigationRouter.shared.popToRoot()
        self.selectedTab = tab
    }

    func openStockDetail(symbol: String) {
        NavigationRouter.shared.popToRoot()
        self.selectedTab = .home
        self.selectedStockSymbol = symbol
    }
}
