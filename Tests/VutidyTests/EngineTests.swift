import Testing
import Foundation
@testable import ScanEngine
@testable import RuleEngine
@testable import SafetyLayer
@testable import CoreKit
@testable import Modules

@Suite struct ScanEngineTests {
    @Test func sizeSumsFilesAndDedupesHardLinks() throws {
        let f = Fixture(); defer { f.cleanup() }
        let a = f.file("d/a.bin", bytes: 100_000)
        let single = FileWalker.allocatedSize(of: f.root)
        try FileManager.default.linkItem(at: a, to: f.root.appendingPathComponent("d/hardlink.bin"))
        let withLink = FileWalker.allocatedSize(of: f.root)
        // Hard link không làm tăng allocated size đáng kể (chỉ thêm một entry thư mục).
        #expect(withLink - single < 50_000)
        #expect(single >= 100_000)
    }
    @Test func doesNotFollowSymlinks() throws {
        let f = Fixture(); defer { f.cleanup() }
        let big = f.file("big/x.bin", bytes: 500_000)
        let other = f.dir("other")
        try FileManager.default.createSymbolicLink(at: other.appendingPathComponent("link"), withDestinationURL: big.deletingLastPathComponent())
        #expect(FileWalker.allocatedSize(of: other) < 100_000)
    }
    @Test func globExpandsPatternsAndBraces() {
        let f = Fixture(); defer { f.cleanup() }
        f.file("a/1.txt"); f.file("a/2.txt"); f.file("b/3.log")
        #expect(Glob.expand(f.root.path + "/a/*.txt").count == 2)
        #expect(Glob.expand(f.root.path + "/{a,b}/*").count == 3)
        #expect(Glob.expand(f.root.path + "/nope/*").isEmpty)
    }
    @Test func treeSortsAndAggregates() async {
        let f = Fixture(); defer { f.cleanup() }
        f.file("small/a", bytes: 4096); f.file("large/b", bytes: 400_000)
        for i in 0..<5 { f.file("many/f\(i)", bytes: 4096) }
        let tree = await DirectoryTree.build(root: f.root, maxDepth: 2, maxChildren: 3)
        #expect(tree.children.first?.name == "large")
        let many = tree.children.first { $0.name == "many" }
        #expect(many?.children.contains { $0.isAggregate } == true)
        #expect(tree.size >= 400_000)
    }
}

@Suite struct RuleEngineTests {
    func rule(_ id: String, paths: [String], exclude: [String]? = nil, age: Int? = nil, safety: SafetyLevel = .safe) -> Rule {
        Rule(id: id, module: "t", title: id, group: "G", paths: paths, exclude: exclude, minAgeDays: age,
             skipIfRunningBundle: nil, appNotRunning: nil, safety: safety, command: nil, requires: nil, detail: nil)
    }
    func evaluator(_ f: Fixture, running: Set<String> = []) -> RuleEvaluator {
        RuleEvaluator(blocklist: Blocklist(home: f.root.path + "/home"), runningBundleIDs: { running })
    }

