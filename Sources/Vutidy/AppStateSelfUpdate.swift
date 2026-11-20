import SwiftUI
import AppKit
import CoreKit
import Modules

extension AppState {
    /// Đang có việc dở mà đóng app sẽ làm gián đoạn.
    var selfUpdateBusyWithWork: Bool {
        !scanning.isEmpty || !cleaning.isEmpty || smartScanning || malwareScanning || fileChecking || outdatedLoading
            || { if case .downloading = appUpdate { return true }; if case .installing = appUpdate { return true }; return false }()
    }

    /// Mỗi 10 phút: kiểm tra bản mới nếu đã quá 24 giờ (theo cài đặt), rồi tự cài nếu được phép. Chỉ chạy từ .app.
    func startSelfUpdateWatch() {
        selfUpdateTask?.cancel()
        guard AppDelegate.canRelaunch else { return }
        // VUTIDY_UPDATE_TICK_SECONDS: chu kỳ ngắn hơn để thử luồng tự cài mà không phải chờ 10 phút.
        let period = UInt64((ProcessInfo.processInfo.environment["VUTIDY_UPDATE_TICK_SECONDS"].flatMap(Double.init) ?? 600) * 1_000_000_000)
        selfUpdateTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            while !Task.isCancelled {
                guard let self else { return }
                await self.selfUpdateTick()
                try? await Task.sleep(nanoseconds: period)
            }
        }
    }

    func selfUpdateTick() async {
        if autoCheckUpdates, !hasUpdate, !isBusyUpdating, Date().timeIntervalSince(lastUpdateCheck ?? .distantPast) > 24 * 3600 {
            await checkForUpdates(silent: true)
        }
        var avail: ReleaseInfo?
        if case .available(let r) = appUpdate { avail = r }
        guard AutoInstallPolicy.shouldInstall(enabled: autoInstallUpdates, canRelaunch: AppDelegate.canRelaunch, available: avail,
                                              alreadyTried: autoInstallTried, busyWithWork: selfUpdateBusyWithWork, appIsActive: NSApp.isActive),
              let r = avail else { return }
        autoInstallTried = r.version                      // chỉ thử một lần mỗi bản trong phiên này; lỗi thì để người dùng tự bấm
        await installUpdate()
        if case .failed(let m) = appUpdate { notify(trf("Tự cập nhật không thành công: %@", m), .error, action: .openUpdate) }
    }

    /// Sau khi cập nhật xong (lần mở đầu tiên của bản mới): báo một lần "Vutidy đã cập nhật lên X".
    func announceUpdateIfAny() {
        guard AppDelegate.canRelaunch else { return }
        let cur = UpdateChecker.currentVersion
        let d = UserDefaults.standard
        if let last = d.string(forKey: "lastRunVersion").flatMap(AppVersion.init), last < cur {
            notify(trf("Vutidy đã cập nhật lên %@", "\(cur)"), .success)
        }
        d.set("\(cur)", forKey: "lastRunVersion")
    }
}
