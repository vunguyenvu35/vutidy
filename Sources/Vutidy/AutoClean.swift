import SwiftUI
import CoreKit
import SafetyLayer
import Modules

extension AppState {
    /// Dọn ngay các mục đủ điều kiện sau một lần Smart Scan, rồi báo một thông báo gộp.
    ///
    /// Mặc định chỉ lấy mục An toàn **và** hoàn tác được (file vào Quarantine). Khi người dùng bật
    /// "Gồm cả mục không hoàn tác được" thì lấy luôn mục An toàn dùng lệnh của công cụ (`docker prune`, `go clean`,
    /// `brew cleanup`) và Thùng rác (xóa vĩnh viễn) — giống nút Dọn. Mục cần xem lại không bao giờ tự dọn.
    func autoCleanSafe() async {
        let all = autoCleanIrreversible
        func eligible(_ i: ScanItem) -> Bool { all ? i.safety == .safe : i.isAutoCleanable }
        var bytes: Int64 = 0, done = 0, failed = 0, permanent: Int64 = 0   // permanent: phần Thùng rác đã xóa hẳn (để quyết định có nút Hoàn tác)

        for id in ["system-junk", "dev-junk", "ai", "trash"] {
            if id == "trash" && !all { continue }                       // Thùng rác chỉ khi người dùng cho phép xóa vĩnh viễn
            guard var arr = results[id], arr.contains(where: eligible) else { continue }
            for i in arr.indices { arr[i].selected = eligible(arr[i]) }
            results[id] = arr
            await clean(id, mode: id == "trash" ? .permanent : .quarantine, quiet: true, allowQuit: false)
            if let r = lastReport {
                bytes += r.reclaimedBytes; done += r.doneCount; failed += r.failures.count
                if id == "trash" { permanent += r.reclaimedBytes }
            }
        }
        // Cập nhật kết quả Smart Scan theo những gì còn lại.
        var r = smart ?? SmartScanResult()
        r.cleanup = results.values.flatMap { $0 }
        smart = r

        let waiting = ["system-junk", "dev-junk", "ai", "trash"].flatMap { results[$0] ?? [] }.filter { $0.safety == .safe }
        let waitingBytes = waiting.reduce(Int64(0)) { $0 + $1.allocatedSize }
        guard done > 0 || failed > 0 else {
            if waitingBytes > 0 { notify(trf("Không có gì tự dọn được. %@ chờ bạn bấm Dọn.", ByteFormat.string(waitingBytes)), .warning) }
            return
        }
        var msg = all
            ? trf("Đã tự dọn %@ · file vào Quarantine hoàn tác được trong %@ ngày; lệnh docker/go/brew và Thùng rác đã xóa hẳn", ByteFormat.string(bytes), "\(retentionDays)")
            : trf("Đã tự dọn %@ vào Quarantine · hoàn tác trong %@ ngày", ByteFormat.string(bytes), "\(retentionDays)")
        if failed > 0 { msg += trf(" · %@ lỗi", "\(failed)") }
        if waitingBytes > 0 { msg += trf(" · %@ chờ bạn bấm Dọn", ByteFormat.string(waitingBytes)) }
        notify(msg, failed == 0 ? .success : .warning, undo: bytes - permanent > 0)
    }
}
