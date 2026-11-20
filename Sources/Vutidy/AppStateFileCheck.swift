import SwiftUI
import AppKit
import CoreKit
import Modules
import SafetyLayer

extension AppState {
    /// Hộp chọn file rồi kiểm tra. Mở sẵn thư mục chứa file Real-time vừa quét (hoặc Downloads).
    func pickFileToCheck() {
        let p = NSOpenPanel()
        p.canChooseFiles = true; p.canChooseDirectories = false; p.allowsMultipleSelection = false
        p.message = tr("Chọn file hoặc app cần kiểm tra"); p.prompt = tr("Kiểm tra")
        let last = lastScanned.map { URL(fileURLWithPath: $0).deletingLastPathComponent() }
        p.directoryURL = last ?? URL(fileURLWithPath: NSHomeDirectory() + "/Downloads")
        guard p.runModal() == .OK, let url = p.url else { return }
        Task { await checkFile(url) }
    }

    func checkFile(_ url: URL) async {
        fileChecking = true; fileReport = nil
        let st = await ClamAV.status(); let useClam = st.installed && st.hasDatabase
        fileReport = await FileInspector.inspect(url, useClamAV: useClam)
        fileChecking = false
    }

    /// Cách ly file vừa kiểm tra (file người dùng tự chọn nên Desktop/Documents được phép). Khôi phục được trong thời hạn Quarantine.
    func quarantineChecked() async {
        guard let r = fileReport else { return }
        let url = URL(fileURLWithPath: r.path)
        if let why = executor.blocklist.reason(for: url, userSelected: true) { notify(trf("Không thể cách ly: %@", "\(why)"), .error); return }
        let bytes = r.size
        do {
            try await executor.quarantine.add(url, ruleID: "file-check", bytes: bytes)
            executor.audit.append(AuditRecord(date: Date(), action: "quarantine", path: r.path, bytes: bytes, ruleID: "file-check", mode: "file-check", result: "done"))
            alerts.removeAll { $0.path == r.path }
            fileReport = nil
            await refreshQuarantine()
            notify(trf("Đã chuyển %@ vào Quarantine.", r.name))
        } catch { notify(trf("Không thể cách ly: %@", error.localizedDescription), .error) }
    }
}
