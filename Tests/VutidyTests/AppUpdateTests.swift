import Testing
import Foundation
@testable import Modules

@Suite struct AppUpdateTests {
    @Test func versionsCompareNumerically() {
        #expect(AppVersion("0.10.0")! > AppVersion("0.9.9")!)
        #expect(!(AppVersion("v1.0")! < AppVersion("1.0.0")!) && !(AppVersion("1.0.0")! < AppVersion("v1.0")!))
        #expect(AppVersion("1.2.3")! > AppVersion("1.2")!)
        #expect(AppVersion("1.0.0-beta")! < AppVersion("1.0.0")!)
        #expect(AppVersion("not a version") == nil)
        #expect(AppVersion("1.x.0") == nil)
    }

    private func release(_ tag: String, draft: Bool = false, assets: [String] = []) -> [String: Any] {
        ["tag_name": tag, "draft": draft, "prerelease": true, "html_url": "https://example.com/\(tag)", "body": "notes \(tag)",
         "assets": assets.map { ["name": $0, "browser_download_url": "https://example.com/dl/\($0)"] }]
    }
    private func data(_ rs: [[String: Any]]) -> Data { try! JSONSerialization.data(withJSONObject: rs) }

    @Test func picksHighestNonDraftReleaseWithAPackage() throws {
        let json = data([
            release("v0.2.0", assets: ["vutidy-0.2.0-macos.zip", "vutidy-macos.zip", "SHA256SUMS"]),
            release("v0.3.0", draft: true, assets: ["vutidy-0.3.0-macos.zip"]),
            release("v0.4.0", assets: ["vutidy-0.4.0-macos.dmg"]),          // no zip → ignored
            release("v0.1.0", assets: ["vutidy-0.1.0-macos.zip"]),
        ])
        let r = try #require(try UpdateChecker.parse(json))
        #expect(r.tag == "v0.2.0")
        #expect(r.zipName == "vutidy-0.2.0-macos.zip")
        #expect(r.sumsURL != nil)
    }

    @Test func reportsOnlyNewerThanCurrent() throws {
        let json = data([release("v0.2.0", assets: ["vutidy-0.2.0-macos.zip"])])
        #expect(try UpdateChecker.newer(than: AppVersion("0.1.0")!, in: json) != nil)
        #expect(try UpdateChecker.newer(than: AppVersion("0.2.0")!, in: json) == nil)
        #expect(try UpdateChecker.newer(than: AppVersion("0.3.0")!, in: json) == nil)
    }

    @Test func rejectsGarbage() {
        #expect(throws: AppUpdateError.self) { _ = try UpdateChecker.parse(Data("{}".utf8)) }
    }

    @Test func parsesChecksumFileAndVerifies() throws {
        let sums = "\(String(repeating: "a", count: 64))  vutidy-0.2.0-macos.zip\n\(String(repeating: "B", count: 64)) *vutidy-0.2.0-macos.dmg\nnoise\n"
        let m = UpdateVerifier.parseSums(sums)
        #expect(m["vutidy-0.2.0-macos.zip"] == String(repeating: "a", count: 64))
        #expect(m["vutidy-0.2.0-macos.dmg"] == String(repeating: "b", count: 64))

        let f = FileManager.default.temporaryDirectory.appendingPathComponent("upd-\(UUID().uuidString).zip")
        try Data("hello".utf8).write(to: f); defer { try? FileManager.default.removeItem(at: f) }
        let hello = "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"      // sha256("hello")
        try AppInstaller.verify(zip: f, name: "x.zip", sums: "\(hello)  x.zip")
        #expect(throws: AppUpdateError.checksumMismatch) { try AppInstaller.verify(zip: f, name: "x.zip", sums: "\(String(repeating: "0", count: 64))  x.zip") }
        #expect(throws: AppUpdateError.noChecksum) { try AppInstaller.verify(zip: f, name: "x.zip", sums: nil) }
        #expect(throws: AppUpdateError.noChecksum) { try AppInstaller.verify(zip: f, name: "other.zip", sums: "\(hello)  x.zip") }
    }

    @Test func refusesToInstallOutsideAnApplicationsFolder() {
        #expect(throws: AppUpdateError.notInstalledAsApp) { try AppInstaller.checkInstallable(URL(fileURLWithPath: "/tmp/Vutidy")) }
        #expect(throws: AppUpdateError.needsApplicationsFolder) { try AppInstaller.checkInstallable(URL(fileURLWithPath: "/Volumes/Vutidy/Vutidy.app")) }
    }
}
