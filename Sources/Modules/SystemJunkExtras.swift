import Foundation
import CoreKit
import ScanEngine

/// Preference plist bị hỏng (không parse được). Chỉ liệt kê, mặc định `review`.
public struct BrokenPreferencesModule: CleanerModule {
    public let id = "broken-prefs"
    public let title = tr("Preferences hỏng")
    public let requiresPrivilege = false
    public init() {}

    public func scan(progress: @escaping @Sendable (String) -> Void) async throws -> [ScanItem] {
        progress(tr("Preferences hỏng"))
        let dir = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Preferences")
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "plist" }.compactMap { url in
            guard let data = try? Data(contentsOf: url), !data.isEmpty else {
                // Không đọc được (quyền) hoặc rỗng: file rỗng coi là hỏng.
                let size = FileWalker.allocatedSize(of: url)
                return (try? Data(contentsOf: url)) == nil && FileManager.default.isReadableFile(atPath: url.path) == false
                    ? nil
                    : ScanItem(url: url, title: url.lastPathComponent, allocatedSize: size, category: tr("Preferences hỏng"),
                               ruleID: "broken-prefs", safety: .review, detail: tr("File rỗng"))
            }
            if (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) != nil { return nil }
            return ScanItem(url: url, title: url.lastPathComponent, allocatedSize: FileWalker.allocatedSize(of: url),
                            category: tr("Preferences hỏng"), ruleID: "broken-prefs", safety: .review,
                            detail: tr("Không parse được plist"))
        }
    }
}

/// Thùng rác của user. Dọn = xóa vĩnh viễn (đã ở trong Trash nên là hành vi người dùng mong đợi).
public struct TrashModule: CleanerModule {
    public let id = "trash"
    public let title = tr("Thùng rác")
    public let requiresPrivilege = false
    public init() {}

    /// `~/.Trash` được macOS bảo vệ (TCC): thiếu Full Disk Access thì không liệt kê được và kết quả rỗng
    /// KHÔNG có nghĩa là thùng rác trống. Dùng để báo đúng thay vì hiện "0 KB".
    public static var isBlocked: Bool {
        let path = NSHomeDirectory() + "/.Trash"
        guard FileManager.default.fileExists(atPath: path) else { return false }
        return (try? FileManager.default.contentsOfDirectory(atPath: path)) == nil
    }

    public func scan(progress: @escaping @Sendable (String) -> Void) async throws -> [ScanItem] {
        progress(tr("Thùng rác"))
        var roots = [URL(fileURLWithPath: NSHomeDirectory() + "/.Trash")]
        let uid = getuid()
        for vol in (try? FileManager.default.contentsOfDirectory(atPath: "/Volumes")) ?? [] {
            roots.append(URL(fileURLWithPath: "/Volumes/\(vol)/.Trashes/\(uid)"))
        }
        var items: [ScanItem] = []
        for r in roots {
            let kids = (try? FileManager.default.contentsOfDirectory(at: r, includingPropertiesForKeys: nil)) ?? []
            for k in kids {
                items.append(ScanItem(url: k, title: k.lastPathComponent, allocatedSize: FileWalker.allocatedSize(of: k),
                                      category: r.path.hasPrefix("/Volumes") ? tr("Ổ ngoài") : tr("Thùng rác"),
                                      ruleID: "trash", safety: .safe))
            }
        }
        return items
    }
}
