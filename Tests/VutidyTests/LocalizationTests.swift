import Testing
import Foundation
@testable import CoreKit

@Suite struct LocalizationTests {
    func placeholders(_ s: String) -> Int { s.components(separatedBy: "%@").count - 1 }

    @Test func everyKeyIsTranslatedInAllLanguages() {
        let keys = L10n.allKeys
        #expect(keys.count > 250)
        for lang in [Language.ja, .zh] {
            let t = L10n.table(lang)
            let missing = keys.filter { t[$0] == nil || t[$0]!.isEmpty }
            #expect(missing.isEmpty, "\(lang) thiếu: \(missing.sorted().prefix(5))")
            #expect(t.keys.allSatisfy { keys.contains($0) }, "\(lang) có khóa thừa")
        }
    }

    /// Mọi chuỗi tiếng Việt truyền vào tr()/trf() trong mã nguồn phải có bản dịch: thiếu thì người dùng thấy tiếng Việt dù đã chọn English
    /// (từng xảy ra với hộp Giới thiệu). Chuỗi có nội suy `\(…)` bị bỏ qua vì không phải khóa bảng.
    @Test func everyTrKeyUsedInSourcesHasATranslation() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources")
        let pattern = try NSRegularExpression(pattern: #"\btrf?\(\s*"((?:[^"\\]|\\.)*)""#)
        let accents = try NSRegularExpression(pattern: "[À-ỹ]")
        let keys = L10n.allKeys
        var missing: [String] = []
        let en = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        while let u = en?.nextObject() as? URL {
            guard u.pathExtension == "swift", !u.path.contains("/Localization/"), let text = try? String(contentsOf: u, encoding: .utf8) else { continue }
            let ns = text as NSString
            for m in pattern.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                // Khóa trong bảng là chuỗi đã giải mã; trong mã nguồn còn dạng literal (\n, \", \\).
                let key = ns.substring(with: m.range(at: 1))
                    .replacingOccurrences(of: "\\n", with: "\n").replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "\\\\", with: "\\")
                guard !key.contains("\\("), accents.firstMatch(in: key, range: NSRange(location: 0, length: (key as NSString).length)) != nil else { continue }
                if !keys.contains(key) { missing.append("\(u.lastPathComponent): \(key.prefix(70))") }
            }
        }
        #expect(missing.isEmpty, "thiếu bản dịch: \(missing.prefix(5))")
    }

    @Test func placeholderCountsMatchKey() {
        for lang in [Language.en, .ja, .zh] {
            for (k, v) in L10n.table(lang) {
                #expect(placeholders(k) == placeholders(v), "\(lang): '\(k)' ↔ '\(v)'")
                #expect(k.components(separatedBy: "%%").count == v.components(separatedBy: "%%").count, "\(lang): %% không khớp ở '\(k)'")
            }
        }
    }

    @Test func translateFallbacks() {
        #expect(L10n.translate("Hủy", to: .vi) == "Hủy")
        #expect(L10n.translate("Hủy", to: .en) == "Cancel")
        #expect(L10n.translate("Hủy", to: .ja) == "キャンセル")
        #expect(L10n.translate("Hủy", to: .zh) == "取消")
        #expect(L10n.translate("khóa chưa có bản dịch", to: .ja) == "khóa chưa có bản dịch")
    }

    @Test func formattedStringsKeepArguments() {
        L10n.preference = .ja
        defer { L10n.preference = .system }
        #expect(trf("Đã xóa %@", "2 GB") == "2 GB を削除しました")
        #expect(trf("Ổ đĩa còn dưới %@%% trống.", "10") == "ディスクの空きが 10% 未満です。")
        L10n.preference = .zh
        #expect(trf("%@ / %@ mục", "3", "9") == "3 / 9 项")
    }

    @Test func systemLanguageResolution() {
        #expect(L10n.systemLanguage(preferred: ["ja-JP", "en-US"]) == .ja)
        #expect(L10n.systemLanguage(preferred: ["zh-Hans-CN"]) == .zh)
        #expect(L10n.systemLanguage(preferred: ["zh-Hant-TW"]) == .zh)
        #expect(L10n.systemLanguage(preferred: ["vi-VN"]) == .vi)
        #expect(L10n.systemLanguage(preferred: ["fr-FR"]) == .en)   // không hỗ trợ → English
        #expect(L10n.systemLanguage(preferred: []) == .en)
    }
}

/// Từ điển Swift crash lúc chạy nếu literal có khóa trùng → đọc file nguồn và đảm bảo không trùng.
@Suite struct LocalizationSourceTests {
    @Test func translationFilesHaveNoDuplicateKeys() throws {
        let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/CoreKit/Localization")
        for name in ["English", "Japanese", "Chinese"] {
            let text = try String(contentsOf: dir.appendingPathComponent("\(name).swift"), encoding: .utf8)
            var seen = Set<String>(), dups: [String] = []
            for line in text.split(separator: "\n") {
                let t = line.trimmingCharacters(in: .whitespaces)
                guard t.hasPrefix("\""), let r = t.range(of: "\": \"") else { continue }
                let key = String(t[t.index(after: t.startIndex)..<r.lowerBound])
                if !seen.insert(key).inserted { dups.append(key) }
            }
            #expect(dups.isEmpty, "\(name) có khóa trùng: \(dups.prefix(5))")
        }
    }
}
