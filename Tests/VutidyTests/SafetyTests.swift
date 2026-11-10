import Testing
import Foundation
@testable import SafetyLayer
@testable import CoreKit
@testable import Modules

@Suite struct BlocklistTests {
    let home = "/Users/tester"
    var b: Blocklist { Blocklist(home: home) }

    @Test func blocksSystemPaths() {
        for p in ["/System", "/System/Library/Foo", "/bin/ls", "/sbin", "/usr/bin/env", "/usr", "/etc/hosts", "/", "/Library/Keychains/x"] {
            #expect(b.isBlocked(URL(fileURLWithPath: p)), "\(p) phải bị chặn")
        }
    }
    @Test func blocksUserData() {
        for p in ["Documents", "Documents/a.txt", "Desktop/x", ".ssh", ".ssh/id_rsa", ".gnupg", "Library/Keychains/login.keychain-db",
                  "Pictures/Photos Library.photoslibrary/originals/1.heic"] {
            #expect(b.isBlocked(URL(fileURLWithPath: "\(home)/\(p)")), "\(p) phải bị chặn")
        }
    }
    @Test func blocksAncestorsOfProtected() {
        #expect(b.isBlocked(URL(fileURLWithPath: home)))
        #expect(b.isBlocked(URL(fileURLWithPath: "\(home)/Library")))
        #expect(b.isBlocked(URL(fileURLWithPath: "\(home)/Pictures")))
        #expect(b.isBlocked(URL(fileURLWithPath: "/Library")))
    }
    @Test func allowsCachesAndUsrLocal() {
        #expect(!b.isBlocked(URL(fileURLWithPath: "\(home)/Library/Caches/com.foo.bar")))
        #expect(!b.isBlocked(URL(fileURLWithPath: "\(home)/.npm/_cacache")))
        #expect(!b.isBlocked(URL(fileURLWithPath: "/Library/Caches/foo")))
        #expect(!b.isBlocked(URL(fileURLWithPath: "/usr/local/lib/foo")))
        #expect(!b.isBlocked(URL(fileURLWithPath: "/Applications/Foo.app")))
    }
    @Test func blocksTraversalAndSymlinkEscape() throws {
        // `..` phải được chuẩn hóa trước khi so khớp.
        #expect(b.isBlocked(URL(fileURLWithPath: "\(home)/Library/Caches/../../Documents")))
        // Symlink trỏ vào vùng bảo vệ phải bị chặn.
        let f = Fixture(); defer { f.cleanup() }
        let link = f.root.appendingPathComponent("evil")
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "/System")
        #expect(Blocklist(home: f.root.path).isBlocked(link))
    }
    @Test func rejectsRelativePaths() {
        #expect(b.isBlocked(URL(string: "relative/path")!))
    }
}

@Suite struct QuarantineTests {
    @Test func addRestoreRoundTrip() async throws {
        let f = Fixture(); defer { f.cleanup() }
        let src = f.file("data/a.bin", bytes: 4096)
        try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: src.path)
        let q = Quarantine(root: f.dir("q"))
        let e = try await q.add(src, ruleID: "t", bytes: 4096)
        #expect(!FileManager.default.fileExists(atPath: src.path))
        #expect(await q.entries().count == 1)
        let restored = try await q.restore(e.id)
        #expect(restored.path == src.path)
        let perm = try FileManager.default.attributesOfItem(atPath: src.path)[.posixPermissions] as? Int
        #expect(perm == 0o640)
        #expect(await q.entries().isEmpty)
    }
    @Test func restoreRefusesToOverwrite() async throws {
        let f = Fixture(); defer { f.cleanup() }
        let src = f.file("a.txt")
        let q = Quarantine(root: f.dir("q"))
        let e = try await q.add(src, ruleID: "t", bytes: 1)
        f.file("a.txt", bytes: 5)   // đường dẫn gốc đã có file mới
        await #expect(throws: QuarantineError.self) { try await q.restore(e.id) }
    }
    @Test func indexPersistsAcrossInstances() async throws {
        let f = Fixture(); defer { f.cleanup() }
        let root = f.dir("q")
        let q1 = Quarantine(root: root)
        _ = try await q1.add(f.file("a.txt"), ruleID: "t", bytes: 10)
        let q2 = Quarantine(root: root)
        #expect(await q2.entries().count == 1)
    }
    @Test func purgesExpired() async throws {
        let f = Fixture(); defer { f.cleanup() }
        let q = Quarantine(root: f.dir("q"), retentionDays: 7)
        let old = Date().addingTimeInterval(-8 * 86_400)
        _ = try await q.add(f.file("old.txt"), ruleID: "t", bytes: 1, now: old)
        _ = try await q.add(f.file("new.txt"), ruleID: "t", bytes: 1)
        #expect(await q.purgeExpired() == 1)
        #expect(await q.entries().count == 1)
    }
}

