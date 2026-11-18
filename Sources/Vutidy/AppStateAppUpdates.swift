import SwiftUI
import CoreKit
import Modules

extension AppState {
    static let appsCheckInterval: TimeInterval = 24 * 3600

    /// Kiểm tra cask Homebrew lỗi thời. `silent`: chạy nền theo chu kỳ, chỉ báo khi xuất hiện bản mới.
    func checkAppUpdates(silent: Bool = false) async {
        guard !outdatedLoading else { return }
        outdatedLoading = true
        let before = Set(outdatedApps.map(\.id))
        let found = await Updater.brewOutdated()
        outdatedLoading = false
        outdatedApps = found
        lastAppsCheck = Date(); UserDefaults.standard.set(lastAppsCheck, forKey: "lastAppsCheck")
        let fresh = found.filter { !before.contains($0.id) }
        if silent, !fresh.isEmpty {
            notify(trf("%@ ứng dụng có bản cập nhật.", "\(found.count)"), .success, action: .openApps)
        }
    }

    /// Mỗi giờ xem đã quá 24 giờ kể từ lần kiểm tra cuối chưa; nếu rồi thì kiểm tra nền.
    func startAppUpdateSchedule() {
        appsCheckTask?.cancel()
        guard autoCheckApps else { return }
        appsCheckTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            while !Task.isCancelled {
                guard let self else { return }
                if self.autoCheckApps, Date().timeIntervalSince(self.lastAppsCheck ?? .distantPast) > Self.appsCheckInterval {
                    await self.checkAppUpdates(silent: true)
                }
                try? await Task.sleep(nanoseconds: 3600 * 1_000_000_000)
            }
        }
    }
}
