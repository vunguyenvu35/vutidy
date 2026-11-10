import Testing
import Foundation
@testable import Modules

@Suite struct VendorTests {
    @Test func prettyStripsCompanySuffixes() {
        #expect(Vendor.pretty("JetBrains s.r.o.") == "JetBrains")
        #expect(Vendor.pretty("Google LLC") == "Google")
        #expect(Vendor.pretty("Microsoft Corporation") == "Microsoft")
        #expect(Vendor.pretty("Brave Software, Inc.") == "Brave")
        #expect(Vendor.pretty("OpenAI, L.L.C.") == "OpenAI")
        #expect(Vendor.pretty("Telegram FZ-LLC") == "Telegram")
        #expect(Vendor.pretty("Docker Inc") == "Docker")
    }

    @Test func prettyFixesShoutingCaseButKeepsAcronyms() {
        #expect(Vendor.pretty("KINGSOFT OFFICE SOFTWARE CO., LTD") == "Kingsoft Office")
        #expect(Vendor.pretty("SLACK TECHNOLOGIES, LLC") == "Slack")
        #expect(Vendor.pretty("VNG ONLINE CO., LTD") == "VNG Online")
        #expect(Vendor.pretty("OpenAI OpCo, L.L.C.") == "OpenAI")
        #expect(Vendor.pretty("Kaspersky Lab Switzerland GmbH") == "Kaspersky Lab")
        #expect(Vendor.pretty("IBM") == "IBM")
    }

    @Test func prettyNeverReturnsEmpty() {
        // chỉ có hậu tố → giữ nguyên thay vì trả về chuỗi rỗng
        #expect(!Vendor.pretty("Software").isEmpty)
        #expect(Vendor.pretty("Acme") == "Acme")
    }

    @Test func bundleIDFallback() {
        #expect(Vendor.fromBundleID("com.jetbrains.intellij") == "JetBrains")
        #expect(Vendor.fromBundleID("com.google.Chrome") == "Google")
        #expect(Vendor.fromBundleID("com.microsoft.VSCode") == "Microsoft")
        #expect(Vendor.fromBundleID("com.tinyspeck.slackmacgap") == "Slack")
        #expect(Vendor.fromBundleID("ru.keepcoder.Telegram") == "Telegram")
        #expect(Vendor.fromBundleID("org.foo.Bar") == "Foo")
        #expect(Vendor.fromBundleID("Standalone") == "Standalone")
        #expect(Vendor.fromBundleID("") == "")
    }

    @Test func sameVendorFromDifferentSourcesGetsTheSameKey() {
        // chữ ký ("Google LLC") và bundle ID ("com.google.antigravity") phải gom về cùng một nhóm
        #expect(Vendor.norm(Vendor.pretty("Google LLC")) == Vendor.norm(Vendor.fromBundleID("com.google.antigravity")))
        #expect(Vendor.norm(Vendor.pretty("JetBrains s.r.o.")) == Vendor.norm(Vendor.fromBundleID("com.jetbrains.datagrip")))
    }

    @Test func resolvesRealSignedAppByItsCertificate() throws {
        // Safari của hệ thống do Apple ký; chỉ cần chắc rằng gọi API chữ ký không làm hỏng và luôn trả về một tên.
        let safari = URL(fileURLWithPath: "/System/Cryptexes/App/System/Applications/Safari.app")
        guard FileManager.default.fileExists(atPath: safari.path) else { return }
        let v = Vendor.resolve(appURL: safari, bundleID: "com.apple.Safari")
        #expect(!v.name.isEmpty)
    }
}
