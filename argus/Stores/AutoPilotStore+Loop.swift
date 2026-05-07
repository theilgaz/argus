import Foundation

// MARK: - Loop / Timer Management
/// AutoPilotStore'un Timer yönetimi. 180sn ana interval, opportunity modda 120sn.
/// Triple-trigger guard: aynı 2sn pencerede ard arda startTimer çağrılırsa
/// immediate-run sadece bir kez yapılır.
extension AutoPilotStore {

    func startAutoPilotLoop() {
        ArgusLogger.info("AutoPilotStore: Starting Loop...", category: "OTOPİLOT")
        // Not: `isAutoPilotEnabled = true` didSet → handleAutoPilotStateChange →
        // startTimer zaten çağrılıyor. Burada ekstra startTimer() çağırmak
        // üçlü immediate-run tetiklemesine (triple trigger bug) yol açıyordu.
        if isAutoPilotEnabled {
            // Zaten açıksa didSet tetiklenmez — timer yoksa elle başlat.
            if autoPilotTimer == nil { startTimer() }
        } else {
            self.isAutoPilotEnabled = true // didSet → startTimer()
        }
    }

    func stopAutoPilotLoop() {
        ArgusLogger.info("AutoPilotStore: Stopping Loop...", category: "OTOPİLOT")
        autoPilotTimer?.invalidate()
        autoPilotTimer = nil
    }

    func restartTimer(interval: TimeInterval) {
        guard isAutoPilotEnabled else { return }
        autoPilotTimer?.invalidate()
        autoPilotTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { [weak self] in
                await self?.runAutoPilot()
            }
        }
        ArgusLogger.info("AutoPilotStore: Timer interval güncellendi → \(Int(interval))sn", category: "OTOPİLOT")
    }

    func startTimer() {
        autoPilotTimer?.invalidate()

        ArgusLogger.info("AutoPilotStore: Timer başlatılıyor...", category: "OTOPİLOT")
        ArgusLogger.info("AutoPilotStore: isAutoPilotEnabled = \(isAutoPilotEnabled)", category: "OTOPİLOT")
        ArgusLogger.info("AutoPilotStore: Watchlist count = \(WatchlistStore.shared.items.count)", category: "OTOPİLOT")

        // 171 sembol taraması + BorsaPy yavaşlığı + Gemini 429 retry'leri toplamda
        // 1-2 dk sürüyor. Timer 60sn ise ikinci/üçüncü loop isScanning guard'ı ile
        // boşa dönüyordu. 180sn (3 dk) interval ile her tur gerçekten çalışıyor.
        autoPilotTimer = Timer.scheduledTimer(withTimeInterval: 180.0, repeats: true) { [weak self] _ in
            Task { [weak self] in
                await self?.runAutoPilot()
            }
        }

        // Immediate run — aynı pencerede (2sn) birden çok startTimer çağrılırsa
        // sadece ilkinde tetikle. Bu guard olmadan init-didSet + bootstrap aynı
        // saniyede üçlü scan başlatıyordu.
        let now = Date()
        if let last = lastImmediateRunAt, now.timeIntervalSince(last) < 2.0 {
            ArgusLogger.warn("AutoPilotStore: startTimer re-entry (<2s), immediate-run atlandı", category: "OTOPİLOT")
            return
        }
        lastImmediateRunAt = now
        Task {
            // 2026-05-04: İlk scan'i 25sn defer et — TradingViewModel'in 319 sembol
            // watchlist batch refresh'i MarketDataStore cache'ini doldurana kadar bekle.
            // Aksi halde AutoPilot ve watchlist refresh aynı anda Yahoo'nun 4 inflight
            // cap'ine yığılıp 30sn rate-cap timeout'larına neden oluyordu (startup stampede).
            // Sonraki tick'ler (180sn timer) defer'sız çalışır — cache zaten sıcak.
            try? await Task.sleep(nanoseconds: 25_000_000_000)
            await runAutoPilot()
        }
    }
}
