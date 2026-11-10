import Foundation
import CoreKit

public enum RecommendationAction: Sendable, Hashable {
    case openCleanup, openSpaceLens, openDevJunk, openUpdater, openUninstaller, openOptimization, openBattery, runDeepScan, thinSnapshots
}

public struct Recommendation: Identifiable, Sendable, Hashable {
    public let id: String
    public let priority: Int
    public let icon: String
    public let title: String
    public let actionTitle: String
    public let action: RecommendationAction
    /// Mức độ nghiêm trọng khi đề xuất — dùng để hiện lại thẻ đã ẩn nếu xấu đi đáng kể.
    public let severity: Double
}

public struct SystemContext: Sendable {
    public var disk: DiskInfo
    public var battery: BatteryInfo?
    public var memory: MemoryInfo?
    public var devJunkSafeBytes: Int64 = 0
    public var outdatedApps: Int = 0
    public var unusedApps: Int = 0
    public var loginItems: Int = 0
    public var lastDeepScan: Date?
    public init(disk: DiskInfo, battery: BatteryInfo? = nil) { self.disk = disk; self.battery = battery }
}

public struct RecommendationThresholds: Codable, Sendable {
    public var purgeableBytes: Int64 = 5_000_000_000
    public var diskFreeFraction: Double = 0.10
    public var deepScanDays: Int = 7
    public var devJunkBytes: Int64 = 5_000_000_000
    public var loginItems: Int = 15
    public var batteryHealth: Double = 0.80
    public var memoryAvailableFraction: Double = 0.10
    public var swapBytes: Int64 = 8_000_000_000
    public var maxCards: Int = 5
    public init() {}
}

public protocol RecommendationProvider: Sendable {
    func evaluate(_ c: SystemContext, _ t: RecommendationThresholds) -> [Recommendation]
}

public struct DefaultRecommendations: RecommendationProvider {
    public init() {}
    public func evaluate(_ c: SystemContext, _ t: RecommendationThresholds) -> [Recommendation] {
        var r: [Recommendation] = []
        if c.disk.purgeable > t.purgeableBytes {
            r.append(.init(id: "purgeable", priority: 90, icon: "internaldrive", title: trf("Giải phóng %@ dung lượng purgeable.", "\(ByteFormat.string(c.disk.purgeable))"),
                           actionTitle: tr("Dọn snapshot"), action: .thinSnapshots, severity: Double(c.disk.purgeable)))
        }
        if c.disk.total > 0, c.disk.freeFraction < t.diskFreeFraction {
            r.append(.init(id: "disk-low", priority: 100, icon: "exclamationmark.triangle", title: trf("Ổ đĩa còn dưới %@%% trống.", "\(Int(t.diskFreeFraction * 100))"),
                           actionTitle: tr("Mở Space Lens"), action: .openSpaceLens, severity: 1 - c.disk.freeFraction))
        }
        if let m = c.memory, m.total > 0 {
            let lowFree = Double(m.available) / Double(m.total) < t.memoryAvailableFraction
            if m.pressure != .normal || lowFree || m.swapUsed > t.swapBytes {
                r.append(.init(id: "memory-pressure", priority: m.pressure == .critical ? 95 : 85, icon: "memorychip",
                               title: trf("Bộ nhớ đang chịu áp lực (%@) · swap %@.", m.pressure.rawValue, ByteFormat.string(m.swapUsed)),
                               actionTitle: tr("Mở Tối ưu"), action: .openOptimization,
                               severity: Double(m.swapUsed) + (m.pressure == .critical ? 1e10 : m.pressure == .warning ? 1e9 : 0)))
            }
        }
        if c.lastDeepScan == nil || Date().timeIntervalSince(c.lastDeepScan!) > Double(t.deepScanDays) * 86_400 {
            r.append(.init(id: "deep-scan", priority: 60, icon: "shield", title: trf("Chưa quét persistence trong %@ ngày.", "\(t.deepScanDays)"),
                           actionTitle: tr("Quét ngay"), action: .runDeepScan, severity: 1))
        }
        if c.devJunkSafeBytes > t.devJunkBytes {
            r.append(.init(id: "dev-junk", priority: 80, icon: "hammer", title: trf("Dev Junk có thể dọn: %@.", "\(ByteFormat.string(c.devJunkSafeBytes))"),
                           actionTitle: tr("Mở Dev Junk"), action: .openDevJunk, severity: Double(c.devJunkSafeBytes)))
        }
        if c.outdatedApps > 0 {
            r.append(.init(id: "updates", priority: 70, icon: "arrow.down.circle", title: trf("%@ ứng dụng có bản cập nhật.", "\(c.outdatedApps)"),
                           actionTitle: tr("Mở Cập nhật"), action: .openUpdater, severity: Double(c.outdatedApps)))
        }
        if c.unusedApps > 0 {
            r.append(.init(id: "unused-apps", priority: 40, icon: "trash", title: trf("%@ ứng dụng chưa mở trong 90 ngày.", "\(c.unusedApps)"),
                           actionTitle: tr("Mở Gỡ ứng dụng"), action: .openUninstaller, severity: Double(c.unusedApps)))
        }
        if c.loginItems > t.loginItems {
            r.append(.init(id: "login-items", priority: 50, icon: "bolt", title: trf("%@ mục khởi động cùng máy.", "\(c.loginItems)"),
                           actionTitle: tr("Mở Tối ưu"), action: .openOptimization, severity: Double(c.loginItems)))
        }
        if let h = c.battery?.health, h < t.batteryHealth {
            r.append(.init(id: "battery-health", priority: 55, icon: "battery.25", title: trf("Sức khỏe pin %@%%.", "\(Int(h * 100))"),
                           actionTitle: "Xem pin", action: .openBattery, severity: 1 - h))
        }
        return r
    }
}

/// Lưu trạng thái ẩn thẻ theo id. Thẻ hiện lại nếu hết hạn hoặc mức độ xấu đi ≥ 50%.
public final class DismissStore: @unchecked Sendable {
    struct Entry: Codable { var until: Date; var severity: Double }
    private let defaults: UserDefaults
    private let key = "vutidy.dismissed"
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    private func load() -> [String: Entry] {
        guard let d = defaults.data(forKey: key) else { return [:] }
        return (try? JSONDecoder().decode([String: Entry].self, from: d)) ?? [:]
    }
    public func dismiss(_ r: Recommendation, days: Int = 7, now: Date = Date()) {
        var m = load()
        m[r.id] = Entry(until: now.addingTimeInterval(Double(days) * 86_400), severity: r.severity)
        defaults.set(try? JSONEncoder().encode(m), forKey: key)
    }
    public func isHidden(_ r: Recommendation, now: Date = Date()) -> Bool {
        guard let e = load()[r.id], e.until > now else { return false }
        return r.severity < e.severity * 1.5
    }
}

public struct RecommendationEngine: Sendable {
    public var providers: [RecommendationProvider]
    public var thresholds: RecommendationThresholds
    public init(providers: [RecommendationProvider] = [DefaultRecommendations()], thresholds: RecommendationThresholds = .init()) {
        self.providers = providers; self.thresholds = thresholds
    }
    public func cards(for c: SystemContext, dismissed: DismissStore? = nil) -> [Recommendation] {
        let all = providers.flatMap { $0.evaluate(c, thresholds) }
        return Array(all.filter { !(dismissed?.isHidden($0) ?? false) }.sorted { $0.priority > $1.priority }.prefix(thresholds.maxCards))
    }
}
