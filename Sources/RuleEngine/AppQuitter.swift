import Foundation
import AppKit
import CoreKit

/// Một ứng dụng đang chạy cần đóng để dọn cache của nó.
public struct RunningApp: Sendable, Hashable, Identifiable {
    public var id: String { bundleID }
    public let bundleID: String
    public let name: String
    public let url: URL?
}

/// Đóng ứng dụng một cách lịch sự (như Cmd+Q, không kill) trước khi dọn cache của nó, rồi mở lại sau khi dọn xong.
public enum AppQuitter {
    /// Chỉ những app này mới được tự đóng khi dọn cache chung (`appNotRunning`): trình duyệt và app chat/nhạc nặng cache, mở lại là khôi phục.
    /// Mọi app khác đang chạy vẫn bị bỏ qua như trước. IDE (Xcode, JetBrains) cố ý không có ở đây vì có thể đang có việc chưa lưu.
    public static let quittable: Set<String> = [
        "com.google.Chrome", "com.brave.Browser", "com.microsoft.edgemac", "org.mozilla.firefox",
        "company.thebrowser.Browser", "com.apple.Safari", "com.vivaldi.Vivaldi", "com.operasoftware.Opera",
        "com.tinyspeck.slackmacgap", "com.hnc.Discord", "com.spotify.client", "notion.id", "com.microsoft.teams2",
    ]

    /// Các app đang chạy mà các mục này cần đóng (theo `quitBundle`), mỗi app một lần.
    public static func running(for items: [ScanItem]) -> [RunningApp] {
        let patterns = Set(items.compactMap(\.quitBundle))
        guard !patterns.isEmpty else { return [] }
        var seen = Set<String>(), out: [RunningApp] = []
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            guard let bid = app.bundleIdentifier, !seen.contains(bid), !app.isTerminated,
                  patterns.contains(where: { fnmatch($0, bid, 0) == 0 }) else { continue }
            seen.insert(bid)
            out.append(RunningApp(bundleID: bid, name: app.localizedName ?? bid, url: app.bundleURL))
        }
        return out.sorted { $0.name < $1.name }
    }

    /// Mục có cần app này không.
    public static func item(_ item: ScanItem, needs app: RunningApp) -> Bool {
        guard let p = item.quitBundle else { return false }
        return fnmatch(p, app.bundleID, 0) == 0
    }

    /// Yêu cầu các app thoát và chờ tối đa `timeout` giây. App nào không thoát (ví dụ đang hỏi lưu file) nằm trong `refused`; không bao giờ ép buộc.
    public static func quit(_ apps: [RunningApp], timeout: TimeInterval = 12) async -> (quit: [RunningApp], refused: [RunningApp]) {
        func live(_ a: RunningApp) -> [NSRunningApplication] {
            NSRunningApplication.runningApplications(withBundleIdentifier: a.bundleID).filter { !$0.isTerminated }
        }
        for a in apps { live(a).forEach { _ = $0.terminate() } }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline, apps.contains(where: { !live($0).isEmpty }) {
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        return (apps.filter { live($0).isEmpty }, apps.filter { !live($0).isEmpty })
    }

    /// Mở lại ở nền (không giành focus của người dùng).
    public static func relaunch(_ apps: [RunningApp]) async {
        for a in apps {
            guard let url = a.url else { continue }
            let cfg = NSWorkspace.OpenConfiguration()
            cfg.activates = false
            _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: cfg)
        }
    }
}