    @Test func bundledRulesDecode() {
        let rules = RuleLoader.loadBundled()
        #expect(rules.count > 20)
        #expect(Set(rules.map(\.id)).count == rules.count, "id rule phải duy nhất")
        #expect(rules.contains { $0.module == "dev-junk" })
    }
    @Test func scansMatchesAndSkipsEmptyAndExcluded() async {
        let f = Fixture(); defer { f.cleanup() }
        f.file("c/keep.app/x", bytes: 20_000); f.file("c/com.apple.foo/x", bytes: 20_000); _ = f.dir("c/empty")
        let items = await evaluator(f).scan([rule("r", paths: [f.root.path + "/c/*"], exclude: [f.root.path + "/c/com.apple.*"])])
        #expect(items.map { $0.url.lastPathComponent } == ["keep.app"])
    }
    @Test func safetyDefaultsSelection() async {
        let f = Fixture(); defer { f.cleanup() }
        f.file("a/x"); f.file("b/x")
        let ev = evaluator(f)
        let safe = await ev.scan([rule("s", paths: [f.root.path + "/a"], safety: .safe)])
        let review = await ev.scan([rule("r", paths: [f.root.path + "/b"], safety: .review)])
        #expect(safe[0].selected == true)
        #expect(review[0].selected == false)
    }
    @Test func minAgeFiltersRecentFiles() async throws {
        let f = Fixture(); defer { f.cleanup() }
        let old = f.file("l/old.log"), _ = f.file("l/new.log")
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-30 * 86_400)], ofItemAtPath: old.path)
        let items = await evaluator(f).scan([rule("r", paths: [f.root.path + "/l/*"], age: 7)])
        #expect(items.map { $0.url.lastPathComponent } == ["old.log"])
    }
    @Test func appNotRunningSkipsRunningBundleCache() async {
        let f = Fixture(); defer { f.cleanup() }
        f.file("c/com.running.app/x"); f.file("c/com.idle.app/x")
        var r = rule("r", paths: [f.root.path + "/c/*"]); r.appNotRunning = true
        let items = await evaluator(f, running: ["com.running.app"]).scan([r])
        #expect(items.map { $0.url.lastPathComponent } == ["com.idle.app"])
    }
    @Test func skipIfRunningBundleSkipsWholeRule() async {
        let f = Fixture(); defer { f.cleanup() }
        f.file("c/x")
        var r = rule("r", paths: [f.root.path + "/c"]); r.skipIfRunningBundle = "com.jetbrains.*"
        #expect(await evaluator(f, running: ["com.jetbrains.intellij"]).scan([r]).isEmpty)
        #expect(await evaluator(f).scan([r]).count == 1)
    }
    @Test func blockedMatchesNeverSurface() async {
        let f = Fixture(); defer { f.cleanup() }
        f.file("home/Documents/secret.txt")
        let items = await evaluator(f).scan([rule("r", paths: [f.root.path + "/home/Documents"])])
        #expect(items.isEmpty)
    }
    @Test func requiresMissingCommandDisablesRule() async {
        let f = Fixture(); defer { f.cleanup() }
        f.file("c/x")
        var r = rule("r", paths: [f.root.path + "/c"]); r.requires = "definitely-not-installed-xyz"
        #expect(await evaluator(f).scan([r]).isEmpty)
    }
}

