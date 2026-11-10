import Foundation
import CoreKit

public struct Rule: Codable, Sendable, Identifiable {
    public var id: String
    public var module: String
    public var title: String
    /// Nhóm hiển thị (Docker, JetBrains…).
    public var group: String
    public var paths: [String]
    public var exclude: [String]?
    public var minAgeDays: Int?
    /// Bỏ qua cả rule nếu có app đang chạy khớp bundle ID glob (ví dụ "com.jetbrains.*").
    public var skipIfRunningBundle: String?
    /// Bỏ qua từng mục có tên thư mục trùng bundle ID của app đang chạy.
    public var appNotRunning: Bool?
    public var safety: SafetyLevel
    /// Lệnh native thay cho xóa file (ví dụ ["go","clean","-cache"]).
    public var command: [String]?
    /// Chỉ áp dụng nếu lệnh này tồn tại (ví dụ "go").
    public var requires: String?
    public var detail: String?
}

public enum RuleLoader {
    public static func loadBundled() -> [Rule] {
        guard let url = Bundle.module.url(forResource: "rules", withExtension: "json", subdirectory: "Resources"),
              let data = try? Data(contentsOf: url),
              let rules = try? JSONDecoder().decode([Rule].self, from: data) else { return [] }
        return rules
    }

    /// Rule bundled + rule người dùng ghi đè/thêm (cùng `id` thì rule người dùng thắng).
    public static func loadAll(paths: AppPaths = .default) -> [Rule] {
        var byID: [String: Rule] = [:]
        var order: [String] = []
        for r in loadBundled() { byID[r.id] = r; order.append(r.id) }
        let fm = FileManager.default
        if let files = try? fm.contentsOfDirectory(at: paths.userRules, includingPropertiesForKeys: nil) {
            for f in files where f.pathExtension == "json" {
                guard let data = try? Data(contentsOf: f),
                      let rules = try? JSONDecoder().decode([Rule].self, from: data) else { continue }
                for r in rules {
                    if byID[r.id] == nil { order.append(r.id) }
                    byID[r.id] = r
                }
            }
        }
        return order.compactMap { byID[$0] }
    }
}
