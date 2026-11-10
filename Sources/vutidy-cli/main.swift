import Foundation
import CoreKit
import SafetyLayer
import ScanEngine
import RuleEngine
import Modules

let usage = """
Vutidy CLI
  vutidy-cli scan <system|dev|trash|privacy|all> [--projects DIR,DIR]
  vutidy-cli clean <system|dev|trash|privacy> [--mode dry|trash|quarantine] [--include-review] [--projects DIR]
  vutidy-cli space <path>
  vutidy-cli duplicates <path>
  vutidy-cli large <path> [--min-mb N] [--days N]
  vutidy-cli quarantine <list|restore ID|purge-expired>
  vutidy-cli audit
Mặc định `clean` chạy dry-run. Chỉ mục an toàn được chọn, trừ khi có --include-review.
"""

func fail(_ m: String) -> Never { FileHandle.standardError.write(Data((m + "\n").utf8)); exit(1) }

var args = Array(CommandLine.arguments.dropFirst())
func flag(_ n: String) -> String? {
    guard let i = args.firstIndex(of: n), i + 1 < args.count else { return nil }
    return args[i + 1]
}
let hasReview = args.contains("--include-review")
let projects = (flag("--projects") ?? "").split(separator: ",").map { URL(fileURLWithPath: expandTilde(String($0))) }

func modules(_ name: String) -> [CleanerModule] {
    let rules = RuleLoader.loadAll()
    switch name {
    case "system": return [Cleaners.systemJunk(rules: rules)]
    case "dev": return [DevJunkModule(rules: rules, projectRoots: projects)]
    case "trash": return [TrashModule()]
    case "privacy": return [Cleaners.privacy(rules: rules)]
    case "all": return [Cleaners.systemJunk(rules: rules), DevJunkModule(rules: rules, projectRoots: projects), TrashModule()]
    default: fail("module không hợp lệ: \(name)\n\(usage)")
    }
}

func scan(_ name: String) async -> [ScanItem] {
    var all: [ScanItem] = []
    for m in modules(name) { all += (try? await m.scan(progress: { _ in })) ?? [] }
    return all
}

func printItems(_ items: [ScanItem]) {
    for (cat, group) in Dictionary(grouping: items, by: \.category).sorted(by: { $0.value.reduce(0) { $0 + $1.allocatedSize } > $1.value.reduce(0) { $0 + $1.allocatedSize } }) {
        print("\n\(cat)  —  \(ByteFormat.string(group.reduce(0) { $0 + $1.allocatedSize }))")
        for i in group.sorted(by: { $0.allocatedSize > $1.allocatedSize }) {
            let tag = i.safety == .safe ? "an toàn" : "xem lại"
            print("  [\(i.selected ? "x" : " ")] \(ByteFormat.string(i.allocatedSize).padding(toLength: 10, withPad: " ", startingAt: 0)) \(tag.padding(toLength: 8, withPad: " ", startingAt: 0)) \(i.isCLI ? "$ " + i.command!.joined(separator: " ") : i.url.path)")
        }
    }
    let safe = items.filter { $0.safety == .safe }.reduce(0) { $0 + $1.allocatedSize }
    print("\nCó thể dọn an toàn: \(ByteFormat.string(safe)) · cần xem lại: \(ByteFormat.string(items.filter { $0.safety != .safe }.reduce(0) { $0 + $1.allocatedSize }))")
}

guard let cmd = args.first else { print(usage); exit(0) }
args.removeFirst()
let executor = ActionExecutor()

switch cmd {
case "scan":
    printItems(await scan(args.first ?? "all"))
case "clean":
    guard let name = args.first else { fail(usage) }
    let mode: CleanMode = ["trash": .moveToTrash, "quarantine": .quarantine][flag("--mode") ?? ""] ?? .dryRun
    var items = await scan(name)
    if hasReview { for i in items.indices { items[i].selected = true } }
    let report = await executor.clean(items, mode: mode)
    for o in report.outcomes { print("\(o.status) \(ByteFormat.string(o.bytes)) \(o.note ?? o.path)") }
    print("\n\(mode == .dryRun ? "[dry-run] " : "")\(ByteFormat.string(report.reclaimedBytes)) · \(report.doneCount) mục · \(report.failures.count) lỗi · \(report.skipped.count) bỏ qua")
case "space":
    let root = URL(fileURLWithPath: expandTilde(args.first ?? "~"))
    let t = await DirectoryTree.build(root: root, maxDepth: 1)
    print("\(root.path): \(ByteFormat.string(t.size))")
    for c in t.children.prefix(25) { print("  \(ByteFormat.string(c.size).padding(toLength: 10, withPad: " ", startingAt: 0)) \(c.name)") }
case "duplicates":
    let groups = await DuplicateFinder(roots: [URL(fileURLWithPath: expandTilde(args.first ?? "~/Downloads"))]).find()
    for g in groups.prefix(30) { print("\(ByteFormat.string(g.wasted)) lãng phí (\(g.files.count) bản)"); g.files.forEach { print("   \($0.path)") } }
    print("Tổng lãng phí: \(ByteFormat.string(groups.reduce(0) { $0 + $1.wasted }))")
case "large":
    let f = LargeOldFilesFinder(roots: [URL(fileURLWithPath: expandTilde(args.first ?? "~/Downloads"))],
                                minBytes: Int64(Double(flag("--min-mb") ?? "100")! * 1_000_000), olderThanDays: Int(flag("--days") ?? "0")!)
    printItems(f.find())
case "quarantine":
    switch args.first {
    case "list", nil:
        let es = await executor.quarantine.entries()
        for e in es { print("\(e.id) \(ByteFormat.string(e.bytes)) còn \(e.daysLeft(retentionDays: 7)) ngày  \(e.originalPath)") }
        print("Tổng: \(ByteFormat.string(await executor.quarantine.totalBytes()))")
    case "restore":
        guard args.count > 1, let id = UUID(uuidString: args[1]) else { fail("thiếu ID") }
        do { print("Đã khôi phục: \(try await executor.quarantine.restore(id).path)") } catch { fail("\(error.localizedDescription)") }
    case "purge-expired": print("Đã xóa \(await executor.quarantine.purgeExpired()) mục quá hạn")
    default: fail(usage)
    }
case "audit":
    for r in executor.audit.recent(limit: 50) { print("\(r.date) \(r.mode) \(r.result) \(r.path)") }
case "malware":
    let t0 = Date()
    let r = await MalwareCheck.run(progress: { print("… \($0)") })
    for c in r.posture { print("[\(c.ok == true ? "OK " : (c.ok == false ? "BAD" : "?  "))] \(c.title): \(c.detail)") }
    for f in r.findings { print("[\(["HIGH", "MED ", "LOW "][f.severity.rawValue])] \(f.title) — \(f.detail) \(f.path ?? "")") }
    print("apps: \(r.appsChecked) · launch items: \(r.launchItemsChecked) · findings: \(r.findings.count) · \(String(format: "%.1f", Date().timeIntervalSince(t0)))s")
default: print(usage)
}
