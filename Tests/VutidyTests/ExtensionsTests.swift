import Testing
import Foundation
@testable import Modules

@Suite struct ExtensionsTests {
    let sample = """
    +    com.acme.App.FinderSync(1.2)
                Path = /Applications/Acme.app/Contents/PlugIns/FinderSync.appex
                UUID = 605AD29C-FB26-42FB-95A3-D9503E46433C
                 SDK = com.apple.FinderSync
       Parent Bundle = /Applications/Acme.app
        Display Name = Acme Finder Menu
         Parent Name = Acme

    -    com.acme.App.Share(1.2)
                Path = /Applications/Acme.app/Contents/PlugIns/Share.appex
                 SDK = com.apple.share-services
       Parent Bundle = /Applications/Acme.app
        Display Name = Acme Share
         Parent Name = Acme

         com.apple.Notes.QuickLookExtension(4.13)
                Path = /System/Applications/Notes.app/Contents/PlugIns/QL.appex
                 SDK = com.apple.quicklook.preview

         com.other.Safari(2.0)
                Path = /Applications/Other.app/Contents/PlugIns/Web.appex
                 SDK = com.apple.Safari.web-extension
        Display Name = Other for Safari
    """

    @Test func parsesRecordsElectionAndKeys() {
        let r = ExtensionScanner.parsePluginKit(sample)
        #expect(r.map(\.bundleID) == ["com.acme.App.FinderSync", "com.acme.App.Share", "com.apple.Notes.QuickLookExtension", "com.other.Safari"])
        #expect(r[0].election == "+" && r[0].enabled)
        #expect(r[1].election == "-" && !r[1].enabled, "dấu - là người dùng đã tắt")
        #expect(r[2].election == "" && r[2].enabled, "không dấu = mặc định = bật")
        #expect(r[0].displayName == "Acme Finder Menu" && r[0].parentName == "Acme" && r[0].parentPath == "/Applications/Acme.app")
        #expect(r[3].path == "/Applications/Other.app/Contents/PlugIns/Web.appex", "bản ghi cuối không có dòng trống phía sau vẫn được lấy")
    }

    @Test func keepsOnlyThirdPartyAndMapsKinds() {
        let items = ExtensionScanner.appExtensions(from: ExtensionScanner.parsePluginKit(sample))
        #expect(items.map(\.bundleID) == ["com.acme.App.FinderSync", "com.acme.App.Share", "com.other.Safari"], "bỏ phần của Apple/hệ thống")
        #expect(items.map(\.kind) == [.finderSync, .share, .safari])
        #expect(items.map(\.enabled) == [true, false, true])
        #expect(items.allSatisfy { !$0.removable }, "extension trong app không gỡ riêng")
    }

    @Test func scansPluginFilesAndSkipsAppleAndOtherExtensions() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ext-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let dir = root.appendingPathComponent("PreferencePanes")
        for n in ["Acme.prefPane", "readme.txt", ".hidden.prefPane"] {
            try FileManager.default.createDirectory(at: dir.appendingPathComponent(n), withIntermediateDirectories: true)
        }
        let items = ExtensionScanner.plugins(dirs: [(dir.path, .preferencePane, ["prefpane"])])
        #expect(items.map(\.name) == ["Acme"])
        #expect(items[0].kind == .preferencePane && items[0].system, "đường dẫn không bắt đầu bằng ~ coi là hệ thống/cần admin")
        #expect(!items[0].removable)
    }
}
