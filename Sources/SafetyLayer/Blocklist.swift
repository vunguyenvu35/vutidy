import Foundation
import CoreKit

/// Blocklist cứng: các đường dẫn không bao giờ được xóa/di chuyển, bất kể rule nói gì.
public struct Blocklist: Sendable {
    public let home: String
    private let protected: [String]

    public init(home: String = NSHomeDirectory()) {
        let h = Blocklist.normalize(home)
        self.home = h
        var p = [
            "/System", "/bin", "/sbin", "/usr", "/etc", "/private/etc", "/dev", "/cores",
            "/Library/Keychains", "/private/var/db", "/private/var/root", "/var/db",
            "/Library/Apple", "/Library/Extensions",
        ]
        p += [
            "Documents", "Desktop", ".ssh", ".gnupg", "Library/Keychains",
            "Library/Mobile Documents", "Library/Application Support/AddressBook",
            "Library/Messages", "Library/Safari/Bookmarks.plist",
            "Pictures/Photos Library.photoslibrary/originals",
            "Pictures/Photos Library.photoslibrary/database",
        ].map { h + "/" + $0 }
        self.protected = p.map(Blocklist.normalize)
    }

    static func normalize(_ path: String) -> String {
        var s = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
        if s.count > 1 && s.hasSuffix("/") { s.removeLast() }
        return s
    }

    public func isBlocked(_ url: URL) -> Bool { reason(for: url) != nil }

    /// Trả về lý do bị chặn, nil nếu được phép.
    public func reason(for url: URL) -> String? {
        guard url.isFileURL, url.path.hasPrefix("/") else { return tr("không phải đường dẫn tuyệt đối") }
        let path = Blocklist.normalize(url.path)
        if path == "/" { return tr("thư mục gốc") }
        if path == home { return tr("thư mục home") }
        if path == home + "/Library" { return "~/Library" }

        // /usr/local được phép khi rule chỉ rõ bên trong.
        if path.hasPrefix("/usr/local/") { return nil }

        for p in protected {
            if path == p || path.hasPrefix(p + "/") { return trf("nằm trong vùng được bảo vệ (%@)", "\(p)") }
            // Chặn xóa thư mục cha chứa vùng được bảo vệ (ví dụ ~/Pictures chứa Photos originals).
            if p.hasPrefix(path + "/") { return trf("chứa vùng được bảo vệ (%@)", "\(p)") }
        }
        return nil
    }
}
