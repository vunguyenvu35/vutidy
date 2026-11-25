import SwiftUI
import CoreKit
import Modules
import SafetyLayer

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

    /// Chạy `brew upgrade --cask` cho một ứng dụng; trạng thái nằm trong AppState nên không mất khi đổi trang.
    func upgradeApp(_ a: OutdatedApp) async {
        guard !upgradingApps.contains(a.id) else { return }
        upgradingApps.insert(a.id); upgradeErrors[a.id] = nil
        let r = await Updater.upgrade(a)
        executor.audit.append(AuditRecord(date: Date(), action: "command", path: "brew upgrade --cask \(a.name)", bytes: 0,
                                          ruleID: "updater", mode: "run", result: r.ok ? "done" : "failed: \(r.stderr.prefix(200))"))
        upgradingApps.remove(a.id)
        if r.ok {
            outdatedApps.removeAll { $0.id == a.id }
            toast = trf("Đã cập nhật %@", a.name)
        } else {
            let line = r.stderr.split(separator: "\n").map(String.init).last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? "exit \(r.status)"
            upgradeErrors[a.id] = line
            notify(trf("Cập nhật %@ thất bại", a.name), .error)
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
