import Foundation
import CoreKit

/// Điểm duy nhất thực hiện xóa/di chuyển. Mọi module đi qua đây để luôn qua blocklist, dry-run và audit.
public final class ActionExecutor: @unchecked Sendable {
    public let blocklist: Blocklist
    public let quarantine: Quarantine
    public let audit: AuditLog

    public init(blocklist: Blocklist = Blocklist(), quarantine: Quarantine, audit: AuditLog) {
        self.blocklist = blocklist
        self.quarantine = quarantine
        self.audit = audit
    }

    public convenience init(paths: AppPaths = .default, retentionDays: Int = 7) {
        self.init(quarantine: Quarantine(root: paths.quarantine, retentionDays: retentionDays),
                  audit: AuditLog(url: paths.auditLog))
    }

    public func execute(_ items: [ScanItem], mode: CleanMode,
                        progress: (@Sendable (Int, Int) -> Void)? = nil) async -> CleanReport {
        var outcomes: [CleanOutcome] = []
        for (i, item) in items.enumerated() {
            if Task.isCancelled { break }
            outcomes.append(await executeOne(item, mode: mode))
            progress?(i + 1, items.count)
        }
        return CleanReport(outcomes: outcomes, mode: mode)
    }

    func executeOne(_ item: ScanItem, mode: CleanMode) async -> CleanOutcome {
        func out(_ s: OutcomeStatus, _ note: String? = nil) -> CleanOutcome {
            log(item, mode: mode, result: s)
            return CleanOutcome(itemID: item.id, path: item.url.path, bytes: item.allocatedSize, status: s, note: note)
        }

        // Mục dọn bằng lệnh native (docker/go/brew…).
        if let cmd = item.command {
            let line = "$ " + cmd.joined(separator: " ")
            if mode == .dryRun { return out(.dryRun, line) }
            let r = await ProcessRunner.run(cmd)
            return r.ok ? out(.done, line)
                        : out(.failed(r.stderr.trimmingCharacters(in: .whitespacesAndNewlines)), line)
        }

        if let why = blocklist.reason(for: item.url) { return out(.skipped(trf("bị chặn: %@", "\(why)"))) }
        let fm = FileManager.default
        guard fm.fileExists(atPath: item.url.path) || (try? item.url.checkResourceIsReachable()) == true
                || (try? fm.destinationOfSymbolicLink(atPath: item.url.path)) != nil else {
            return out(.skipped(tr("không còn tồn tại")))
        }

        switch mode {
        case .dryRun:
            return out(.dryRun, trf("sẽ chuyển vào Quarantine: %@", "\(item.url.path)"))
        case .moveToTrash:
            do {
                var result: NSURL?
                try fm.trashItem(at: item.url, resultingItemURL: &result)
                return out(.done, trf("Thùng rác: %@", "\(result?.path ?? "")"))
            } catch { return out(.failed(error.localizedDescription)) }
        case .quarantine:
            do {
                let e = try await quarantine.add(item.url, ruleID: item.ruleID, bytes: item.allocatedSize)
                return out(.done, "Quarantine: \(e.storedPath)")
            } catch { return out(.failed(error.localizedDescription)) }
        case .permanent:
            do {
                try fm.removeItem(at: item.url)
                return out(.done, tr("đã xóa vĩnh viễn"))
            } catch { return out(.failed(error.localizedDescription)) }
        }
    }

    private func log(_ item: ScanItem, mode: CleanMode, result: OutcomeStatus) {
        let r: String
        switch result {
        case .done: r = "done"
        case .dryRun: r = "dryRun"
        case .skipped(let s): r = "skipped: \(s)"
        case .failed(let s): r = "failed: \(s)"
        }
        audit.append(AuditRecord(date: Date(), action: item.isCLI ? "command" : "remove",
                                 path: item.command?.joined(separator: " ") ?? item.url.path,
                                 bytes: item.allocatedSize, ruleID: item.ruleID, mode: mode.rawValue, result: r))
    }
}
