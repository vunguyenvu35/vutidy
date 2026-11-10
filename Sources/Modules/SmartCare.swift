import Foundation
import CoreKit

/// Phần "Smart Care" ngoài dọn dẹp: những thứ Smart Scan chỉ báo cáo để người dùng xem (không tự làm gì).
public struct SmartCareSummary: Sendable {
    /// Cập nhật cho các app cài bằng Homebrew cask.
    public var updates: [OutdatedApp] = []
    /// App lâu không mở (mặc định 90 ngày), chưa tính app của Apple.
    public var unusedApps: [AppInfo] = []
    /// File lớn và cũ trong Downloads (chỉ gợi ý, không chọn sẵn).
    public var clutter: [ScanItem] = []
    /// Mục "mở khi đăng nhập": đang bật, và trong đó bao nhiêu mục không còn file.
    public var loginOn = 0
    public var loginMissing = 0
    public var date = Date()
    public init() {}

    public var unusedBytes: Int64 { unusedApps.reduce(0) { $0 + $1.size } }
    public var clutterBytes: Int64 { clutter.reduce(0) { $0 + $1.allocatedSize } }
}

public enum SmartCare {
    /// Gom song song: cập nhật app, app ít dùng, file lớn và cũ trong Downloads, mục mở khi đăng nhập.
    public static func gather(unusedDays: Int = 90, clutterDays: Int = 90, clutterMinMB: Int64 = 200,
                              progress: @escaping @Sendable (String) -> Void = { _ in }) async -> SmartCareSummary {
        async let updates = Updater.brewOutdated()
        async let apps = Uninstaller.installedApps()
        async let login = LoginItems.list()
        async let clutter: [ScanItem] = Task.detached {
            let downloads = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads")
            return LargeOldFilesFinder(roots: [downloads], minBytes: clutterMinMB * 1_000_000, olderThanDays: clutterDays, limit: 200).find()
        }.value

        var s = SmartCareSummary()
        progress("Applications")
        s.updates = await updates
        let cutoff = Date().addingTimeInterval(-Double(unusedDays) * 86_400)
        s.unusedApps = await apps.filter { a in a.lastUsed.map { $0 < cutoff } ?? false }.sorted { $0.size > $1.size }
        let items = await login
        s.loginOn = items.filter(\.enabled).count
        s.loginMissing = items.filter { $0.enabled && $0.orphaned }.count
        progress("Clutter")
        s.clutter = await clutter.sorted { $0.allocatedSize > $1.allocatedSize }
        s.date = Date()
        return s
    }
}
