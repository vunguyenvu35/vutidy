import Foundation
import CoreServices
import AppKit
import SafetyLayer
import CoreKit
import ScanEngine

public struct AppInfo: Identifiable, Sendable, Hashable {
    public var id: String { url.path }
    public let url: URL
    public let name: String
    public let bundleID: String
    public let size: Int64
    public let lastUsed: Date?
    public let source: Source
    /// Nhà sản xuất (từ chữ ký mã, nếu không có thì từ bundle ID) và khoá để gom nhóm.
    public var vendor: String = ""
    public var vendorKey: String = ""
    public enum Source: String, Sendable {
        case appStore = "App Store", homebrew = "Homebrew", other = "Khác"
        public var title: String { tr(rawValue) }
    }
}

public enum Uninstaller {
    public static let leftoverDirs = [
        "~/Library/Application Support", "~/Library/Caches", "~/Library/Preferences", "~/Library/Containers",
        "~/Library/Group Containers", "~/Library/Saved Application State", "~/Library/HTTPStorages",
        "~/Library/WebKit", "~/Library/Logs", "~/Library/LaunchAgents", "~/Library/Cookies",
        "/Library/Application Support", "/Library/LaunchAgents", "/Library/LaunchDaemons",
        "/Library/PrivilegedHelperTools", "/Library/Preferences", "/Library/Caches",
    ]

    public static func installedApps(dirs: [String] = ["/Applications", "~/Applications"]) async -> [AppInfo] {
        let urls = dirs.map { URL(fileURLWithPath: expandTilde($0)) }.flatMap { d -> [URL] in
            ((try? FileManager.default.contentsOfDirectory(at: d, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.pathExtension == "app" }
        }
        let cask = Set((try? FileManager.default.contentsOfDirectory(atPath: "/opt/homebrew/Caskroom")) ?? [])
        let apps = await Concurrent.map(urls) { url -> AppInfo? in
            guard let b = Bundle(url: url), let bid = b.bundleIdentifier, !bid.hasPrefix("com.apple.") else { return nil }
            let name = (b.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? (b.object(forInfoDictionaryKey: "CFBundleName") as? String) ?? url.deletingPathExtension().lastPathComponent
            let masReceipt = url.appendingPathComponent("Contents/_MASReceipt").path
            let source: AppInfo.Source = FileManager.default.fileExists(atPath: masReceipt) ? .appStore
                : (cask.contains(url.deletingPathExtension().lastPathComponent.lowercased().replacingOccurrences(of: " ", with: "-")) ? .homebrew : .other)
            let v = Vendor.resolve(appURL: url, bundleID: bid)
            return AppInfo(url: url, name: name, bundleID: bid, size: FileWalker.allocatedSize(of: url),
                           lastUsed: LargeOldFilesFinder.lastUsed(url), source: source, vendor: v.name, vendorKey: v.key)
        }
        return apps.compactMap { $0 }.sorted { $0.size > $1.size }
    }

    /// Tìm leftovers theo bundle ID (an toàn) và theo tên chính xác (cần xem lại).
    public static func leftovers(for app: AppInfo, dirs: [String] = leftoverDirs) -> [ScanItem] {
        let bid = app.bundleID.lowercased()
        let name = app.name.lowercased()
        var items: [ScanItem] = []
        for d in dirs {
            let dir = URL(fileURLWithPath: expandTilde(d))
            for f in (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [] {
                let l = f.lowercased()
                let byBundle = l.contains(bid)
                let byName = !byBundle && (l == name || l == name + ".plist") && d.contains("Application Support")
                guard byBundle || byName else { continue }
                let u = dir.appendingPathComponent(f)
                items.append(ScanItem(url: u, title: f, allocatedSize: FileWalker.allocatedSize(of: u),
                                      category: d.hasPrefix("~") ? "Leftover (user)" : "Leftover (system)",
                                      ruleID: "uninstall-leftover", safety: byBundle ? .safe : .review,
                                      detail: d.hasPrefix("/") ? tr("Cần quyền admin để xóa") : d))
            }
        }
        return items
    }

    /// Tất cả mục cần dọn khi gỡ app: bản thân app + leftovers.
    public static func plan(for app: AppInfo, includeApp: Bool = true) -> [ScanItem] {
        var items = leftovers(for: app)
        if includeApp {
            items.insert(ScanItem(url: app.url, title: app.name + ".app", allocatedSize: app.size, category: tr("Ứng dụng"),
                                  ruleID: "uninstall-app", safety: .safe,
                                  detail: app.source == .homebrew ? tr("Cài qua Homebrew: nên dùng `brew uninstall --cask`") : nil), at: 0)
        }
        return items
    }

    /// Unload launch agent/daemon liên quan trước khi xóa.
    public static func bootout(_ items: [ScanItem]) async {
        let uid = getuid()
        for i in items where i.url.pathExtension == "plist" && i.url.path.contains("/LaunchAgents/") {
            _ = await ProcessRunner.run(["launchctl", "bootout", "gui/\(uid)", i.url.path])
        }
    }
}

public extension Uninstaller {
    /// Gỡ cài đặt thật: thoát app, unload launch agent, xóa vĩnh viễn app + mọi dữ liệu liên quan.
    /// Mục cần quyền admin (ví dụ trong /Library) được thử lại qua hộp thoại mật khẩu của macOS.
    /// Blocklist của SafetyLayer vẫn áp dụng cho mọi đường dẫn.
    static func uninstall(_ items: [ScanItem], app: AppInfo, executor: ActionExecutor) async -> CleanReport {
        let selected = items.filter { $0.selected }

        // 1. Thoát app (nhẹ nhàng trước, ép buộc nếu cần).
        func running() -> [NSRunningApplication] { NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID) }
        running().forEach { $0.terminate() }
        for _ in 0..<30 where !running().isEmpty { try? await Task.sleep(nanoseconds: 100_000_000) }
        running().forEach { $0.forceTerminate() }

        // 2. Dừng launch agent/daemon liên quan trước khi xóa plist.
        await bootout(selected)

        // 3. Xóa vĩnh viễn qua ActionExecutor (blocklist + audit log).
        var report = await executor.execute(selected, mode: .permanent)

        // 4. Mục bị từ chối quyền → thử lại với quyền admin.
        let failed = report.outcomes.filter { if case .failed = $0.status { return true }; return false }
        guard !failed.isEmpty else { return report }
        let blocklist = executor.blocklist
        let paths = failed.map(\.path).filter { blocklist.reason(for: URL(fileURLWithPath: $0)) == nil }
        guard !paths.isEmpty else { return report }
        let quoted = paths.map { "'" + $0.replacingOccurrences(of: "'", with: "'\\''") + "'" }.joined(separator: " ")
        let r = await ProcessRunner.runPrivileged(shell: "/bin/rm -rf -- \(quoted)")
        for p in paths {
            executor.audit.append(AuditRecord(date: Date(), action: "remove", path: p, bytes: 0, ruleID: "uninstall-admin",
                                              mode: "permanent", result: r.ok ? "done (admin)" : "failed: \(r.stderr.prefix(160))"))
        }
        if r.ok {
            let done = Set(paths)
            report.outcomes = report.outcomes.map { o in
                done.contains(o.path) ? CleanOutcome(itemID: o.itemID, path: o.path, bytes: o.bytes, status: .done, note: "admin") : o
            }
        }
        return report
    }
}
