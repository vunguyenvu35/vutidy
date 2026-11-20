import SwiftUI
import CoreKit
import Modules

extension AppState {
    static let trashAlertBytes: Int64 = 5_000_000_000

    /// Đo Thùng rác (kể cả ổ ngoài). Không đo được khi thiếu Full Disk Access: kết quả rỗng khi đó KHÔNG có nghĩa là trống.
    func refreshTrashSize() async {
        guard !TrashModule.isBlocked else { trashBytes = 0; return }
        let total = await Task.detached(priority: .utility) { () -> Int64 in
            ((try? await TrashModule().scan { _ in }) ?? []).reduce(0) { $0 + $1.allocatedSize }
        }.value
        trashBytes = total
        notifyTrashIfNeeded()
        pollSystem()
    }

    /// Báo (toast + thông báo hệ thống) khi vượt ngưỡng: tối đa một lần mỗi 3 ngày, hoặc khi lớn thêm 50% so với lần báo trước.
    func notifyTrashIfNeeded(now: Date = Date()) {
        let d = UserDefaults.standard
        guard trashBytes > Self.trashAlertBytes else { d.removeObject(forKey: "trashNotifiedAt"); d.removeObject(forKey: "trashNotifiedBytes"); return }
        guard notifyTrash else { return }
        if let at = d.object(forKey: "trashNotifiedAt") as? Date {
            let prev = Int64(d.integer(forKey: "trashNotifiedBytes"))
            if now.timeIntervalSince(at) < 3 * 86_400 && Double(trashBytes) < Double(prev) * 1.5 { return }
        }
        d.set(now, forKey: "trashNotifiedAt"); d.set(Int(trashBytes), forKey: "trashNotifiedBytes")
        let text = trf("Thùng rác đang chiếm %@, nên dọn.", ByteFormat.string(trashBytes))
        notify(text, .warning, action: .openTrash)
        SystemNotifier.shared.post(title: "Vutidy", body: text, page: Page.trash.rawValue)
    }

    /// Đo ngay sau khi mở app rồi mỗi 10 phút (không đo mỗi 3 giây vì phải duyệt cả thùng rác).
    func startTrashWatch() {
        trashWatchTask?.cancel()
        trashWatchTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            while !Task.isCancelled {
                guard let self else { return }
                await self.refreshTrashSize()
                try? await Task.sleep(nanoseconds: 600 * 1_000_000_000)
            }
        }
    }
}
