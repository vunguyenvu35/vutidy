import SwiftUI
import AppKit
import CoreKit

@MainActor
extension AppState {
    // MARK: Bắt phím toàn app

    func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let consumed = MainActor.assumeIsolated { self.handleKey(event) }
            return consumed ? nil : event
        }
    }

    /// Trả về true nếu phím đã được xử lý (không chuyển tiếp cho view/menu).
    func handleKey(_ e: NSEvent) -> Bool {
        // 1. Đang ghi phím tắt mới trong Settings.
        if shortcuts.recordingID != nil {
            if e.keyCode == 53 { shortcuts.recordingID = nil; shortcuts.message = nil; return true }
            if let c = KeyCombo(event: e) { shortcuts.record(c) }
            return true
        }
        // 1b. Hộp thoại xác nhận: Esc hủy; Return chỉ xác nhận với hành động KHÔNG phá hủy.
        if let req = confirmRequest {
            if e.keyCode == 53 { confirmRequest = nil; return true }
            if (e.keyCode == 36 || e.keyCode == 76) && !req.destructive { let run = req.action; confirmRequest = nil; run() }
            return true
        }
        // 2. Mở nhanh: điều hướng bằng bàn phím, ô tìm kiếm vẫn nhận ký tự.
        if paletteOpen {
            switch e.keyCode {
            case 53: paletteOpen = false; return true
            case 125: movePalette(1); return true
            case 126: movePalette(-1); return true
            case 36, 76: runPaletteSelection(); return true
            default: break
            }
        }
        // 3. Esc đóng Settings.
        if settingsOpen && e.keyCode == 53 { settingsOpen = false; return true }
        // 4. Phím tắt người dùng.
        guard let combo = KeyCombo(event: e), let action = shortcuts.action(for: combo) else { return false }
        if !e.isARepeat { run(action) }
        return true
    }

    func run(_ a: ShortcutAction) {
        if let p = a.page {
            section = p; paletteOpen = false; settingsOpen = false
            return
        }
        switch a.id {
        case "quickOpen": settingsOpen = false; paletteOpen.toggle()
        case "scanCurrent": rescanCurrent()
        case "toggleRealtime": setRealtime(!realtimeOn)
        case "openSettings": paletteOpen = false; settingsOpen = true
        default: break
        }
    }

    func rescanCurrent() {
        if let id = section.cleanupID { Task { await scan(id) } }
        else if section == .smartScan { Task { await runSmartScan() } }
        else if section == .malware { Task { await runMalwareCheck() } }
        else { toast = tr("Trang này không có thao tác quét.") }
    }

    func openSettings(_ page: SettingsPage) {
        settingsPage = page; paletteOpen = false; settingsOpen = true
        showMainWindow()
    }

    /// Đưa cửa sổ chính lên trước; nếu app đang chỉ chạy ở menu bar thì mở lại cửa sổ và icon Dock.
    func showMainWindow() {
        NSApp.setActivationPolicy(.regular)
        if !NSApp.windows.contains(where: { $0.canBecomeMain }) { openMainWindow?() }
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
    }

    // MARK: Mở nhanh

    var paletteItems: [PaletteItem] {
        let q = paletteQuery.trimmingCharacters(in: .whitespaces).lowercased()
        let all = shortcuts.actions.map { a in
            PaletteItem(id: a.id, title: a.page?.title ?? a.title, symbol: a.symbol, tint: a.page?.tint ?? Theme.Signal.base,
                        shortcut: shortcuts.combo(a).symbols, group: a.group.title, run: { [unowned self] in self.run(a) })
        }
        return q.isEmpty ? all : all.filter { $0.title.lowercased().contains(q) }
    }

    func movePalette(_ delta: Int) {
        let n = paletteItems.count
        guard n > 0 else { return }
        paletteIndex = max(0, min(n - 1, paletteIndex + delta))
    }

    func runPaletteSelection() {
        let items = paletteItems
        guard items.indices.contains(paletteIndex) else { return }
        let item = items[paletteIndex]
        paletteOpen = false
        item.run()
    }
}

@MainActor
extension AppState {
    /// Kiểm thử/chụp màn hình: VUTIDY_RENDER_POPOVER=<file.png> vẽ popover ra file rồi thoát (không cần bấm icon menu bar).
    /// ImageRenderer không vẽ được NSView/vật liệu mờ nên ảnh chỉ để kiểm tra bố cục, không phải bản chụp thật.
    func renderPopoverSnapshotIfRequested() {
        guard let path = ProcessInfo.processInfo.environment["VUTIDY_RENDER_POPOVER"] else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)   // đợi số liệu hệ thống đầu tiên
            let view = PopoverView().environmentObject(self).environmentObject(shortcuts).preferredColorScheme(.dark)
            let r = ImageRenderer(content: view)
            r.scale = 2
            if let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: path))
            }
            exit(0)
        }
    }
}
