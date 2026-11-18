import Testing
import Foundation
@testable import Modules

@Suite struct ClamAVTests {
    @Test func parsesVersion() {
        #expect(ClamAV.parseVersion("ClamAV 1.5.4/27812/Tue Nov 18 07:25:28 2026\n") == "1.5.4")
        #expect(ClamAV.parseVersion("ClamAV 1.5.4\n") == "1.5.4")
        #expect(ClamAV.parseVersion("command not found") == nil)
    }

    @Test func parsesFoundLinesAndIgnoresEverythingElse() {
        let out = """
        /Users/me/Downloads/eicar.com: Win.Test.EICAR_HDB-1 FOUND
        /Users/me/Downloads/a: b.dmg: Osx.Trojan.Agent-1234 FOUND
        /Users/me/Downloads/ok.txt: OK
        LibClamAV Warning: something
        relative/path: Foo FOUND
        /Users/me/x: FOUND
        """
        let f = ClamAV.parseFound(out)
        #expect(f.map(\.path) == ["/Users/me/Downloads/eicar.com", "/Users/me/Downloads/a: b.dmg"], "đường dẫn có \": \" vẫn tách đúng từ bên phải; bỏ dòng OK, cảnh báo, đường dẫn tương đối và dòng thiếu tên chữ ký")
        #expect(f.map(\.signature) == ["Win.Test.EICAR_HDB-1", "Osx.Trojan.Agent-1234"])
    }

    @Test func scanCommandUsesOwnDatabaseAndOnlyExistingFolders() {
        let db = URL(fileURLWithPath: "/tmp/vutidy-clam")
        let args = ClamAV.scanArguments(database: db, targets: ["/Applications", "/nope/missing", "/Library/LaunchDaemons"], exists: { $0 != "/nope/missing" })
        #expect(args.first == "clamscan" && args.contains("-r") && args.contains("--infected"))
        #expect(args.contains("--database=/tmp/vutidy-clam"), "dùng cơ sở dữ liệu riêng, không đụng cấu hình hệ thống của ClamAV")
        #expect(args.contains("--max-filesize=100M") && args.contains("--cross-fs=no"))
        #expect(args.suffix(2) == ["/Applications", "/Library/LaunchDaemons"])
    }

    @Test func findingsCanBeQuarantinedAndKeepASignatureKey() {
        let f = ClamAV.findings([("/Users/me/Downloads/eicar.com", "Win.Test.EICAR_HDB-1")])
        #expect(f.count == 1 && f[0].severity == .high && f[0].code == "clamav" && f[0].source == .file)
        #expect(f[0].canQuarantine && f[0].path == "/Users/me/Downloads/eicar.com", "dùng chung luồng Cách ly như mọi phát hiện khác")
        #expect(f[0].key.contains("Win.Test.EICAR_HDB-1") || f[0].key.contains("eicar"), "khóa riêng để Bỏ qua và nhận biết mục mới")
    }

    @Test func scanTargetsAvoidPrivateDocuments() {
        #expect(!ClamAV.scanTargets.contains { $0.contains("Documents") })
        #expect(ClamAV.scanTargets.contains("~/Downloads") && ClamAV.scanTargets.contains("/Library/LaunchDaemons"))
    }
}
