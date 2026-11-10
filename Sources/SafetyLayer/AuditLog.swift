import Foundation

public struct AuditRecord: Codable, Sendable {
    public let date: Date
    public let action: String
    public let path: String
    public let bytes: Int64
    public let ruleID: String
    public let mode: String
    public let result: String

    public init(date: Date, action: String, path: String, bytes: Int64, ruleID: String, mode: String, result: String) {
        self.date = date; self.action = action; self.path = path; self.bytes = bytes; self.ruleID = ruleID; self.mode = mode; self.result = result
    }
}

/// Ghi mọi thao tác xóa/di chuyển dạng JSON lines.
public final class AuditLog: @unchecked Sendable {
    private let url: URL
    private let lock = NSLock()
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    public init(url: URL) { self.url = url }

    public func append(_ r: AuditRecord) {
        lock.lock(); defer { lock.unlock() }
        guard var data = try? encoder.encode(r) else { return }
        data.append(0x0A)
        let fm = FileManager.default
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let h = try? FileHandle(forWritingTo: url) {
            defer { try? h.close() }
            _ = try? h.seekToEnd()
            try? h.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }

    public func recent(limit: Int = 200) -> [AuditRecord] {
        lock.lock(); defer { lock.unlock() }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return text.split(separator: "\n").suffix(limit).compactMap {
            try? d.decode(AuditRecord.self, from: Data($0.utf8))
        }
    }
}
