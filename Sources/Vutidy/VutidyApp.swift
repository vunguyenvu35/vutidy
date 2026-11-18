import SwiftUI
import AppKit
import CoreKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// true khi người dùng chọn thoát hẳn (popover → Thoát, ⌥⌘Q) hoặc hệ thống tắt máy/đăng xuất.
    static var allowTerminate = false

    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(.regular)   // cần khi chạy bằng `swift run` (không có .app bundle)
        // Chạy trần (swift run) thì Dock hiện icon "exec" mặc định → gán icon từ resource.
        if let url = Bundle.module.url(forResource: "appicon", withExtension: "png", subdirectory: "Resources"),
           let img = NSImage(contentsOf: url) { NSApplication.shared.applicationIconImage = img }
        NSApp.activate(ignoringOtherApps: true)

        // Đóng cửa sổ cuối cùng → ẩn icon Dock, app tiếp tục chạy ở thanh menu.
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { _ in
            DispatchQueue.main.async {
                if !NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeMain }) { NSApp.setActivationPolicy(.accessory) }
            }
        }
        // Tắt máy / khởi động lại / đăng xuất phải được phép thoát, nếu không sẽ chặn hệ thống.
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willPowerOffNotification, object: nil, queue: .main) { _ in
            AppDelegate.allowTerminate = true
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { true }

    /// ⌘Q / Dock → Quit: chỉ đóng cửa sổ, giữ tiến trình để icon menu bar còn theo dõi hệ thống.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if AppDelegate.allowTerminate { return .terminateNow }
        AppDelegate.hideToMenuBar()
        return .terminateCancel
    }

    /// Ẩn cửa sổ popover của MenuBarExtra (lớp riêng của SwiftUI, không thể trở thành cửa sổ chính).
    static func closeMenuBarPopover() {
        for w in NSApp.windows where w.isVisible && !w.canBecomeMain && String(describing: type(of: w)).contains("MenuBarExtra") {
            w.orderOut(nil)
        }
    }

    static func hideToMenuBar() {
        NSApp.windows.filter { $0.canBecomeMain && $0.isVisible }.forEach { $0.close() }
        NSApp.setActivationPolicy(.accessory)
    }

    /// Mở lại chính app rồi thoát tiến trình hiện tại — cần để macOS áp dụng quyền Full Disk Access mới cấp.
    static func relaunch() {
        let path = Bundle.main.bundleURL.path
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 0.7; /usr/bin/open -n \"$1\"", "sh", path]
        try? p.run()
        quitCompletely()
    }

    static var canRelaunch: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    /// Ứng dụng đã khởi chạy tiến trình này (ví dụ "Visual Studio Code", "Terminal") khi chạy `swift run`.
    /// macOS tính quyền riêng tư theo ứng dụng "chịu trách nhiệm" đó, không theo file thực thi.
    static func hostAppName() -> String? {
        var pid = getppid()
        for _ in 0..<12 {
            if pid <= 1 { return nil }
            if let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular { return app.localizedName }
            var info = kinfo_proc()
            var size = MemoryLayout<kinfo_proc>.stride
            var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
            guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { return nil }
            pid = info.kp_eproc.e_ppid
        }
        return nil
    }

    /// Lời nhắc khi đang chạy file trần: nêu đúng ứng dụng cần được cấp Full Disk Access.
    static var unbundledFDAMessage: String {
        if let host = hostAppName() {
            return trf("Đang chạy bản chưa đóng gói (swift run) từ “%@”, nên macOS tính quyền theo “%@”. Hãy bật Full Disk Access cho “%@” rồi khởi động lại nó, hoặc chạy bản .app: scripts/dev.sh", host, host, host)
        }
        return tr("Đang chạy bản chưa đóng gói (swift run), nên quyền cấp cho Vutidy.app không áp dụng. Hãy mở bản .app: scripts/make-app.sh --open")
    }


    static func quitCompletely() {
        allowTerminate = true
        NSApp.terminate(nil)
    }
}

