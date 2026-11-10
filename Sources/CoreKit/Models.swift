import Foundation

public enum SafetyLevel: String, Codable, Sendable, CaseIterable {
    case safe, review, dangerous
}

public enum CleanMode: String, Codable, Sendable, CaseIterable {
    case dryRun, moveToTrash, quarantine, permanent
}

public struct ScanItem: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var url: URL
    public var title: String
    public var allocatedSize: Int64
    /// Nhóm hiển thị (ví dụ "Docker", "JetBrains").
    public var category: String
    public var ruleID: String
    public var safety: SafetyLevel
    public var selected: Bool
    /// Nếu có: dọn bằng lệnh native của công cụ (docker prune, go clean…), không hoàn tác được.
    public var command: [String]?
    public var detail: String?

    public init(id: UUID = UUID(), url: URL, title: String, allocatedSize: Int64,
                category: String, ruleID: String, safety: SafetyLevel,
                selected: Bool? = nil, command: [String]? = nil, detail: String? = nil) {
        self.id = id
        self.url = url
        self.title = title
        self.allocatedSize = allocatedSize
        self.category = category
        self.ruleID = ruleID
        self.safety = safety
        self.selected = selected ?? (safety == .safe)
        self.command = command
        self.detail = detail
    }

    public var isCLI: Bool { command != nil }
}

public enum OutcomeStatus: Equatable, Sendable {
    case done
    case dryRun
    case skipped(String)
    case failed(String)
}

public struct CleanOutcome: Sendable {
    public let itemID: UUID
    public let path: String
    public let bytes: Int64
    public let status: OutcomeStatus
    /// Mô tả hành động (đường dẫn quarantine, lệnh đã chạy…).
    public let note: String?

    public init(itemID: UUID, path: String, bytes: Int64, status: OutcomeStatus, note: String? = nil) {
        self.itemID = itemID; self.path = path; self.bytes = bytes; self.status = status; self.note = note
    }
}

public struct CleanReport: Sendable {
    public var outcomes: [CleanOutcome]
    public var mode: CleanMode

    public init(outcomes: [CleanOutcome] = [], mode: CleanMode) {
        self.outcomes = outcomes; self.mode = mode
    }

    public var reclaimedBytes: Int64 {
        outcomes.filter { $0.status == .done || $0.status == .dryRun }.reduce(0) { $0 + $1.bytes }
    }
    public var doneCount: Int { outcomes.filter { $0.status == .done }.count }
    public var failures: [CleanOutcome] {
        outcomes.filter { if case .failed = $0.status { return true }; return false }
    }
    public var skipped: [CleanOutcome] {
        outcomes.filter { if case .skipped = $0.status { return true }; return false }
    }
}
