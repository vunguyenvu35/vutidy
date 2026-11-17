import Testing
import Foundation
import CoreKit
import SafetyLayer
@testable import RuleEngine

@Suite struct QuitAppsTests {
    func evaluator(_ f: Fixture, running: Set<String>) -> RuleEvaluator {
        RuleEvaluator(blocklist: Blocklist(home: f.root.path + "/home"), runningBundleIDs: { running })
    }
    func rule(paths: [String], appNotRunning: Bool? = nil, quitBundle: String? = nil) -> Rule {
        Rule(id: "r", module: "t", title: "r", group: "G", paths: paths, exclude: nil, minAgeDays: nil, skipIfRunningBundle: nil,
             appNotRunning: appNotRunning, quitBundle: quitBundle, safety: .safe, command: nil, requires: nil, detail: nil)
    }

    @Test func runningRuleAppIsTaggedForQuit() async {
        let f = Fixture(); defer { f.cleanup() }
        f.file("cache/x", bytes: 20_000)
        let r = rule(paths: [f.root.path + "/cache"], quitBundle: "com.google.Chrome")
        let running = await evaluator(f, running: ["com.google.Chrome"]).scan([r])
        #expect(running.first?.quitBundle == "com.google.Chrome")
        // App không chạy thì không cần đóng gì.
        let idle = await evaluator(f, running: ["com.other"]).scan([r])
        #expect(idle.count == 1 && idle.first?.quitBundle == nil)
    }

    @Test func genericCacheQuitsOnlyAllowlistedApps() async {
        let f = Fixture(); defer { f.cleanup() }
        f.file("c/com.google.Chrome/x", bytes: 20_000)
        f.file("c/com.example.Editor/x", bytes: 20_000)
        f.file("c/com.idle.App/x", bytes: 20_000)
        let r = rule(paths: [f.root.path + "/c/*"], appNotRunning: true)
        let items = await evaluator(f, running: ["com.google.Chrome", "com.example.Editor"]).scan([r])
        let byName = Dictionary(uniqueKeysWithValues: items.map { ($0.url.lastPathComponent, $0.quitBundle) })
        #expect(byName["com.google.Chrome"] == "com.google.Chrome")   // trong danh sách: đóng rồi dọn
        #expect(byName["com.example.Editor"] == nil && !byName.keys.contains("com.example.Editor"))   // ngoài danh sách: bỏ qua như trước
        #expect(byName.keys.contains("com.idle.App") && byName["com.idle.App"] == nil as String?)   // không chạy: dọn bình thường
    }

    @Test func ideAreNeverQuittable() {
        for bid in ["com.apple.dt.Xcode", "com.jetbrains.intellij", "com.microsoft.VSCode"] {
            #expect(!AppQuitter.quittable.contains(bid), "\(bid) có thể đang có việc chưa lưu")
        }
    }

    @Test func itemMatchingUsesGlob() {
        let app = RunningApp(bundleID: "com.google.Chrome", name: "Chrome", url: nil)
        let item = ScanItem(url: URL(fileURLWithPath: "/x"), title: "x", allocatedSize: 1, category: "c", ruleID: "r", safety: .safe, quitBundle: "com.google.*")
        let other = ScanItem(url: URL(fileURLWithPath: "/y"), title: "y", allocatedSize: 1, category: "c", ruleID: "r", safety: .safe)
        #expect(AppQuitter.item(item, needs: app))
        #expect(!AppQuitter.item(other, needs: app))
    }

    @Test func noItemsNeedNoApps() {
        let plain = ScanItem(url: URL(fileURLWithPath: "/y"), title: "y", allocatedSize: 1, category: "c", ruleID: "r", safety: .safe)
        #expect(AppQuitter.running(for: [plain]).isEmpty)
        #expect(AppQuitter.running(for: []).isEmpty)
    }

    @Test func bundledBrowserRulesCarryQuitBundle() {
        let rules = Dictionary(uniqueKeysWithValues: RuleLoader.loadBundled().map { ($0.id, $0) })
        #expect(rules["chrome-cache"]?.quitBundle == "com.google.Chrome")
        #expect(rules["brave-cache"]?.quitBundle == "com.brave.Browser")
        #expect(rules["edge-cache"]?.quitBundle == "com.microsoft.edgemac")
    }
}
