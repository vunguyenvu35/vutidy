import Foundation
import CoreKit

public final class DirNode: Identifiable, @unchecked Sendable {
    public var id: String { url.path }
    public let url: URL
    public let name: String
    public var size: Int64
    public let isDir: Bool
    public var children: [DirNode]
    /// Nút gộp "…khác" (không drill-down được).
    public let isAggregate: Bool
    /// Thời điểm tạo file/thư mục. Đọc lười (chỉ khi giao diện cần) để không làm chậm lúc quét.
    public lazy var created: Date? = isAggregate ? nil : (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate

    public init(url: URL, name: String? = nil, size: Int64, isDir: Bool,
                children: [DirNode] = [], isAggregate: Bool = false) {
        self.url = url
        self.name = name ?? url.lastPathComponent
        self.size = size
        self.isDir = isDir
        self.children = children
        self.isAggregate = isAggregate
    }
}

public enum DirectoryTree {
    /// Dựng cây với kích thước đầy đủ nhưng chỉ giữ `maxDepth` cấp con. Mỗi thư mục giữ tối đa
    /// `maxChildren` nút lớn nhất, phần còn lại gộp vào một nút "…khác".
    /// Hai cấp đầu được quét song song; `progress` (tuỳ chọn) nhận số file/dung lượng đã quét để hiển thị tiến độ.
    public static func build(root: URL, maxDepth: Int = 3, maxChildren: Int = 60, progress: ScanProgress? = nil) async -> DirNode {
        await nodeAsync(url: root, isDir: true, depth: 0, maxDepth: maxDepth, maxChildren: maxChildren, rootDev: devOf(root), progress: progress)
    }

    private static func devOf(_ url: URL) -> dev_t {
        var st = stat()
        return lstat(url.path, &st) == 0 ? st.st_dev : 0
    }

    private static func nodeAsync(url: URL, isDir: Bool, depth: Int, maxDepth: Int, maxChildren: Int,
                                  rootDev: dev_t, progress: ScanProgress?) async -> DirNode {
        if Task.isCancelled { return DirNode(url: url, size: 0, isDir: isDir) }
        if !isDir {
            let s = FileWalker.allocatedSize(of: url)
            progress?.add(files: 1, bytes: s)
            return DirNode(url: url, size: s, isDir: false)
        }
        if depth > 0 && rootDev != 0 && devOf(url) != rootDev { return DirNode(url: url, size: 0, isDir: true) }
        if depth >= maxDepth {
            return DirNode(url: url, size: FileWalker.metrics(of: url, progress: progress).bytes, isDir: true)
        }
        progress?.setCurrent(url.path)
        let kids = FileWalker.children(of: url)
        var nodes: [DirNode] = []
        if depth <= 1 {
            // Quét song song hai cấp đầu — phần lớn thời gian nằm ở các thư mục lớn như Library, Users…
            nodes = await withTaskGroup(of: DirNode.self) { group in
                for k in kids {
                    group.addTask {
                        await nodeAsync(url: k.url, isDir: k.isDir && !k.isSymlink, depth: depth + 1, maxDepth: maxDepth,
                                        maxChildren: maxChildren, rootDev: rootDev, progress: progress)
                    }
                }
                var r: [DirNode] = []
                for await n in group { r.append(n) }
                return r
            }
        } else {
            for k in kids {
                if Task.isCancelled { break }
                nodes.append(buildSync(url: k.url, isDir: k.isDir && !k.isSymlink, depth: depth + 1, maxDepth: maxDepth,
                                       maxChildren: maxChildren, rootDev: rootDev, progress: progress))
            }
        }
        let total = nodes.reduce(Int64(0)) { $0 + $1.size }
        return DirNode(url: url, size: total, isDir: true, children: trim(nodes, maxChildren: maxChildren, parent: url))
    }

    static func buildSync(url: URL, isDir: Bool, depth: Int, maxDepth: Int, maxChildren: Int, rootDev: dev_t,
                          progress: ScanProgress? = nil) -> DirNode {
        if !isDir {
            let s = FileWalker.allocatedSize(of: url)
            progress?.add(files: 1, bytes: s)
            return DirNode(url: url, size: s, isDir: false)
        }
        if devOf(url) != rootDev && rootDev != 0 { return DirNode(url: url, size: 0, isDir: true) }
        if depth >= maxDepth {
            return DirNode(url: url, size: FileWalker.metrics(of: url, progress: progress).bytes, isDir: true)
        }
        var nodes: [DirNode] = []
        for k in FileWalker.children(of: url) {
            if Task.isCancelled { break }
            nodes.append(buildSync(url: k.url, isDir: k.isDir && !k.isSymlink, depth: depth + 1, maxDepth: maxDepth,
                                   maxChildren: maxChildren, rootDev: rootDev, progress: progress))
        }
        let total = nodes.reduce(Int64(0)) { $0 + $1.size }
        return DirNode(url: url, size: total, isDir: true, children: trim(nodes, maxChildren: maxChildren, parent: url))
    }

    static func trim(_ nodes: [DirNode], maxChildren: Int, parent: URL) -> [DirNode] {
        let sorted = nodes.sorted { $0.size > $1.size }
        guard sorted.count > maxChildren else { return sorted }
        let head = Array(sorted.prefix(maxChildren))
        let rest = sorted.dropFirst(maxChildren)
        let agg = DirNode(url: parent.appendingPathComponent("…khác"), name: trf("…%@ mục khác", "\(rest.count)"),
                          size: rest.reduce(0) { $0 + $1.size }, isDir: false, isAggregate: true)
        return head + [agg]
    }
}
