import Foundation
import Security
import CoreKit

/// Xác định nhà sản xuất của một ứng dụng để gom nhóm trong Uninstaller.
/// Ưu tiên tên tổ chức trong chứng chỉ ký mã (đáng tin hơn bundle ID), rồi mới đến bundle ID.
public enum Vendor {
    /// Hậu tố pháp lý/chung chung bị bỏ khi rút gọn tên công ty: "JetBrains s.r.o." → "JetBrains".
    static let suffixes: Set<String> = [
        "inc", "incorporated", "llc", "ltd", "limited", "corp", "corporation", "co", "company", "gmbh", "srl", "sro",
        "bv", "sa", "ag", "ab", "oy", "plc", "kg", "sarl", "jsc", "ooo", "pte", "pty", "fzllc", "fze", "fzco",
        "technologies", "technology", "software", "opco", "international", "switzerland", "usa", "holdings", "group",
    ]

    /// Tên riêng khi suy ra từ bundle ID (phần tên miền ngược không phải lúc nào cũng là tên thương hiệu).
    static let aliases: [String: String] = [
        "jetbrains": "JetBrains", "google": "Google", "microsoft": "Microsoft", "docker": "Docker", "kingsoft": "Kingsoft",
        "tinyspeck": "Slack", "openai": "OpenAI", "anthropic": "Anthropic", "postmanlabs": "Postman", "keepcoder": "Telegram",
        "mozilla": "Mozilla", "spotify": "Spotify", "vng": "VNG", "brave": "Brave", "adobe": "Adobe", "github": "GitHub",
        "zoom": "Zoom", "dropbox": "Dropbox", "figma": "Figma", "notion": "Notion", "valve": "Valve", "videolan": "VideoLAN",
    ]

    static let tlds: Set<String> = ["com", "org", "net", "io", "app", "co", "dev", "ai", "me", "ru", "vn", "de", "fr", "jp", "cn", "us", "uk", "eu", "tv"]

    static func norm(_ s: String) -> String { s.lowercased().filter { $0.isLetter || $0.isNumber } }

    /// "Google LLC" → "Google", "JetBrains s.r.o." → "JetBrains", "Brave Software, Inc." → "Brave".
    static func pretty(_ org: String) -> String {
        var tokens = org.replacingOccurrences(of: ",", with: " ").split(separator: " ").map(String.init)
        while tokens.count > 1, let last = tokens.last, suffixes.contains(norm(last)) { tokens.removeLast() }
        // Chữ ký hay viết HOA toàn bộ ("KINGSOFT OFFICE", "SLACK"): chuyển thành "Kingsoft Office", "Slack".
        // Từ viết tắt ngắn (VNG, IBM, AWS) giữ nguyên.
        tokens = tokens.map { t in
            t.count > 4 && t == t.uppercased() && t.contains(where: \.isLetter) ? t.prefix(1) + t.dropFirst().lowercased() : t
        }
        return tokens.joined(separator: " ")
    }

    /// "com.jetbrains.intellij" → "JetBrains"; "ru.keepcoder.Telegram" → "Telegram"; không đoán được → "".
    static func fromBundleID(_ bundleID: String) -> String {
        let parts = bundleID.split(separator: ".").map(String.init)
        guard !parts.isEmpty else { return "" }
        let raw = (parts.count >= 2 && tlds.contains(parts[0].lowercased())) ? parts[1] : parts[0]
        if let a = aliases[raw.lowercased()] { return a }
        return raw.prefix(1).uppercased() + raw.dropFirst()
    }

    /// Tên tổ chức trong chứng chỉ ký, ví dụ "Developer ID Application: JetBrains s.r.o. (ZVJHPTHV9T)" → "JetBrains s.r.o.".
    /// App Store ký bằng "Apple Mac OS Application Signing" (không có tên nhà phát triển) nên trả về nil.
    static func signingOrganization(_ appURL: URL) -> String? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(appURL as CFURL, [], &code) == errSecSuccess, let code else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let d = info as? [String: Any],
              let certs = d[kSecCodeInfoCertificates as String] as? [SecCertificate], let leaf = certs.first,
              let summary = SecCertificateCopySubjectSummary(leaf) as String?,
              let r = summary.range(of: ": ") else { return nil }
        var org = String(summary[r.upperBound...])
        if let team = org.range(of: #"\s*\([A-Z0-9]{10}\)\s*$"#, options: .regularExpression) { org.removeSubrange(team) }
        org = org.trimmingCharacters(in: .whitespaces)
        return org.isEmpty ? nil : org
    }

    /// (tên hiển thị, khoá gom nhóm). Hai ứng dụng cùng khoá nằm chung một nhóm.
    public static func resolve(appURL: URL, bundleID: String) -> (name: String, key: String) {
        if let org = signingOrganization(appURL) {
            let n = pretty(org)
            if !norm(n).isEmpty { return (n, norm(n)) }
        }
        let n = fromBundleID(bundleID)
        return n.isEmpty ? (tr("Khác"), "") : (n, norm(n))
    }
}
