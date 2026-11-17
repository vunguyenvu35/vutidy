import SwiftUI
import CoreKit
import SafetyLayer
import Modules

extension AppState {
    /// Mục mà dọn tự động được phép đụng tới: An toàn **và** hoàn tác được — tức là file đi vào Quarantine.
    /// Không tự dọn: mục dùng lệnh của công cụ (`docker prune`, `go clean`, `brew cleanup`: không khôi phục được),
    /// nội dung Thùng rác (xóa vĩnh viễn) và mọi mục cần xem lại.
    static func isAutoCleanable(_ i: ScanItem) -> Bool { i.isAutoCleanable }

    /// Dọn ngay các mục đủ điều kiện sau một lần Smart Scan, rồi báo một thông báo gộp (có nút Hoàn tác).
    /// Phần không hoàn tác được vẫn nằm chờ trong danh sách để người dùng tự bấm Dọn.
    func autoCleanSafe() async {
        let ids = ["system-junk", "dev-junk"]
        var bytes: Int64 = 0, done = 0, failed = 0
        for id in ids {
            guard var arr = results[id], arr.contains(where: Self.isAutoCleanable) else { continue }
            for i in arr.indices { arr[i].selected = Self.isAutoCleanable(arr[i]) }
            results[id] = arr
            await clean(id, mode: .quarantine, quiet: true)
            if let r = lastReport { bytes += r.reclaimedBytes; done += r.doneCount; failed += r.failures.count }
        }
        // Cập nhật kết quả Smart Scan theo những gì còn lại (số "có thể lấy lại" co lại, phần chờ bạn quyết định còn nguyên).
        var r = smart ?? SmartScanResult()
        r.cleanup = results.values.flatMap { $0 }
        smart = r

        let waiting = (results["dev-junk"] ?? []).filter { $0.safety == .safe && $0.command != nil }
            + (results["trash"] ?? []).filter { $0.safety == .safe }
        let waitingBytes = waiting.reduce(Int64(0)) { $0 + $1.allocatedSize }
        guard done > 0 || failed > 0 else {
            if waitingBytes > 0 { notify(trf("Không có gì tự dọn được. %@ chờ bạn bấm Dọn.", ByteFormat.string(waitingBytes)), .warning) }
            return
        }
        var msg = trf("Đã tự dọn %@ vào Quarantine · hoàn tác trong %@ ngày", ByteFormat.string(bytes), "\(retentionDays)")
        if failed > 0 { msg += trf(" · %@ lỗi", "\(failed)") }
        if waitingBytes > 0 { msg += trf(" · %@ chờ bạn bấm Dọn", ByteFormat.string(waitingBytes)) }
        notify(msg, failed == 0 ? .success : .warning, undo: true)
    }
}
