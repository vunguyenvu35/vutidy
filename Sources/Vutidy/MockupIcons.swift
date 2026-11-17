import SwiftUI
import CoreKit

/// Bộ icon của mockup "Smart Scan": nét thuần trên lưới 24×24 (không chấm nhấn tô đặc), dùng nguyên đường vẽ SVG.
/// Các icon này thay cho phiên bản cũ của cùng tên trong `VIcon`; phần còn lại của bộ icon (danh mục, giao diện) giữ nguyên.
enum MockupIcons {
    private static func circle(_ cx: Double, _ cy: Double, _ r: Double) -> String {
        "M\(cx - r) \(cy)a\(r) \(r) 0 1 0 \(2 * r) 0a\(r) \(r) 0 1 0 \(-2 * r) 0z"
    }
    private static func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ r: Double) -> String {
        "M\(x + r) \(y)h\(w - 2 * r)a\(r) \(r) 0 0 1 \(r) \(r)v\(h - 2 * r)a\(r) \(r) 0 0 1 \(-r) \(r)"
        + "h\(-(w - 2 * r))a\(r) \(r) 0 0 1 \(-r) \(-r)v\(-(h - 2 * r))a\(r) \(r) 0 0 1 \(r) \(-r)z"
    }

    static let d: [VIcon: [String]] = [
        .smartScan: ["M12 3l1.8 5.2L19 10l-5.2 1.8L12 17l-1.8-5.2L5 10l5.2-1.8z"],
        .systemJunk: [rect(3, 12, 18, 8, 2), "M5 12l2-7h10l2 7"],
        .devJunk: ["M8 8l-4 4 4 4M16 8l4 4-4 4"],
        .trash: ["M4 7h16M9 7V4h6v3M6 7l1 13h10l1-13"],
        .privacy: ["M2 12s4-7 10-7 10 7 10 7-4 7-10 7S2 12 2 12z", circle(12, 12, 3)],
        .protection: ["M12 3l8 3v6c0 5-3.5 8-8 9-4.5-1-8-4-8-9V6z"],
        .malware: [rect(8, 7, 8, 12, 4), "M12 7V4M4 13h4M16 13h4M5 8l3 2M19 8l-3 2M5 19l3-2M19 19l-3-2"],
        .optimization: ["M4 17a8 8 0 1116 0", "M12 17l4-5"],
        .maintenance: ["M4 7h10M18 7h2M4 17h4M12 17h8", circle(16, 7, 2), circle(10, 17, 2)],
        .uninstaller: [rect(4, 4, 16, 16, 3), "M9 9l6 6M15 9l-6 6"],
        .updater: [circle(12, 12, 9), "M12 7v9M8 12l4 4 4-4"],
        .spaceLens: ["M12 3a9 9 0 109 9h-9z", "M15 3.5A9 9 0 0120.5 9H15z"],
        .largeFiles: ["M6 3h8l4 4v14H6z", "M14 3v4h4"],
        .duplicates: [rect(8, 8, 12, 12, 2), "M16 8V4H4v12h4"],
        .cloud: ["M7 18h10a4 4 0 000-8 6 6 0 00-11.5 1.5A3.5 3.5 0 007 18z"],
        .quarantine: [rect(3, 4, 18, 5, 1), "M5 9v10h14V9M10 13h4"],
        .gear: [circle(12, 12, 3), "M12 2v3M12 19v3M2 12h3M19 12h3M4.9 4.9l2.1 2.1M17 17l2.1 2.1M4.9 19.1L7 17M17 7l2.1-2.1"],
        .search: [circle(11, 11, 7), "M20 20l-4-4"],
    ]

    static func path(for icon: VIcon, size: CGFloat) -> Path? {
        guard let parts = d[icon] else { return nil }
        let k = size / 24
        var p = Path()
        for part in parts { p.addPath(Path(SVGPathParser.path(part, scale: k))) }
        return p
    }
}
