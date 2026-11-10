import Foundation
import CoreKit
import ScanEngine
import RuleEngine
import SafetyLayer

/// Dev Junk: rule-based + detector Docker, JetBrains orphan, node_modules/vendor/venv trong project cũ.
public struct DevJunkModule: CleanerModule {
    public let id = "dev-junk"
    public let title = "Dev Junk"
    public let requiresPrivilege = false
    let rules: [Rule]
    let evaluator: RuleEvaluator
    public var projectRoots: [URL]
    public var staleProjectDays: Int

    public init(rules: [Rule] = RuleLoader.loadAll(), evaluator: RuleEvaluator = RuleEvaluator(),
                projectRoots: [URL] = [], staleProjectDays: Int = 60) {
        self.rules = rules.filter { $0.module == "dev-junk" }
        self.evaluator = evaluator
        self.projectRoots = projectRoots
        self.staleProjectDays = staleProjectDays
    }

    public func scan(progress: @escaping @Sendable (String) -> Void) async throws -> [ScanItem] {
        var items = await evaluator.scan(rules, progress: progress)
        progress("Docker")
        items += await DockerDetector.scan()
        progress(tr("JetBrains (phiên bản cũ)"))
        items += JetBrainsOrphans.scan()
        if !projectRoots.isEmpty {
            progress(tr("Thư mục project"))
            items += await ProjectArtifacts.scan(roots: projectRoots, staleDays: staleProjectDays)
        }
        return items
    }
}

// MARK: - Docker

public enum DockerDetector {
    /// Parse "1.2GB", "512MB", "3.5kB", "0B" → bytes (đơn vị thập phân như docker).
    public static func parseSize(_ s: String) -> Int64 {
        let t = s.trimmingCharacters(in: .whitespaces)
        let numPart = t.prefix { "0123456789.".contains($0) }
        let unit = t.dropFirst(numPart.count).trimmingCharacters(in: .whitespaces).uppercased()
        guard let n = Double(numPart) else { return 0 }
        let mult: Double = ["B": 1, "KB": 1e3, "MB": 1e6, "GB": 1e9, "TB": 1e12][unit] ?? 1
        return Int64(n * mult)
    }

    struct Row: Decodable { let `Type`: String; let Reclaimable: String }

    /// Parse output của `docker system df --format '{{json .}}'`.
    static func parse(_ output: String) -> [(type: String, bytes: Int64)] {
        output.split(separator: "\n").compactMap { line in
            guard let row = try? JSONDecoder().decode(Row.self, from: Data(line.utf8)) else { return nil }
            // Reclaimable có dạng "3.5GB (45%)"
            let size = row.Reclaimable.split(separator: " ").first.map(String.init) ?? "0B"
            return (row.`Type`, parseSize(size))
        }
    }

    public static func scan() async -> [ScanItem] {
        guard ProcessRunner.which("docker") != nil else { return [] }
        let r = await ProcessRunner.run(["docker", "system", "df", "--format", "{{json .}}"], timeout: 20)
        guard r.ok else { return [] }
        let dockerDir = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Containers/com.docker.docker")
        let map: [String: (String, [String], SafetyLevel, String)] = [
            "Images": (tr("Image không dùng"), ["docker", "image", "prune", "-f"], .safe, "docker-images"),
            "Build Cache": ("Build cache", ["docker", "builder", "prune", "-f"], .safe, "docker-build-cache"),
            "Containers": (tr("Container đã dừng"), ["docker", "container", "prune", "-f"], .review, "docker-containers"),
            "Local Volumes": (tr("Volume không dùng"), ["docker", "volume", "prune", "-f"], .review, "docker-volumes"),
        ]
        return parse(r.stdout).compactMap { row in
            guard row.bytes > 0, let m = map[row.type] else { return nil }
            return ScanItem(url: dockerDir, title: m.0, allocatedSize: row.bytes, category: "Docker",
                            ruleID: m.3, safety: m.2, command: m.1,
                            detail: m.2 == .review ? tr("Volume/container có thể chứa dữ liệu") : tr("Dọn bằng lệnh docker, không hoàn tác"))
        }
    }
}

// MARK: - JetBrains orphans

