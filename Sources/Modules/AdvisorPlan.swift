import Foundation
import CoreKit

/// Một hành động app có thể thực hiện và AI được phép đề xuất. AI chỉ chọn trong danh sách này (theo `id`), không tự nghĩ ra lệnh.
public struct AdvisorAction: Codable, Sendable, Hashable, Identifiable {
    public enum Kind: String, Codable, Sendable { case clean, terminateAgents, review }
    public let id: String          // "clean:Docker" · "terminate-agents" · "review:Node"
    public let kind: Kind
    public let category: String    // nhóm rác (rỗng với terminate-agents)
    public let items: Int
    public let megabytes: Int
    public init(id: String, kind: Kind, category: String, items: Int, megabytes: Int) {
        self.id = id; self.kind = kind; self.category = category; self.items = items; self.megabytes = megabytes
    }
}

/// Một bước trong kế hoạch của AI: hành động + lý do ngắn.
public struct AdvisorStep: Sendable, Equatable, Identifiable {
    public var id: String { action.id }
    public let action: AdvisorAction
    public let reason: String
    public init(action: AdvisorAction, reason: String) { self.action = action; self.reason = reason }
}

public struct AdvisorPlan: Sendable, Equatable {
    public let summary: String
    public let steps: [AdvisorStep]
    public init(summary: String, steps: [AdvisorStep]) { self.summary = summary; self.steps = steps }
}

public enum AdvisorPlanner {
    /// Tên nhóm gửi cho AI và dùng làm khóa hành động: nhóm trông như đường dẫn hoặc quá dài gộp vào "Other".
    /// Nhóm nhỏ hơn mức này không được đề xuất như một bước dọn.
    public static let minCleanMB = 5
    public static func sanitizedCategory(_ c: String) -> String { (c.contains("/") || c.count > 40) ? "Other" : c }
    /// Các hành động khả dụng cho kết quả quét này. Chỉ gồm việc an toàn và hoàn tác được (vào Quarantine); mục cần xem lại chỉ được "xem".
    public static func availableActions(_ r: SmartScanResult) -> [AdvisorAction] {
        let clean = sanitizedCategory
        let mb = { (b: Int64) in Int((Double(b) / 1_000_000).rounded()) }
        var out: [AdvisorAction] = []

        // Thùng rác không bao giờ là hành động của AI: xóa nó là vĩnh viễn, không phải "vào Quarantine".
        let reversible = r.cleanup.filter { $0.isAutoCleanable && $0.ruleID != "trash" }
        for (cat, items) in Dictionary(grouping: reversible, by: { clean($0.category) }).sorted(by: { $0.key < $1.key }) {
            let size = mb(items.reduce(0) { $0 + $1.allocatedSize })
            guard size >= minCleanMB else { continue }   // dọn vài KB không đáng thành một bước ("+0 KB" chỉ là nhiễu)
            out.append(.init(id: "clean:\(cat)", kind: .clean, category: cat, items: items.count, megabytes: size))
        }
        let flagged = r.flaggedAgents
        if !flagged.isEmpty {
            out.append(.init(id: "terminate-agents", kind: .terminateAgents, category: "", items: flagged.count,
                             megabytes: mb(flagged.reduce(0) { $0 + $1.footprint })))
        }
        let review = r.cleanup.filter { $0.safety == .review && $0.ruleID != "trash" }
        for (cat, items) in Dictionary(grouping: review, by: { clean($0.category) }).sorted(by: { $0.key < $1.key }) {
            out.append(.init(id: "review:\(cat)", kind: .review, category: cat, items: items.count, megabytes: mb(items.reduce(0) { $0 + $1.allocatedSize })))
        }
        return out
    }

    /// Đọc câu trả lời của AI thành kế hoạch. Chịu được chữ thừa/khung ``` quanh JSON; bỏ mọi `id` không nằm trong `available`.
    public static func parse(_ text: String, available: [AdvisorAction]) -> AdvisorPlan? {
        guard let a = text.firstIndex(of: "{"), let b = text.lastIndex(of: "}"), a < b,
              let data = String(text[a...b]).data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        var summary = ""
        if let s = obj["summary"] as? String { summary = s }
        else if let l = obj["summary"] as? [String] { summary = l.joined(separator: "\n") }
        summary = summary.trimmingCharacters(in: .whitespacesAndNewlines)

        let byID = Dictionary(available.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var seen = Set<String>(), steps: [AdvisorStep] = []
        for e in (obj["actions"] as? [[String: Any]]) ?? [] {
            guard let id = e["id"] as? String, let act = byID[id], seen.insert(id).inserted else { continue }
            let why = ((e["reason"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            steps.append(AdvisorStep(action: act, reason: String(why.prefix(200))))
            if steps.count == 6 { break }
        }
        return summary.isEmpty && steps.isEmpty ? nil : AdvisorPlan(summary: summary, steps: steps)
    }
}