@Suite struct ExecutorTests {
    func make(_ f: Fixture) -> ActionExecutor {
        ActionExecutor(blocklist: Blocklist(home: f.root.path + "/home"),
                       quarantine: Quarantine(root: f.dir("q")), audit: AuditLog(url: f.root.appendingPathComponent("audit.log")))
    }
    func item(_ u: URL, size: Int64 = 100, safety: SafetyLevel = .safe) -> ScanItem {
        ScanItem(url: u, title: u.lastPathComponent, allocatedSize: size, category: "t", ruleID: "r", safety: safety)
    }

    @Test func dryRunTouchesNothing() async {
        let f = Fixture(); defer { f.cleanup() }
        let u = f.file("x.txt")
        let r = await make(f).execute([item(u)], mode: .dryRun)
        #expect(FileManager.default.fileExists(atPath: u.path))
        #expect(r.outcomes.first?.status == .dryRun)
    }
    @Test func quarantineMovesFile() async {
        let f = Fixture(); defer { f.cleanup() }
        let u = f.file("x.txt")
        let ex = make(f)
        let r = await ex.execute([item(u)], mode: .quarantine)
        #expect(!FileManager.default.fileExists(atPath: u.path))
        #expect(r.doneCount == 1)
        #expect(await ex.quarantine.entries().count == 1)
    }
    @Test func blockedItemIsSkippedEvenIfSelected() async {
        let f = Fixture(); defer { f.cleanup() }
        let docs = f.file("home/Documents/keep.txt")
        let r = await make(f).execute([item(docs)], mode: .permanent)
        #expect(FileManager.default.fileExists(atPath: docs.path))
        #expect(r.skipped.count == 1)
    }
    @Test func missingFileIsSkipped() async {
        let f = Fixture(); defer { f.cleanup() }
        let r = await make(f).execute([item(f.root.appendingPathComponent("nope"))], mode: .quarantine)
        #expect(r.skipped.count == 1)
    }
    @Test func permanentRemoves() async {
        let f = Fixture(); defer { f.cleanup() }
        let u = f.file("x.txt")
        _ = await make(f).execute([item(u)], mode: .permanent)
        #expect(!FileManager.default.fileExists(atPath: u.path))
    }
    @Test func commandItemsRunOnlyOutsideDryRun() async {
        let f = Fixture(); defer { f.cleanup() }
        let marker = f.root.appendingPathComponent("marker")
        var it = item(f.root)
        it.command = ["/usr/bin/touch", marker.path]
        let ex = make(f)
        _ = await ex.execute([it], mode: .dryRun)
        #expect(!FileManager.default.fileExists(atPath: marker.path))
        _ = await ex.execute([it], mode: .quarantine)
        #expect(FileManager.default.fileExists(atPath: marker.path))
    }
    @Test func writesAuditLog() async {
        let f = Fixture(); defer { f.cleanup() }
        let ex = make(f)
        _ = await ex.execute([item(f.file("x.txt"))], mode: .quarantine)
        let log = ex.audit.recent()
        #expect(log.count == 1)
        #expect(log[0].mode == "quarantine" && log[0].result == "done")
    }
    @Test func cleanOnlyProcessesSelected() async {
        let f = Fixture(); defer { f.cleanup() }
        let a = f.file("a.txt"), b = f.file("b.txt")
        var ia = item(a), ib = item(b)
        ia.selected = true; ib.selected = false
        _ = await make(f).clean([ia, ib], mode: .quarantine)
        #expect(!FileManager.default.fileExists(atPath: a.path))
        #expect(FileManager.default.fileExists(atPath: b.path))
    }
}
