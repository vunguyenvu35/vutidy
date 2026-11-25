import AppKit
import CoreKit

/// Menu chuột phải (hoặc Control + bấm) trên biểu tượng Vutidy ở thanh menu. Cùng các mục với nút bánh răng ở chân popover.
/// SwiftUI `MenuBarExtra` kiểu .window không có menu chuột phải, nên bắt sự kiện chuột phải của cửa sổ status item và tự hiện NSMenu.
@MainActor
final class StatusItemMenu: NSObject {
    static let shared = StatusItemMenu()
    weak var state: AppState?
    private var monitor: Any?

    func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, let window = event.window, String(describing: type(of: window)).contains("StatusBar"),
                      event.type == .rightMouseDown || event.modifierFlags.contains(.control),
                      let view = window.contentView else { return event }
                AppDelegate.closeMenuBarPopover()   // đang mở popover thì đóng trước, menu thay chỗ nó
                NSMenu.popUpContextMenu(self.makeMenu(), with: event, for: view)
                return nil                           // nuốt sự kiện để popover không bật lên
            }
        }
    }

    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        let about = item(tr("Giới thiệu Vutidy"), #selector(showAbout))
        about.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)
        menu.addItem(about)
        menu.addItem(item(tr("Góp ý…"), #selector(sendFeedback)))
        menu.addItem(.separator())
        menu.addItem(item(tr("Cài đặt…"), #selector(openSettings), key: ","))
        menu.addItem(.separator())
        menu.addItem(item(tr("Thoát hẳn Vutidy"), #selector(quitCompletely)))
        return menu
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = self
        return i
    }

    @objc private func showAbout() { NSApp.activate(ignoringOtherApps: true); AboutPanel.show() }
    @objc private func sendFeedback() {
        if let u = URL(string: "https://github.com/vunguyenvu35/vutidy/issues") { NSWorkspace.shared.open(u) }
    }
    @objc private func openSettings() { state?.openSettings(.general) }
    @objc private func quitCompletely() { AppDelegate.quitCompletely() }
}
