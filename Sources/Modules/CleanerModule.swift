import Foundation
import CoreKit
import SafetyLayer
import RuleEngine

public protocol CleanerModule: Sendable {
    var id: String { get }
    var title: String { get }
    var requiresPrivilege: Bool { get }
    func scan(progress: @escaping @Sendable (String) -> Void) async throws -> [ScanItem]
}

/// Module chạy trên danh sách Rule (YAML→JSON) với bộ đánh giá chung.
public struct RuleBasedModule: CleanerModule {
    public let id: String
    public let title: String
    public let requiresPrivilege = false
    let rules: [Rule]
    let evaluator: RuleEvaluator

    public init(id: String, title: String, rules: [Rule], evaluator: RuleEvaluator = RuleEvaluator()) {
        self.id = id; self.title = title; self.evaluator = evaluator
        self.rules = rules.filter { $0.module == id }
    }

    public func scan(progress: @escaping @Sendable (String) -> Void) async throws -> [ScanItem] {
        await evaluator.scan(rules, progress: progress)
    }
}

public extension ActionExecutor {
    /// Chỉ dọn các mục đã chọn.
    func clean(_ items: [ScanItem], mode: CleanMode,
               progress: (@Sendable (Int, Int) -> Void)? = nil) async -> CleanReport {
        await execute(items.filter { $0.selected }, mode: mode, progress: progress)
    }
}

public enum Cleaners {
    public static func systemJunk(rules: [Rule] = RuleLoader.loadAll()) -> CleanerModule {
        CompositeModule(id: "system-junk", title: tr("Rác hệ thống"), parts: [
            RuleBasedModule(id: "system-junk", title: "", rules: rules),
            BrokenPreferencesModule(),
        ])
    }
    public static func privacy(rules: [Rule] = RuleLoader.loadAll()) -> CleanerModule {
        RuleBasedModule(id: "privacy", title: tr("Quyền riêng tư"), rules: rules)
    }
}

public struct CompositeModule: CleanerModule {
    public let id: String
    public let title: String
    public var requiresPrivilege: Bool { parts.contains { $0.requiresPrivilege } }
    let parts: [CleanerModule]
    public init(id: String, title: String, parts: [CleanerModule]) {
        self.id = id; self.title = title; self.parts = parts
    }
    public func scan(progress: @escaping @Sendable (String) -> Void) async throws -> [ScanItem] {
        var all: [ScanItem] = []
        for p in parts { all += try await p.scan(progress: progress) }
        return all
    }
}
