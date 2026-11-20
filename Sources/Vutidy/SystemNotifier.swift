import AppKit
import UserNotifications

/// Thông báo hệ thống của macOS. Chỉ hoạt động khi chạy từ .app (bản `swift run` không có bundle nên bỏ qua).
/// Bấm vào thông báo mở đúng trang trong Vutidy.
@MainActor
final class SystemNotifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = SystemNotifier()
    /// Gán bởi AppState: nhận rawValue của trang cần mở.
    var open: ((String) -> Void)?
    private var asked = false

    private var available: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    func post(title: String, body: String, page: String) {
        guard available else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let send = {
            let c = UNMutableNotificationContent()
            c.title = title; c.body = body; c.userInfo = ["page": page]
            center.add(UNNotificationRequest(identifier: "vutidy.\(page)", content: c, trigger: nil))
        }
        center.getNotificationSettings { s in
            switch s.authorizationStatus {
            case .authorized, .provisional: send()
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound]) { ok, _ in if ok { send() } }
            default: break
            }
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let page = response.notification.request.content.userInfo["page"] as? String
        Task { @MainActor in if let page { SystemNotifier.shared.open?(page) } }
        completionHandler()
    }

    /// Hiện cả khi Vutidy đang ở phía trước.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
