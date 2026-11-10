import SwiftUI
import CoreKit
import Modules
import SafetyLayer

extension AppState {
    var isBusyUpdating: Bool {
        switch appUpdate { case .checking, .downloading, .installing: return true; default: return false }
    }

    /// Hỏi GitHub bản mới nhất. `silent`: chạy nền lúc mở app; chỉ báo khi có bản mới, im lặng nếu lỗi/đã mới nhất.
    func checkForUpdates(silent: Bool = false) async {
        guard !isBusyUpdating else { return }
        if case .available = appUpdate, silent { return }
        appUpdate = .checking
        do {
            let r = try await UpdateChecker.fetchLatest()
            lastUpdateCheck = Date(); UserDefaults.standard.set(lastUpdateCheck, forKey: "lastUpdateCheck")
            if let r {
                appUpdate = .available(r)
                if silent { notify(trf("Có Vutidy %@ mới", "\(r.version)"), .success, action: .openUpdate) }
            } else {
                appUpdate = .upToDate
            }
        } catch {
            appUpdate = silent ? .idle : .failed(error.localizedDescription)
        }
    }

    /// Tải → xác minh SHA-256 → giải nén và kiểm tra chữ ký → thay app → mở lại. Mọi lỗi dừng trước khi động tới app đang chạy.
    func installUpdate() async {
        guard case .available(let r) = appUpdate else { return }
        do {
            try AppInstaller.checkInstallable()
            let work = FileManager.default.temporaryDirectory.appendingPathComponent("vutidy-update-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            appUpdate = .downloading(0)
            let sumsText: String? = try await {
                guard let u = r.sumsURL else { return nil }
                let f = try await AppInstaller.download(u, to: work) { _ in }
                return try? String(contentsOf: f, encoding: .utf8)
            }()
            let zip = try await AppInstaller.download(r.zipURL, to: work) { p in Task { @MainActor in self.appUpdate = .downloading(p) } }
            appUpdate = .installing
            try AppInstaller.verify(zip: zip, name: r.zipName, sums: sumsText)
            let newApp = try AppInstaller.extract(zip: zip, into: work, expecting: r.version, current: Bundle.main.bundleURL)
            try AppInstaller.stageAndSwap(newApp: newApp)
            executor.audit.append(AuditRecord(date: Date(), action: "command", path: "update Vutidy \(UpdateChecker.currentVersion) → \(r.version)", bytes: 0, ruleID: "self-update", mode: "run", result: "done"))
            AppDelegate.quitCompletely()
        } catch {
            appUpdate = .failed(error.localizedDescription)
        }
    }
}