public enum JetBrainsOrphans {
    static func parse(_ name: String) -> (ide: String, version: [Int])? {
        guard let r = name.range(of: #"\d{4}\.\d+(\.\d+)?$"#, options: .regularExpression), r.lowerBound != name.startIndex else { return nil }
        let ide = String(name[..<r.lowerBound])
        let ver = name[r].split(separator: ".").compactMap { Int($0) }
        return (ide, ver)
    }

    static func lessThan(_ a: [Int], _ b: [Int]) -> Bool {
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x < y }
        }
        return false
    }

    /// Trả về các thư mục config/cache của phiên bản cũ (giữ phiên bản mới nhất của mỗi IDE).
    public static func olderVersions(in names: [String]) -> [String] {
        var latest: [String: [Int]] = [:]
        let parsed = names.compactMap { n in parse(n).map { (n, $0.ide, $0.version) } }
        for (_, ide, v) in parsed { if latest[ide] == nil || lessThan(latest[ide]!, v) { latest[ide] = v } }
        return parsed.filter { _, ide, v in lessThan(v, latest[ide]!) }.map { $0.0 }
    }

    public static func scan(base: URL = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support/JetBrains")) -> [ScanItem] {
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: base.path)) ?? [])
        return olderVersions(in: names).map { n in
            let u = base.appendingPathComponent(n)
            return ScanItem(url: u, title: n, allocatedSize: FileWalker.allocatedSize(of: u), category: "JetBrains",
                            ruleID: "jetbrains-orphan-config", safety: .review,
                            detail: tr("Config của phiên bản IDE cũ — mất setting nếu bạn còn dùng"))
        }.filter { $0.allocatedSize > 0 }
    }
}

// MARK: - node_modules / vendor / venv của project lâu không đụng tới

public enum ProjectArtifacts {
    struct Kind { let dir: String; let marker: String; let group: String }
    static let kinds = [
        Kind(dir: "node_modules", marker: "package.json", group: "Node.js"),
        Kind(dir: "vendor", marker: "composer.json", group: "PHP"),
        Kind(dir: "target", marker: "Cargo.toml", group: "Rust"),
        Kind(dir: ".venv", marker: "pyproject.toml", group: "Python"),
        Kind(dir: "venv", marker: "requirements.txt", group: "Python"),
        Kind(dir: "Pods", marker: "Podfile", group: "CocoaPods"),
    ]
    static let skipDirs: Set<String> = [".git", "Library", ".Trash", "node_modules", ".build", "DerivedData"]

    public static func scan(roots: [URL], staleDays: Int, maxDepth: Int = 6) async -> [ScanItem] {
        let found = await Concurrent.map(roots) { find(in: $0, staleDays: staleDays, maxDepth: maxDepth) }
        let urls = found.flatMap { $0 }
        return await Concurrent.map(urls) { (url, group) in
            ScanItem(url: url, title: "\(url.deletingLastPathComponent().lastPathComponent)/\(url.lastPathComponent)",
                     allocatedSize: FileWalker.allocatedSize(of: url), category: group, ruleID: "stale-project-\(group.lowercased())",
                     safety: .review, detail: trf("Project không đổi trong %@+ ngày: %@", "\(staleDays)", "\(url.deletingLastPathComponent().path)"))
        }.filter { $0.allocatedSize > 0 }
    }

    static func find(in root: URL, staleDays: Int, maxDepth: Int) -> [(URL, String)] {
        var out: [(URL, String)] = []
        let now = Date()
        func visit(_ dir: URL, depth: Int) {
            if depth > maxDepth || Task.isCancelled { return }
            for k in FileWalker.children(of: dir) where k.isDir && !k.isSymlink {
                let name = k.url.lastPathComponent
                if let kind = kinds.first(where: { $0.dir == name }) {
                    let marker = dir.appendingPathComponent(kind.marker)
                    if let m = FileWalker.mtime(of: marker), now.timeIntervalSince(m) > Double(staleDays) * 86_400 {
                        out.append((k.url, kind.group))
                    }
                    continue   // không đi sâu vào bên trong
                }
                if skipDirs.contains(name) { continue }
                visit(k.url, depth: depth + 1)
            }
        }
        visit(root, depth: 0)
        return out
    }
}
