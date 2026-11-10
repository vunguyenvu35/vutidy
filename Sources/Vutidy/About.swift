import AppKit
import CoreKit

/// Hộp thoại "Giới thiệu Vutidy" chuẩn của macOS (icon, phiên bản, mô tả, bản quyền).
enum AboutPanel {
    static func show() {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let build = info?["CFBundleVersion"] as? String ?? "dev"

        let para = NSMutableParagraphStyle(); para.alignment = .center; para.lineSpacing = 2
        let body: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: para]
        let credits = NSMutableAttributedString(string: tr("Dọn dẹp và tối ưu Mac an toàn: mọi thao tác đều có xem trước và hoàn tác được.\nKhông thu thập dữ liệu, mọi xử lý diễn ra trên máy của bạn.") + "\n\n", attributes: body)
        credits.append(NSAttributedString(string: "MIT License · Vũ Nguyễn Vũ", attributes: body))

        var options: [NSApplication.AboutPanelOptionKey: Any] = [
            .applicationName: "Vutidy",
            .applicationVersion: version,
            .version: build,
            .credits: credits,
            NSApplication.AboutPanelOptionKey(rawValue: "Copyright"): "© 2026 Vũ Nguyễn Vũ",
        ]
        if let icon = NSImage(named: "AppIcon") { options[.applicationIcon] = icon }
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: options)
    }
}
