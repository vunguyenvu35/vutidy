import Foundation
import CoreKit
import ScanEngine

/// Chi tiết một mục trong nhóm, đã ẩn danh: không tên người dùng, không tên project.
public struct InspectItem: Codable, Sendable, Equatable {
    public var name: String
    public var sizeMB: Int
    public var safety: String
    /// Lệnh của công cụ sẽ chạy nếu dọn (vd. "docker image prune -f"); nil nếu là file/thư mục.
    public var tool: String?
    /// Số ngày từ lần sửa cuối.
    public var ageDays: Int?
    /// Số ngày từ lần truy cập cuối (nếu hệ thống ghi nhận).
    public var idleDays: Int?
    public var location: String
}

public struct DockerImageInfo: Codable, Sendable, Equatable {
    public var name: String
    public var tag: String
    public var sizeMB: Int
    public var ageDays: Int?
    /// Có container (kể cả đã dừng) đang dùng image này: dọn sẽ không xóa nó.
    public var inUse: Bool
}

public struct GroupDetail: Codable, Sendable, Equatable {
    public var group: String
    public var totalItems: Int
    public var items: [InspectItem]
    public var dockerImages: [DockerImageInfo]?
}

/// Đọc chi tiết các nhóm mà AI yêu cầu xem. Chỉ-đọc, chạy trên máy; AI chỉ chọn tên nhóm trong danh sách app đưa ra, không tự chạy lệnh.
public enum AdvisorInspector {
    public static let maxItems = 12
    public static let maxImages = 15
    public static let maxGroups = 4

    /// Đường dẫn đã ẩn danh: thư mục home thành `~`; thư mục project (node_modules, venv…) chỉ còn `<project>/tên-cuối`.
    static func sanitize(path: String, ruleID: String, home: String = NSHomeDirectory()) -> String {
        if ruleID.hasPrefix("stale-project") { return "<project>/" + (path as NSString).lastPathComponent }
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }

    static func days(since d: Date?, now: Date) -> Int? { d.map { max(0, Int(now.timeIntervalSince($0) / 86_400)) } }

    static func detail(for group: String, in r: SmartScanResult, now: Date = Date(), home: String = NSHomeDirectory()) -> GroupDetail {
        let all = r.cleanup.filter { AdvisorPlanner.sanitizedCategory($0.category) == group }.sorted { $0.allocatedSize > $1.allocatedSize }
        let items = all.prefix(maxItems).map { it -> InspectItem in
            let isCLI = it.command != nil
            let access = isCLI ? nil : (try? it.url.resourceValues(forKeys: [.contentAccessDateKey]))?.contentAccessDate
            return InspectItem(name: it.title, sizeMB: Int((Double(it.allocatedSize) / 1_000_000).rounded()), safety: it.safety.rawValue,
                               tool: it.command?.joined(separator: " "),
                               ageDays: isCLI ? nil : days(since: FileWalker.mtime(of: it.url), now: now), idleDays: days(since: access, now: now),
                               location: sanitize(path: it.url.path, ruleID: it.ruleID, home: home))
        }
        return GroupDetail(group: group, totalItems: all.count, items: Array(items), dockerImages: nil)
    }

    // MARK: Docker

    /// "1.23GB" / "456MB" / "12kB" → MB.
    static func parseMB(_ s: String) -> Int {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard let i = t.firstIndex(where: { $0.isLetter }), let v = Double(t[..<i]) else { return 0 }
        switch t[i...].lowercased() {
        case "gb": return Int(v * 1000)
        case "mb": return Int(v)
        case "kb": return Int(v / 1000)
        case "tb": return Int(v * 1_000_000)
        default: return 0
        }
    }

    /// Chỉ giữ phần cuối của repository ("registry.corp.com/team/app" → "app") để không lộ tên registry/công ty.
    static func shortName(_ repo: String) -> String { repo.split(separator: "/").last.map(String.init) ?? repo }

    /// `docker images --format '{{json .}}'` + danh sách image mà container đang dùng.
    static func parseDockerImages(_ lines: String, usedRefs: Set<String>, now: Date = Date()) -> [DockerImageInfo] {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        var out: [DockerImageInfo] = []
        for line in lines.split(separator: "\n") {
            guard let o = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any] else { continue }
            let repo = (o["Repository"] as? String) ?? "<none>", tag = (o["Tag"] as? String) ?? "<none>", id = (o["ID"] as? String) ?? ""
            let created = (o["CreatedAt"] as? String).flatMap { f.date(from: String($0.prefix(19))) }
            let inUse = usedRefs.contains("\(repo):\(tag)") || usedRefs.contains(repo) || (!id.isEmpty && usedRefs.contains { $0.hasPrefix(id) || id.hasPrefix($0) })
            out.append(DockerImageInfo(name: repo == "<none>" ? "<untagged>" : shortName(repo), tag: tag == "<none>" ? "" : tag,
                                       sizeMB: parseMB((o["Size"] as? String) ?? ""), ageDays: days(since: created, now: now), inUse: inUse))
        }
        return Array(out.sorted { $0.sizeMB > $1.sizeMB }.prefix(maxImages))
    }

    static func dockerImages() async -> [DockerImageInfo]? {
        guard ProcessRunner.which("docker") != nil else { return nil }
        let imgs = await ProcessRunner.run(["docker", "images", "--format", "{{json .}}"], timeout: 20)
        guard imgs.ok else { return nil }
        let ps = await ProcessRunner.run(["docker", "ps", "-a", "--format", "{{.Image}}"], timeout: 20)
        let used = Set(ps.stdout.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) })
        return parseDockerImages(imgs.stdout, usedRefs: used)
    }

    // MARK: Điểm vào

    public static func inspect(_ groups: [String], in r: SmartScanResult) async -> [GroupDetail] {
        var out: [GroupDetail] = []
        for g in groups.prefix(maxGroups) {
            var d = detail(for: g, in: r)
            if g == "Docker" { d.dockerImages = await dockerImages() }
            out.append(d)
        }
        return out
    }

    public static func json(_ d: [GroupDetail]) -> String {
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? String(data: e.encode(d), encoding: .utf8)) ?? "[]"
    }

    /// Nhóm AI được phép xin xem sâu: những nhóm có mục, lớn nhất trước.
    public static func inspectableGroups(_ r: SmartScanResult) -> [String] {
        var size: [String: Int64] = [:]
        for it in r.cleanup { size[AdvisorPlanner.sanitizedCategory(it.category), default: 0] += it.allocatedSize }
        return size.sorted { ($0.value, $1.key) > ($1.value, $0.key) }.prefix(8).map(\.key)
    }
}