@Suite struct ModuleLogicTests {
    @Test func dockerSizeParsing() {
        #expect(DockerDetector.parseSize("1.5GB") == 1_500_000_000)
        #expect(DockerDetector.parseSize("512MB") == 512_000_000)
        #expect(DockerDetector.parseSize("3.5kB") == 3_500)
        #expect(DockerDetector.parseSize("0B") == 0)
        #expect(DockerDetector.parseSize("garbage") == 0)
    }
    @Test func dockerDfParsing() {
        let out = """
        {"Type":"Images","TotalCount":"5","Active":"1","Size":"2GB","Reclaimable":"1.2GB (60%)"}
        {"Type":"Build Cache","TotalCount":"9","Active":"0","Size":"700MB","Reclaimable":"700MB"}
        """
        let r = DockerDetector.parse(out)
        #expect(r.count == 2)
        #expect(r[0].type == "Images" && r[0].bytes == 1_200_000_000)
        #expect(r[1].bytes == 700_000_000)
    }
    @Test func jetbrainsKeepsNewestPerIDE() {
        let old = JetBrainsOrphans.olderVersions(in: ["IntelliJIdea2023.3", "IntelliJIdea2024.1", "IntelliJIdea2024.2", "GoLand2024.1", "PyCharm2023.3", "PyCharm2023.10", "random"])
        #expect(Set(old) == ["IntelliJIdea2023.3", "IntelliJIdea2024.1", "PyCharm2023.3"])
    }
    @Test func staleProjectDetection() async throws {
        let f = Fixture(); defer { f.cleanup() }
        f.file("old/package.json", bytes: 10); f.file("old/node_modules/dep/index.js", bytes: 50_000)
        f.file("fresh/package.json", bytes: 10); f.file("fresh/node_modules/dep/index.js", bytes: 50_000)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-90 * 86_400)],
                                              ofItemAtPath: f.root.appendingPathComponent("old/package.json").path)
        let items = await ProjectArtifacts.scan(roots: [f.root], staleDays: 60)
        #expect(items.count == 1)
        #expect(items[0].url.path.contains("/old/node_modules"))
        #expect(items[0].safety == .review && !items[0].selected)
    }
    @Test func duplicateFinderGroupsByContent() async {
        let f = Fixture(); defer { f.cleanup() }
        f.file("a/x.bin", bytes: 20_000, fill: 1); f.file("b/y.bin", bytes: 20_000, fill: 1)
        f.file("c/z.bin", bytes: 20_000, fill: 2)                 // cùng size, khác nội dung
        f.file("d/w.bin", bytes: 20_000, fill: 3)
        let groups = await DuplicateFinder(roots: [f.root]).find()
        #expect(groups.count == 1)
        #expect(groups[0].files.count == 2)
        #expect(groups[0].wasted == 20_000)
        let items = DuplicateFinder.items(from: groups)
        #expect(items.count == 1 && items[0].selected == false)
    }
    @Test func duplicateDetectsDifferenceInMiddle() async {
        // Partial hash trùng (đầu/cuối giống) nhưng ruột khác — full hash phải tách ra.
        let f = Fixture(); defer { f.cleanup() }
        var a = Data(repeating: 7, count: 50_000), b = a
        b[25_000] = 9
        try! FileManager.default.createDirectory(at: f.root.appendingPathComponent("x"), withIntermediateDirectories: true)
        try! a.write(to: f.root.appendingPathComponent("x/a")); try! b.write(to: f.root.appendingPathComponent("x/b"))
        a = Data()
        #expect(await DuplicateFinder(roots: [f.root]).find().isEmpty)
    }
    @Test func largeOldFinderFiltersBySizeAndKind() {
        let f = Fixture(); defer { f.cleanup() }
        f.file("Downloads/big.dmg", bytes: 300_000); f.file("Downloads/big.zip", bytes: 300_000); f.file("Downloads/tiny.dmg", bytes: 1000)
        let all = LargeOldFilesFinder(roots: [f.root], minBytes: 100_000).find()
        #expect(all.count == 2)
        let dmg = LargeOldFilesFinder(roots: [f.root], minBytes: 100_000, kind: .diskImage).find()
        #expect(dmg.map { $0.title } == ["big.dmg"])
        #expect(dmg.allSatisfy { !$0.selected })
    }
    @Test func uninstallerLeftoversByBundleID() {
        let f = Fixture(); defer { f.cleanup() }
        f.file("Caches/com.acme.tool/x"); f.file("Preferences/com.acme.tool.plist"); f.file("Caches/com.other.app/x")
        f.file("Application Support/Acme Tool/x")
        let app = AppInfo(url: f.root.appendingPathComponent("Acme Tool.app"), name: "Acme Tool", bundleID: "com.acme.tool", size: 1, lastUsed: nil, source: .other)
        let items = Uninstaller.leftovers(for: app, dirs: [f.root.path + "/Caches", f.root.path + "/Preferences", f.root.path + "/Application Support"])
        let names = Set(items.map(\.title))
        #expect(names.contains("com.acme.tool") && names.contains("com.acme.tool.plist"))
        #expect(!names.contains("com.other.app"))
    }
    @Test func recommendationsRespectThresholdsAndLimit() {
        var ctx = SystemContext(disk: DiskInfo(total: 1000, available: 50, availableImportant: 60))
        ctx.devJunkSafeBytes = 8_000_000_000; ctx.outdatedApps = 3; ctx.lastDeepScan = Date()
        let cards = RecommendationEngine().cards(for: ctx)
        #expect(cards.first?.id == "disk-low")
        #expect(cards.count <= 5)
        #expect(cards.map(\.priority) == cards.map(\.priority).sorted(by: >))
        var healthy = SystemContext(disk: DiskInfo(total: 1000, available: 600, availableImportant: 600)); healthy.lastDeepScan = Date()
        #expect(RecommendationEngine().cards(for: healthy).isEmpty)
    }
    @Test func dismissHidesUntilWorse() {
        let d = UserDefaults(suiteName: "vutidy-test-\(UUID().uuidString)")!
        let store = DismissStore(defaults: d)
        let r = Recommendation(id: "x", priority: 1, icon: "", title: "", actionTitle: "", action: .openCleanup, severity: 10)
        store.dismiss(r)
        #expect(store.isHidden(r))
        let worse = Recommendation(id: "x", priority: 1, icon: "", title: "", actionTitle: "", action: .openCleanup, severity: 20)
        #expect(!store.isHidden(worse))
    }
    @Test func systemMonitorReturnsSaneValues() {
        let s = SystemMonitor().sample()
        #expect(s.disk.total > 0 && s.memory.total > 0)
        #expect(s.cpuLoad >= 0 && s.cpuLoad <= 1)
    }
}
