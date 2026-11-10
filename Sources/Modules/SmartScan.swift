import Foundation
import CoreKit

public struct SmartScanResult: Sendable {
    public var cleanup: [ScanItem] = []
    public var persistence: [PersistenceItem] = []
    public var launchItems: [LaunchItem] = []
    public var consumers: [Optimization.Consumer] = []
    public var date = Date()
    public init() {}

    public var cleanableBytes: Int64 { cleanup.filter { $0.safety == .safe }.reduce(0) { $0 + $1.allocatedSize } }
    public var reviewBytes: Int64 { cleanup.filter { $0.safety != .safe }.reduce(0) { $0 + $1.allocatedSize } }
    public var suspiciousCount: Int { persistence.filter(\.suspicious).count }
}

public enum SmartScan {
    /// Chạy song song System Junk, Dev Junk, Persistence, Optimization.
    public static func run(modules: [CleanerModule], progress: @escaping @Sendable (String) -> Void) async -> SmartScanResult {
        async let cleanup: [ScanItem] = {
            await withTaskGroup(of: [ScanItem].self) { g in
                for m in modules { g.addTask { (try? await m.scan(progress: progress)) ?? [] } }
                var all: [ScanItem] = []
                for await r in g { all += r }
                return all
            }
        }()
        async let persistence = Task.detached { progress("Persistence"); return PersistenceScanner.scan() }.value
        async let launch = Optimization.launchItems()
        async let consumers = Optimization.heavyConsumers()
        var r = SmartScanResult()
        r.cleanup = await cleanup
        r.persistence = await persistence
        r.launchItems = await launch
        r.consumers = await consumers
        return r
    }
}


import RuleEngine

public enum ModuleRouting {
    /// Xác định item thuộc module dọn dẹp nào dựa trên ruleID (để chia kết quả Smart Scan về từng màn).
    public static func moduleID(forRuleID id: String, rules: [Rule]) -> String {
        if let m = rules.first(where: { $0.id == id })?.module { return m }
        if id == "broken-prefs" { return "system-junk" }
        if id == "trash" { return "trash" }
        return "dev-junk"   // docker-*, jetbrains-orphan-config, stale-project-*
    }
}
