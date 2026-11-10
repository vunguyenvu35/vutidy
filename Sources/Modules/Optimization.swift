import Foundation
import Darwin
import CoreKit

public struct LaunchItem: Identifiable, Sendable, Hashable {
    public var id: String { plist.path }
    public let label: String
    public let plist: URL
    public let scope: Scope
    public let program: String?
    public var loaded: Bool
    public var disabled: Bool
    public enum Scope: String, Sendable { case userAgent = "User Agent", systemAgent = "System Agent", daemon = "Daemon" }
    public var requiresAdmin: Bool { scope != .userAgent }
}

public enum Optimization {
    static let dirs: [(String, LaunchItem.Scope)] = [
        ("~/Library/LaunchAgents", .userAgent), ("/Library/LaunchAgents", .systemAgent), ("/Library/LaunchDaemons", .daemon),
    ]

    public static func launchItems() async -> [LaunchItem] {
        let list = await ProcessRunner.run(["launchctl", "list"])
        let loadedLabels = Set(list.stdout.split(separator: "\n").compactMap { $0.split(separator: "\t").last.map(String.init) })
        let uid = getuid()
        let disabledOut = await ProcessRunner.run(["launchctl", "print-disabled", "gui/\(uid)"]).stdout
        var out: [LaunchItem] = []
        for (d, scope) in dirs {
            let dir = URL(fileURLWithPath: expandTilde(d))
            for f in (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [] where f.pathExtension == "plist" {
                guard let data = try? Data(contentsOf: f),
                      let plist = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any] else { continue }
                let label = (plist["Label"] as? String) ?? f.deletingPathExtension().lastPathComponent
                let program = (plist["Program"] as? String) ?? (plist["ProgramArguments"] as? [String])?.first
                let isDisabled = disabledOut.contains("\"\(label)\" => disabled")
                out.append(LaunchItem(label: label, plist: f, scope: scope, program: program,
                                      loaded: loadedLabels.contains(label), disabled: isDisabled))
            }
        }
        return out.sorted { $0.label < $1.label }
    }

    /// Tắt (không xóa): bootout + disable. Chỉ hỗ trợ agent của user ở chế độ không cần admin.
    public static func disable(_ item: LaunchItem) async -> ProcessResult {
        let uid = getuid()
        if item.requiresAdmin {
            let domain = item.scope == .daemon ? "system" : "gui/\(uid)"
            return await ProcessRunner.runPrivileged(shell: "launchctl bootout \(domain) '\(item.plist.path)'; launchctl disable \(domain)/\(item.label)")
        }
        _ = await ProcessRunner.run(["launchctl", "bootout", "gui/\(uid)", item.plist.path])
        return await ProcessRunner.run(["launchctl", "disable", "gui/\(uid)/\(item.label)"])
    }

    public static func enable(_ item: LaunchItem) async -> ProcessResult {
        let uid = getuid()
        _ = await ProcessRunner.run(["launchctl", "enable", "gui/\(uid)/\(item.label)"])
        return await ProcessRunner.run(["launchctl", "bootstrap", "gui/\(uid)", item.plist.path])
    }

    /// `rssBytes` là footprint thật (gồm cả phần bị nén/swap) khi đọc được, nếu không thì RSS.
    /// `owner` là tiến trình chịu trách nhiệm (cách Activity Monitor gán máy ảo/helper về đúng app).
    public struct Consumer: Identifiable, Sendable { public let id: Int32; public let name: String; public let cpu: Double; public let rssBytes: Int64; public var owner: Int32 = 0 }

    /// Top tiến trình theo CPU.
    public static func heavyConsumers(limit: Int = 10) async -> [Consumer] {
        let r = await ProcessRunner.run(["ps", "-Aceo", "pid=,pcpu=,rss=,comm=", "-r"])
        return r.stdout.split(separator: "\n").prefix(limit).compactMap { line in
            let p = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard p.count == 4, let pid = Int32(p[0]), let cpu = Double(p[1]), let rss = Int64(p[2]) else { return nil }
            return Consumer(id: pid, name: String(p[3]), cpu: cpu, rssBytes: rss * 1024)
        }
    }
}

extension Optimization {
    /// Footprint thật của một tiến trình (gồm cả bộ nhớ đã nén/swap). `ps`/RSS bỏ sót phần này nên đánh giá thấp
    /// các máy ảo (Docker, Claude…) và app đã bị đẩy ra swap. Chỉ đọc được tiến trình của chính user.
    public static func footprint(of pid: Int32) -> Int64? {
        var ri = rusage_info_v4()
        let ok = withUnsafeMutablePointer(to: &ri) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
        }
        return ok == 0 ? Int64(ri.ri_phys_footprint) : nil
    }

    /// Tiến trình "chịu trách nhiệm" cho `pid` (ví dụ Docker VM → com.docker.backend). API riêng của macOS, có thể vắng.
    public static func responsiblePID(of pid: Int32) -> Int32? {
        typealias Fn = @convention(c) (pid_t) -> pid_t
        guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid") else { return nil }
        let r = unsafeBitCast(sym, to: Fn.self)(pid)
        return r > 0 ? r : nil
    }

    public static func parentPID(of pid: Int32) -> Int32? {
        var info = proc_bsdinfo()
        let n = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size))
        return n > 0 ? Int32(info.pbi_ppid) : nil
    }

    static func processName(_ pid: Int32) -> String? {
        var buf = [CChar](repeating: 0, count: 256)
        return proc_name(pid, &buf, 255) > 0 ? String(cString: buf) : nil
    }

    static func allProcesses() async -> [Consumer] {
        let r = await ProcessRunner.run(["ps", "-Aceo", "pid=,pcpu=,rss=,comm="])
        return r.stdout.split(separator: "\n").compactMap { line in
            let p = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard p.count == 4, let pid = Int32(p[0]), let cpu = Double(p[1]), let rss = Int64(p[2]) else { return nil }
            return Consumer(id: pid, name: String(p[3]), cpu: cpu, rssBytes: footprint(of: pid) ?? rss * 1024,
                            owner: responsiblePID(of: pid) ?? pid)
        }
    }

    /// Top tiến trình theo RAM (footprint), giảm dần.
    public static func memoryConsumers(limit: Int = 40) async -> [Consumer] {
        Array(await allProcesses().sorted { $0.rssBytes > $1.rssBytes }.prefix(limit))
    }

    public struct AppMemory: Identifiable, Sendable {
        public let id: Int32            // pid của app/tiến trình chịu trách nhiệm
        public let name: String
        public let footprint: Int64
        public let cpu: Double
        public let processCount: Int
    }

    /// Gộp theo app chịu trách nhiệm: helper của Chrome, VM của Docker/Claude… được tính vào đúng app chủ.
    public static func memoryByApp(limit: Int = 30) async -> [AppMemory] {
        let groups = Dictionary(grouping: await allProcesses(), by: \.owner)
        return groups.map { owner, ps in
            AppMemory(id: owner, name: processName(owner) ?? ps[0].name, footprint: ps.reduce(0) { $0 + $1.rssBytes },
                      cpu: ps.reduce(0) { $0 + $1.cpu }, processCount: ps.count)
        }.sorted { $0.footprint > $1.footprint }.prefix(limit).map { $0 }
    }

    /// Xóa cache file inactive của macOS (cần quyền admin). Hiệu quả ngắn hạn; macOS tự nạp lại cache khi cần.
    public static func purgeMemory() async -> ProcessResult {
        await ProcessRunner.runPrivileged(shell: "/usr/sbin/purge")
    }
}
