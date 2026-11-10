import Foundation
import CryptoKit
import CoreKit
import ScanEngine

public struct DuplicateGroup: Identifiable, Sendable {
    public let id = UUID()
    public let size: Int64
    public var files: [URL]
    /// Dung lượng lấy lại được nếu chỉ giữ một bản.
    public var wasted: Int64 { size * Int64(files.count - 1) }
}

public struct DuplicateFinder: Sendable {
    public var roots: [URL]
    public var minBytes: Int64

    public init(roots: [URL], minBytes: Int64 = 1024) { self.roots = roots; self.minBytes = minBytes }

    public func find(progress: (@Sendable (String) -> Void)? = nil) async -> [DuplicateGroup] {
        // 1. nhóm theo size
        progress?(tr("Gom theo kích thước"))
        var bySize: [Int64: [URL]] = [:]
        var seenInodes = Set<String>()
        let skip: Set<String> = ["Library", ".Trash", ".git", "node_modules", ".build"]
        func visit(_ dir: URL) {
            if Task.isCancelled { return }
            for k in FileWalker.children(of: dir) where !k.isSymlink {
                if k.isDir {
                    if ["app", "photoslibrary", "sparsebundle"].contains(k.url.pathExtension) { continue }
                    if !skip.contains(k.url.lastPathComponent) { visit(k.url) }
                    continue
                }
                var st = stat()
                guard lstat(k.url.path, &st) == 0, st.st_size >= minBytes else { continue }
                // Hard link cùng inode không phải bản trùng thật.
                if !seenInodes.insert("\(st.st_dev):\(st.st_ino)").inserted { continue }
                bySize[Int64(st.st_size), default: []].append(k.url)
            }
        }
        for r in roots { visit(r) }
        let candidates = bySize.filter { $0.value.count > 1 }

        // 2. partial hash (4KB đầu + 4KB cuối)  3. full hash
        var groups: [DuplicateGroup] = []
        for (size, urls) in candidates {
            if Task.isCancelled { break }
            progress?(trf("So sánh %@ file %@", "\(urls.count)", "\(ByteFormat.string(size))"))
            let partial = await group(urls) { Self.partialHash($0, size: size) }
            for p in partial where p.count > 1 {
                let full = await group(p) { Self.fullHash($0) }
                for f in full where f.count > 1 { groups.append(DuplicateGroup(size: size, files: f.sorted { $0.path < $1.path })) }
            }
        }
        return groups.sorted { $0.wasted > $1.wasted }
    }

    private func group(_ urls: [URL], key: @escaping @Sendable (URL) -> String?) async -> [[URL]] {
        let keyed = await Concurrent.map(urls) { ($0, key($0)) }
        var d: [String: [URL]] = [:]
        for (u, k) in keyed { if let k { d[k, default: []].append(u) } }
        return Array(d.values)
    }

    static func partialHash(_ url: URL, size: Int64) -> String? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        var hasher = SHA256()
        guard let head = try? h.read(upToCount: 4096) else { return nil }
        hasher.update(data: head)
        if size > 8192 {
            try? h.seek(toOffset: UInt64(size - 4096))
            if let tail = try? h.read(upToCount: 4096) { hasher.update(data: tail) }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func fullHash(_ url: URL) -> String? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        var hasher = SHA256()
        while let chunk = try? h.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Chuyển nhóm thành ScanItem: giữ bản đầu tiên (theo path), đánh dấu phần còn lại.
    public static func items(from groups: [DuplicateGroup], keep: (DuplicateGroup) -> URL? = { $0.files.first }) -> [ScanItem] {
        groups.flatMap { g -> [ScanItem] in
            let keeper = keep(g)
            return g.files.filter { $0 != keeper }.map {
                ScanItem(url: $0, title: $0.lastPathComponent, allocatedSize: g.size, category: trf("Trùng: %@", "\(g.files[0].lastPathComponent)"),
                         ruleID: "duplicate", safety: .review, selected: false, detail: trf("Bản gốc: %@", "\(keeper?.path ?? "")"))
            }
        }
    }
}
