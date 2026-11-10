import Foundation
import CoreKit

public struct MaintenanceTask: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let detail: String
    public let shell: String
    public let needsAdmin: Bool
}

public enum Maintenance {
    /// Chỉ giữ tác vụ còn có ý nghĩa (bỏ periodic scripts, repair permissions).
    public static var tasks: [MaintenanceTask] = [
        .init(id: "flush-dns", title: tr("Xóa DNS cache"), detail: tr("Hữu ích khi đổi DNS hoặc site không phân giải đúng."),
              shell: "dscacheutil -flushcache; killall -HUP mDNSResponder", needsAdmin: true),
        .init(id: "purge-ram", title: tr("Giải phóng RAM purgeable"), detail: tr("Hiệu quả hạn chế: macOS tự quản lý bộ nhớ. Chỉ nên dùng khi cần đo benchmark."),
              shell: "/usr/sbin/purge", needsAdmin: true),
        .init(id: "reindex-spotlight", title: tr("Lập chỉ mục lại Spotlight"), detail: tr("Chạy nền, có thể tốn pin vài giờ."),
              shell: "mdutil -E /", needsAdmin: true),
        .init(id: "thin-tm", title: tr("Dọn Time Machine local snapshot"), detail: tr("Thu hồi dung lượng purgeable do snapshot cục bộ."),
              shell: "tmutil thinlocalsnapshots / 100000000000 4", needsAdmin: true),
        .init(id: "rebuild-ls", title: tr("Dựng lại Launch Services"), detail: tr("Sửa menu 'Mở bằng' bị trùng hoặc sai."),
              shell: "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -kill -r -domain local -domain system -domain user",
              needsAdmin: false),
        .init(id: "verify-disk", title: tr("Kiểm tra ổ đĩa (chỉ verify)"), detail: tr("Không sửa gì, chỉ báo cáo lỗi."),
              shell: "diskutil verifyVolume /", needsAdmin: false),
    ]

    public static func run(_ task: MaintenanceTask) async -> ProcessResult {
        task.needsAdmin ? await ProcessRunner.runPrivileged(shell: task.shell)
                        : await ProcessRunner.run(["/bin/sh", "-c", task.shell])
    }

    public static func localSnapshots() async -> [String] {
        let r = await ProcessRunner.run(["tmutil", "listlocalsnapshots", "/"])
        return r.stdout.split(separator: "\n").map(String.init).filter { $0.contains("com.apple.TimeMachine") }
    }
}
