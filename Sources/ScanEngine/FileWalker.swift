import Foundation
import Darwin

struct InodeKey: Hashable { let dev: dev_t; let ino: ino_t }

/// Duyệt cây thư mục bằng lstat/readdir. Tính allocated size (st_blocks), dedupe hard link,
/// không đi theo symlink, không băng qua mount point khác.
public enum FileWalker {
    public struct Metrics: Sendable {
        public var bytes: Int64 = 0
        public var files: Int = 0
        var pendingFiles = 0
        var pendingBytes: Int64 = 0
    }

    public static func metrics(of url: URL, crossDevices: Bool = false, progress: ScanProgress? = nil) -> Metrics {
        var seen = Set<InodeKey>()
        var m = Metrics()
        var st = stat()
        guard lstat(url.path, &st) == 0 else { return m }
        walk(path: url.path, st: st, rootDev: st.st_dev, crossDevices: crossDevices, seen: &seen, m: &m, progress: progress)
        if let progress, m.pendingFiles > 0 { progress.add(files: m.pendingFiles, bytes: m.pendingBytes) }
        return m
    }

    public static func allocatedSize(of url: URL) -> Int64 { metrics(of: url).bytes }

    private static func walk(path: String, st: stat, rootDev: dev_t, crossDevices: Bool,
                             seen: inout Set<InodeKey>, m: inout Metrics, progress: ScanProgress? = nil) {
        let isDir = (st.st_mode & S_IFMT) == S_IFDIR
        if !isDir {
            // Hard link: chỉ tính một lần.
            if st.st_nlink > 1 {
                let k = InodeKey(dev: st.st_dev, ino: st.st_ino)
                if !seen.insert(k).inserted { return }
            }
            let size = Int64(st.st_blocks) * 512
            m.bytes += size
            m.files += 1
            if let progress {
                m.pendingFiles += 1; m.pendingBytes += size
                if m.pendingFiles >= 256 { progress.add(files: m.pendingFiles, bytes: m.pendingBytes); m.pendingFiles = 0; m.pendingBytes = 0 }
            }
            return
        }
        m.bytes += Int64(st.st_blocks) * 512
        if Task.isCancelled { return }
        progress?.setCurrent(path)
        guard let dir = opendir(path) else { return }
        defer { closedir(dir) }
        while let ent = readdir(dir) {
            let name = withUnsafePointer(to: &ent.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(NAME_MAX) + 1) { String(cString: $0) }
            }
            if name == "." || name == ".." { continue }
            let child = path == "/" ? "/" + name : path + "/" + name
            var cst = stat()
            guard lstat(child, &cst) == 0 else { continue }
            if (cst.st_mode & S_IFMT) == S_IFDIR && !crossDevices && cst.st_dev != rootDev { continue }
            walk(path: child, st: cst, rootDev: rootDev, crossDevices: crossDevices, seen: &seen, m: &m, progress: progress)
        }
    }

    /// Liệt kê con trực tiếp (tên, stat) của một thư mục.
    public static func children(of url: URL) -> [(url: URL, isDir: Bool, isSymlink: Bool)] {
        guard let dir = opendir(url.path) else { return [] }
        defer { closedir(dir) }
        var out: [(URL, Bool, Bool)] = []
        while let ent = readdir(dir) {
            let name = withUnsafePointer(to: &ent.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(NAME_MAX) + 1) { String(cString: $0) }
            }
            if name == "." || name == ".." { continue }
            let child = url.appendingPathComponent(name)
            var st = stat()
            guard lstat(child.path, &st) == 0 else { continue }
            let t = st.st_mode & S_IFMT
            out.append((child, t == S_IFDIR, t == S_IFLNK))
        }
        return out
    }

    public static func mtime(of url: URL) -> Date? {
        var st = stat()
        guard lstat(url.path, &st) == 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(st.st_mtimespec.tv_sec))
    }

    public static func atime(of url: URL) -> Date? {
        var st = stat()
        guard lstat(url.path, &st) == 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(st.st_atimespec.tv_sec))
    }
}
