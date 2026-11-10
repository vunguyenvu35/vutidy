import Foundation
import AppKit
import CoreKit
import ScanEngine
import SafetyLayer

public struct RuleEvaluator: Sendable {
    public let blocklist: Blocklist
    private let runningBundleIDs: @Sendable () -> Set<String>

    public init(blocklist: Blocklist = Blocklist(),
                runningBundleIDs: @escaping @Sendable () -> Set<String> = RuleEvaluator.defaultRunning) {
        self.blocklist = blocklist
        self.runningBundleIDs = runningBundleIDs
    }

    public static let defaultRunning: @Sendable () -> Set<String> = {
        Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier })
    }

    public func scan(_ rules: [Rule], progress: (@Sendable (String) -> Void)? = nil) async -> [ScanItem] {
        let running = runningBundleIDs()
        var items: [ScanItem] = []
        for rule in rules {
            if Task.isCancelled { break }
            progress?(rule.title)
            items += await evaluate(rule, running: running)
        }
        return items
    }

    func evaluate(_ rule: Rule, running: Set<String>) async -> [ScanItem] {
        if let req = rule.requires, ProcessRunner.which(req) == nil { return [] }
        if let pat = rule.skipIfRunningBundle, running.contains(where: { fnmatch(pat, $0, 0) == 0 }) { return [] }

        let excludes = (rule.exclude ?? []).map(expandTilde)
        let now = Date()
        var matches: [URL] = []
        var seen = Set<String>()
        for p in rule.paths {
            for u in Glob.expand(p) where seen.insert(u.path).inserted {
                if excludes.contains(where: { fnmatch($0, u.path, 0) == 0 }) { continue }
                if blocklist.isBlocked(u) { continue }
                if rule.appNotRunning == true, running.contains(u.lastPathComponent) { continue }
                if let days = rule.minAgeDays, days > 0,
                   let m = FileWalker.mtime(of: u), now.timeIntervalSince(m) < Double(days) * 86_400 { continue }
                matches.append(u)
            }
        }
        let sized = await Concurrent.map(matches) { ($0, FileWalker.allocatedSize(of: $0)) }
        return sized.filter { $0.1 > 0 }.map { (url, size) in
            ScanItem(url: url, title: displayName(url, rule: rule), allocatedSize: size,
                     category: tr(rule.group), ruleID: rule.id, safety: rule.safety,
                     command: rule.command, detail: rule.detail.map(tr))
        }
    }

    private func displayName(_ url: URL, rule: Rule) -> String {
        rule.paths.count == 1 && !rule.paths[0].contains("*") ? tr(rule.title) : url.lastPathComponent
    }
}