@main
struct VutidyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var state = AppState()

    var body: some Scene {
        // Window (một cửa sổ duy nhất) để mở lại từ menu bar bằng openWindow(id:).
        Window("Vutidy", id: "main") {
            RootView()
                .environmentObject(state)
                .environmentObject(state.shortcuts)
                .frame(minWidth: 940, minHeight: 640)
                .preferredColorScheme(.dark)

        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1180, height: 780)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button(tr("Giới thiệu Vutidy")) { AboutPanel.show() }
                Button(tr("Kiểm tra cập nhật…")) { state.openSettings(.general); Task { await state.checkForUpdates() } }
            }
            // View: bỏ "Hiện thanh bên/thanh công cụ" mặc định (app tự dựng sidebar), thay bằng điều hướng các trang.
            CommandGroup(replacing: .toolbar) {}
            CommandGroup(replacing: .sidebar) {
                Button(tr("Tìm tính năng…")) { state.paletteOpen = true; state.showMainWindow() }
                Divider()
                ForEach(Page.groups, id: \.0) { name, pages in
                    // Nhóm không tên (Smart Scan) không có tiêu đề: một Section rỗng chừa khoảng trắng trong menu.
                    if name.isEmpty {
                        ForEach(pages) { p in Button(p.title) { state.section = p; state.settingsOpen = false; state.showMainWindow() } }
                    } else {
                        Section(name) {
                            ForEach(pages) { p in Button(p.title) { state.section = p; state.settingsOpen = false; state.showMainWindow() } }
                        }
                    }
                }
            }
            CommandGroup(replacing: .appSettings) {
                Button(tr("Cài đặt…")) { state.openSettings(.general) }
            }
            CommandGroup(replacing: .appTermination) {
                Button(tr("Đóng về thanh menu")) { AppDelegate.hideToMenuBar() }.keyboardShortcut("q")
                Button(tr("Thoát hẳn Vutidy")) { AppDelegate.quitCompletely() }.keyboardShortcut("q", modifiers: [.command, .option])
            }
            CommandGroup(replacing: .help) {
                Button(tr("Kiểm tra cập nhật…")) { state.openSettings(.general); Task { await state.checkForUpdates() } }
                Divider()
                Button(tr("Phím tắt")) { state.openSettings(.shortcuts); state.showMainWindow() }
                Button(tr("Ủng hộ Vutidy")) { state.openSettings(.support); state.showMainWindow() }
            }
        }

        MenuBarExtra("Vutidy", systemImage: "sparkles") {
            PopoverView().environmentObject(state).environmentObject(state.shortcuts).preferredColorScheme(.dark).id("\(state.language)|\(state.typographyKey)")
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - Cửa sổ: kéo bằng nền, double-click vùng tiêu đề để phóng to/thu nhỏ

/// Cấu hình NSWindow: kéo được bằng vùng nền như CleanMyMac, và báo cho UI biết tâm của 3 nút đèn giao thông
/// (tính từ mép trên cửa sổ) để căn thẳng hàng logo với chúng.
struct WindowConfigurator: NSViewRepresentable {
    var onTitleBarCenter: (CGFloat) -> Void = { _ in }
    var onFullScreen: (Bool) -> Void = { _ in }

    final class Probe: NSView {
        var onCenter: (CGFloat) -> Void = { _ in }
        var onFullScreen: (Bool) -> Void = { _ in }
        private var observers: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.isMovableByWindowBackground = true
            window.titlebarAppearsTransparent = true
            // Cách chuẩn của macOS để có thanh tiêu đề cao (như Finder/GitHub): gắn toolbar rỗng kiểu unified.
            // Hệ thống tự căn 3 nút đèn giao thông ở giữa chiều cao đó, giữ nguyên kích thước gốc.
            if window.toolbar == nil {
                let tb = NSToolbar(identifier: "VutidyToolbar")
                tb.showsBaselineSeparator = false
                window.toolbar = tb
            }
            window.toolbarStyle = .unified
            window.titlebarSeparatorStyle = .none
            report()
            DispatchQueue.main.async { [weak self] in self?.report() }
            for name in [NSWindow.didResizeNotification, NSWindow.didEndLiveResizeNotification, NSWindow.didExitFullScreenNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in self?.report() })
            }
            // Toolbar rỗng chỉ để có thanh tiêu đề cao khi cửa sổ thường. Ở full screen macOS giữ nó thành một dải xám riêng
            // và đẩy nội dung xuống → ẩn khi vào full screen, hiện lại khi thoát.
            applyFullScreen(window.styleMask.contains(.fullScreen))
            let nc = NotificationCenter.default
            observers.append(nc.addObserver(forName: NSWindow.willEnterFullScreenNotification, object: window, queue: .main) { [weak self] _ in self?.applyFullScreen(true) })
            observers.append(nc.addObserver(forName: NSWindow.didEnterFullScreenNotification, object: window, queue: .main) { [weak self] _ in self?.applyFullScreen(true) })
            observers.append(nc.addObserver(forName: NSWindow.willExitFullScreenNotification, object: window, queue: .main) { [weak self] _ in self?.applyFullScreen(false) })
        }

        func applyFullScreen(_ on: Bool) {
            window?.toolbar?.isVisible = !on
            onFullScreen(on)
        }

        func report() {
            guard let window, let close = window.standardWindowButton(.closeButton) else { return }
            // Không can thiệp vị trí/kích thước nút: macOS tự căn giữa chúng trong thanh tiêu đề (xem toolbar ở trên).
            let fromTop = window.frame.height - close.convert(close.bounds, to: nil).midY
            if fromTop > 4 && fromTop < 70 { onCenter(fromTop) }
        }
    }

    func makeNSView(context: Context) -> Probe { let p = Probe(); p.onCenter = onTitleBarCenter; p.onFullScreen = onFullScreen; return p }
    func updateNSView(_ nsView: Probe, context: Context) { nsView.onCenter = onTitleBarCenter; nsView.onFullScreen = onFullScreen }
}

/// Vùng tiêu đề tự dựng (vì dùng hiddenTitleBar): kéo để di chuyển, double-click theo cài đặt hệ thống.
struct TitleBarArea: NSViewRepresentable {
    final class Handle: NSView {
        override var mouseDownCanMoveWindow: Bool { false }
        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            if event.clickCount == 2 {
                let action = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["AppleActionOnDoubleClick"] as? String
                switch action {
                case "Minimize": window.performMiniaturize(nil)
                case "None": break
                default: window.zoom(nil)              // "Maximize" hoặc mặc định (zoom() không cần nút xanh đang bật)
                }
            } else {
                window.performDrag(with: event)
            }
        }
    }
    func makeNSView(context: Context) -> NSView { Handle() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
