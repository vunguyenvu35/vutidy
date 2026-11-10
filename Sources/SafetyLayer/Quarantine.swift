import Foundation
import CoreKit

public struct QuarantineEntry: Codable, Identifiable, Sendable, Hashable {
    public let id: UUID
    public let originalPath: String
    public let storedPath: String
    public let bytes: Int64
    public let ruleID: String
    public let date: Date

    public func daysLeft(retentionDays: Int, now: Date = Date()) -> Int {
        let expire = date.addingTimeInterval(Double(retentionDays) * 86_400)
        return max(0, Int((expire.timeIntervalSince(now) / 86_400).rounded(.up)))
    }
}

public enum QuarantineError: Error, LocalizedError {
    case notFound
    case originalExists(String)
    public var errorDescription: String? {
        switch self {
        case .notFound: return tr("Không tìm thấy mục trong Quarantine")
        case .originalExists(let p): return trf("Đường dẫn gốc đã tồn tại: %@", "\(p)")
        }
    }
}

/// Khu cách ly: di chuyển thay vì xóa, giữ nguyên permission/xattrs, khôi phục được về đúng path gốc.
public actor Quarantine {
    public nonisolated let root: URL
    public nonisolated let retentionDays: Int
    private var index: [QuarantineEntry]
    private var indexURL: URL { root.appendingPathComponent("index.json") }

    public init(root: URL, retentionDays: Int = 7) {
        self.root = root
        self.retentionDays = retentionDays
        let url = root.appendingPathComponent("index.json")
        if let data = try? Data(contentsOf: url) {
            let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
            self.index = (try? d.decode([QuarantineEntry].self, from: data)) ?? []
        } else {
            self.index = []
        }
    }

    private func save() {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        if let data = try? e.encode(index) { try? data.write(to: indexURL, options: .atomic) }
    }

    @discardableResult
    public func add(_ url: URL, ruleID: String, bytes: Int64, now: Date = Date()) throws -> QuarantineEntry {
        let fm = FileManager.default
        let id = UUID()
        let dir = root.appendingPathComponent(id.uuidString, isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent(url.lastPathComponent)
        do { try fm.moveItem(at: url, to: dest) } catch {
            try? fm.removeItem(at: dir)
            throw error
        }
        let entry = QuarantineEntry(id: id, originalPath: url.path, storedPath: dest.path,
                                    bytes: bytes, ruleID: ruleID, date: now)
        index.append(entry)
        save()
        return entry
    }

    public func entries() -> [QuarantineEntry] { index.sorted { $0.date > $1.date } }
    public func totalBytes() -> Int64 { index.reduce(0) { $0 + $1.bytes } }

    @discardableResult
    public func restore(_ id: UUID) throws -> URL {
        guard let i = index.firstIndex(where: { $0.id == id }) else { throw QuarantineError.notFound }
        let e = index[i]
        let fm = FileManager.default
        let original = URL(fileURLWithPath: e.originalPath)
        if fm.fileExists(atPath: original.path) { throw QuarantineError.originalExists(original.path) }
        try fm.createDirectory(at: original.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.moveItem(at: URL(fileURLWithPath: e.storedPath), to: original)
        try? fm.removeItem(at: root.appendingPathComponent(e.id.uuidString))
        index.remove(at: i)
        save()
        return original
    }

    /// Xóa vĩnh viễn một mục trong quarantine.
    public func purge(_ id: UUID) {
        guard let i = index.firstIndex(where: { $0.id == id }) else { return }
        try? FileManager.default.removeItem(at: root.appendingPathComponent(index[i].id.uuidString))
        index.remove(at: i)
        save()
    }

    /// Xóa các mục quá hạn retention. Trả về số mục đã xóa.
    @discardableResult
    public func purgeExpired(now: Date = Date()) -> Int {
        let limit = Double(retentionDays) * 86_400
        let expired = index.filter { now.timeIntervalSince($0.date) >= limit }
        for e in expired { purge(e.id) }
        return expired.count
    }
}
