import Foundation
import CoreServices
import CoreKit
import ScanEngine

public enum FileKind: String, CaseIterable, Sendable {
    case all, archive, video, diskImage, installer
    public var title: String {
        switch self {
        case .all: return tr("Tất cả"); case .archive: return tr("Archive"); case .video: return tr("Video")
        case .diskImage: return tr("Disk image"); case .installer: return tr("Installer")
        }
    }
    static let ext: [FileKind: Set<String>] = [
        .archive: ["zip", "tar", "gz", "tgz", "7z", "rar", "bz2", "xz"],
        .video: ["mp4", "mov", "mkv", "avi", "m4v", "webm"],
        .diskImage: ["dmg", "iso", "img", "sparseimage", "sparsebundle"],
        .installer: ["pkg", "mpkg"],
    ]
    public func matches(_ ext: String) -> Bool {
        self == .all ? true : (Self.ext[self]?.contains(ext.lowercased()) ?? false)
    }
}

public struct LargeOldFilesFinder: Sendable {
    public var roots: [URL]
    public var minBytes: Int64
    public var olderThanDays: Int
    public var kind: FileKind
    public var limit: Int

    public init(roots: [URL] = [URL(fileURLWithPath: NSHomeDirectory())],
                minBytes: Int64 = 100 * 1_000_000, olderThanDays: Int = 0, kind: FileKind = .all, limit: Int = 500) {
        self.roots = roots; self.minBytes = minBytes; self.olderThanDays = olderThanDays; self.kind = kind; self.limit = limit
    }

    /// Ngày dùng cuối: kMDItemLastUsedDate, fallback atime, fallback mtime.
    public static func lastUsed(_ url: URL) -> Date? {
        if let item = MDItemCreateWithURL(nil, url as CFURL),
           let d = MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date { return d }
        return FileWalker.atime(of: url) ?? FileWalker.mtime(of: url)
    }

    public func find() -> [ScanItem] {
        let now = Date()
        var out: [ScanItem] = []
        let skip: Set<String> = ["Library", ".Trash", ".git", "node_modules", ".build"]
        func visit(_ dir: URL, depth: Int) {
            if Task.isCancelled || depth > 12 { return }
            for k in FileWalker.children(of: dir) where !k.isSymlink {
                let name = k.url.lastPathComponent
                if k.isDir {
                    // Bundle (.app, .photoslibrary…) coi như một file.
                    if ["app", "photoslibrary", "sparsebundle", "xcarchive"].contains(k.url.pathExtension) { consider(k.url) }
                    else if !skip.contains(name) { visit(k.url, depth: depth + 1) }
                } else { consider(k.url) }
            }
        }
        func consider(_ url: URL) {
            guard kind.matches(url.pathExtension) else { return }
            let size = FileWalker.allocatedSize(of: url)
            guard size >= minBytes else { return }
            var last: Date?
            if olderThanDays > 0 {
                last = Self.lastUsed(url)
                if let l = last, now.timeIntervalSince(l) < Double(olderThanDays) * 86_400 { return }
            }
            let detail = (last ?? Self.lastUsed(url)).map { trf("Dùng lần cuối: %@", "\($0.formatted(date: .abbreviated, time: .omitted))") }
            out.append(ScanItem(url: url, title: url.lastPathComponent, allocatedSize: size, category: tr("File lớn & cũ"),
                                ruleID: "large-old", safety: .review, selected: false, detail: detail))
        }
        for r in roots { visit(r, depth: 0) }
        return Array(out.sorted { $0.allocatedSize > $1.allocatedSize }.prefix(limit))
    }
}
