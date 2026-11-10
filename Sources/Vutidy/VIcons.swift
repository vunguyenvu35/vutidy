import SwiftUI
import CoreKit

/// Bộ icon riêng của Vutidy, vẽ trên lưới 24×24: nét 1.8 bo tròn + một chi tiết nhấn tô đặc
/// (cùng ngôn ngữ với logo: nét bo + khối nhỏ). Không phụ thuộc SF Symbols.
enum VIcon: String, CaseIterable {
    // Trang chính
    case smartScan, systemJunk, devJunk, trash, privacy, protection, optimization, maintenance
    case uninstaller, updater, spaceLens, largeFiles, duplicates, cloud, quarantine, malware
    // Danh mục & giao diện
    case box, braces, code, hammer, mug, chip, ram, doc, mail, photo, globe, drive, clock, warn
    case sliders, folder, heart, gear, command, search, power, wifi, check, lock, bolt
}

private struct Pen {
    var p = Path()
    let k: CGFloat
    init(_ k: CGFloat) { self.k = k }
    private func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * k, y: y * k) }
    mutating func M(_ x: CGFloat, _ y: CGFloat) { p.move(to: pt(x, y)) }
    mutating func L(_ x: CGFloat, _ y: CGFloat) { p.addLine(to: pt(x, y)) }
    mutating func C(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat, _ x: CGFloat, _ y: CGFloat) {
        p.addCurve(to: pt(x, y), control1: pt(x1, y1), control2: pt(x2, y2))
    }
    mutating func Z() { p.closeSubpath() }
    mutating func RR(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) {
        p.addRoundedRect(in: CGRect(x: x * k, y: y * k, width: w * k, height: h * k), cornerSize: CGSize(width: r * k, height: r * k), style: .continuous)
    }
    mutating func O(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) { E(cx, cy, r, r) }
    mutating func E(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat) {
        p.addEllipse(in: CGRect(x: (cx - rx) * k, y: (cy - ry) * k, width: rx * 2 * k, height: ry * 2 * k))
    }
    /// Cung tròn lấy mẫu (góc độ, chiều kim đồng hồ trên màn hình, 0° = hướng phải).
    mutating func arc(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, _ a0: Double, _ a1: Double, move: Bool = true, close: Bool = false) {
        let steps = max(2, Int(abs(a1 - a0) / 5))
        for i in 0...steps {
            let a = (a0 + (a1 - a0) * Double(i) / Double(steps)) * .pi / 180
            let x = cx + r * CGFloat(cos(a)), y = cy + r * CGFloat(sin(a))
            if i == 0 && move { M(x, y) } else { L(x, y) }
        }
        if close { Z() }
    }
}

extension VIcon {
    /// (nét, mảng tô) trong hệ tọa độ pixel của khung `size`.
    func paths(size: CGFloat) -> (stroke: Path, fill: Path) {
        let k = size / 24
        var s = Pen(k), f = Pen(k)
        switch self {
        case .smartScan:
            s.M(11, 3.5); s.C(11.6, 8.3, 14.7, 11.4, 19.5, 12); s.C(14.7, 12.6, 11.6, 15.7, 11, 20.5)
            s.C(10.4, 15.7, 7.3, 12.6, 2.5, 12); s.C(7.3, 11.4, 10.4, 8.3, 11, 3.5); s.Z()
            f.O(19, 5, 1.7); f.O(5.5, 19, 1.2)
        case .systemJunk:
            s.M(3.5, 13.5); s.L(6.3, 5.8); s.C(6.6, 5.1, 7.2, 4.8, 7.9, 4.8); s.L(16.1, 4.8); s.C(16.8, 4.8, 17.4, 5.1, 17.7, 5.8); s.L(20.5, 13.5)
            s.RR(3.5, 13.5, 17, 6.5, 2.6)
            s.M(3.8, 13.5); s.L(8.3, 13.5); s.L(9.6, 15.8); s.L(14.4, 15.8); s.L(15.7, 13.5); s.L(20.2, 13.5)
            f.RR(9.2, 8, 5.6, 2.4, 1.2)
        case .devJunk, .code:
            s.M(8, 7); s.L(3, 12); s.L(8, 17); s.M(16, 7); s.L(21, 12); s.L(16, 17)
            f.RR(10.6, 11, 2.8, 2, 1)  // dấu nhấn: con trỏ
            s.M(13.4, 5.2); s.L(10.6, 18.8)
        case .trash:
            s.M(4, 7); s.L(20, 7); s.M(9, 7); s.L(9, 4.6); s.L(15, 4.6); s.L(15, 7)
            s.M(6.2, 7); s.L(7, 19); s.C(7.1, 20.1, 7.9, 21, 9, 21); s.L(15, 21); s.C(16.1, 21, 16.9, 20.1, 17, 19); s.L(17.8, 7)
            f.RR(9.2, 10.6, 1.8, 6.4, 0.9); f.RR(13, 10.6, 1.8, 6.4, 0.9)
        case .privacy:
            s.M(2.5, 12); s.C(5, 7.6, 8.3, 5.5, 12, 5.5); s.C(15.7, 5.5, 19, 7.6, 21.5, 12)
            s.C(19, 16.4, 15.7, 18.5, 12, 18.5); s.C(8.3, 18.5, 5, 16.4, 2.5, 12); s.Z()
            s.O(12, 12, 3.4); f.O(12, 12, 1.4)
        case .protection:
            s.M(12, 3); s.L(19.5, 6); s.L(19.5, 11.5); s.C(19.5, 16, 16.6, 19.4, 12, 21); s.C(7.4, 19.4, 4.5, 16, 4.5, 11.5); s.L(4.5, 6); s.Z()
            s.M(8.6, 12.2); s.L(11, 14.6); s.L(15.5, 9.6)
        case .malware:
            s.RR(7.6, 8.4, 8.8, 11.6, 4.4); s.O(12, 6.2, 2.3)
            s.M(10.6, 4.3); s.L(9, 2.7); s.M(13.4, 4.3); s.L(15, 2.7)
            s.M(7.8, 11); s.L(4.2, 9.4); s.M(7.6, 14.4); s.L(3.6, 14.4); s.M(7.8, 17.6); s.L(4.4, 19.6)
            s.M(16.2, 11); s.L(19.8, 9.4); s.M(16.4, 14.4); s.L(20.4, 14.4); s.M(16.2, 17.6); s.L(19.6, 19.6)
            f.RR(11.2, 10.6, 1.6, 7.8, 0.8)
        case .optimization:
            s.arc(12, 14, 8.5, 150, 390)
            s.M(12, 14); s.L(16.2, 9.2)
            f.O(12, 14, 1.9)
            f.RR(5.2, 9.2, 1.6, 1.6, 0.8); f.RR(11.2, 4.6, 1.6, 1.6, 0.8); f.RR(17.2, 9.2, 1.6, 1.6, 0.8)
        case .maintenance, .sliders:
            s.M(3.5, 8); s.L(20.5, 8); s.M(3.5, 16); s.L(20.5, 16)
            f.O(9, 8, 2.7); f.O(15, 16, 2.7)
        case .uninstaller:
            s.RR(3.5, 4.5, 17, 15, 3.6); s.M(3.5, 9.2); s.L(20.5, 9.2)
            s.M(9.6, 12.6); s.L(14.4, 17.2); s.M(14.4, 12.6); s.L(9.6, 17.2)
            f.O(6.4, 6.9, 0.9); f.O(9, 6.9, 0.9)
        case .updater:
            s.O(12, 12, 8.5); s.M(12, 7.6); s.L(12, 15.4); s.M(8.6, 12.4); s.L(12, 15.8); s.L(15.4, 12.4)
            f.RR(9.6, 17.4, 4.8, 1.6, 0.8)
        case .spaceLens:
            s.O(12, 12, 8.5); s.M(12, 12); s.L(12, 3.5); s.M(12, 12); s.L(19.36, 16.25)
            f.M(12, 12); f.arc(12, 12, 8.5, 270, 390, move: false); f.Z()
        case .largeFiles:
            s.M(6.5, 3.5); s.L(13.6, 3.5); s.L(18.5, 8.4); s.L(18.5, 19); s.C(18.5, 19.9, 17.9, 20.5, 17, 20.5); s.L(6.5, 20.5)
            s.C(5.6, 20.5, 5, 19.9, 5, 19); s.L(5, 5); s.C(5, 4.1, 5.6, 3.5, 6.5, 3.5); s.Z()
            s.M(13.6, 3.5); s.L(13.6, 8.4); s.L(18.5, 8.4)
            s.O(11.5, 14.8, 3); s.M(11.5, 13.1); s.L(11.5, 14.8); s.L(12.8, 15.6)
        case .duplicates:
            s.RR(8.5, 3.5, 12, 12, 3); s.RR(3.5, 8.5, 12, 12, 3)
            f.RR(7, 13.4, 5, 2.2, 1.1)
        case .cloud:
            s.M(7.5, 19); s.C(4.8, 19, 3, 17.1, 3, 14.7); s.C(3, 12.5, 4.6, 10.8, 6.8, 10.5); s.C(7.4, 7.3, 9.7, 5.5, 12.5, 5.5)
            s.C(15.5, 5.5, 17.7, 7.6, 18.1, 10.4); s.C(20.1, 10.7, 21.5, 12.3, 21.5, 14.4); s.C(21.5, 16.9, 19.6, 19, 17.1, 19); s.Z()
            f.RR(10.9, 11.4, 2.2, 5.6, 1.1)
        case .quarantine:
            s.RR(3.5, 4.5, 17, 5, 2); s.M(5.5, 9.5); s.L(5.5, 17.5); s.C(5.5, 18.7, 6.3, 19.5, 7.5, 19.5); s.L(16.5, 19.5)
            s.C(17.7, 19.5, 18.5, 18.7, 18.5, 17.5); s.L(18.5, 9.5)
            f.RR(9.4, 12.6, 5.2, 2.4, 1.2)
        case .box:
            s.M(12, 3); s.L(19.8, 7.4); s.L(19.8, 16.6); s.L(12, 21); s.L(4.2, 16.6); s.L(4.2, 7.4); s.Z()
            s.M(4.2, 7.4); s.L(12, 12); s.L(19.8, 7.4); s.M(12, 12); s.L(12, 21)
            f.O(12, 12, 1.3)
        case .braces:
            s.M(9.5, 4); s.C(7.6, 4, 7, 5, 7, 6.8); s.L(7, 9.2); s.C(7, 10.6, 6, 11.7, 4.5, 12); s.C(6, 12.3, 7, 13.4, 7, 14.8); s.L(7, 17.2); s.C(7, 19, 7.6, 20, 9.5, 20)
            s.M(14.5, 4); s.C(16.4, 4, 17, 5, 17, 6.8); s.L(17, 9.2); s.C(17, 10.6, 18, 11.7, 19.5, 12); s.C(18, 12.3, 17, 13.4, 17, 14.8); s.L(17, 17.2); s.C(17, 19, 16.4, 20, 14.5, 20)
            f.O(12, 12, 1.5)
        case .hammer:
            s.M(14.4, 3.8); s.L(20.2, 9.6); s.L(17.4, 12.4); s.L(11.6, 6.6); s.Z()
            s.M(11, 9.4); s.L(5, 15.4); s.C(4.1, 16.3, 4.1, 17.7, 5, 18.6); s.L(5.4, 19); s.C(6.3, 19.9, 7.7, 19.9, 8.6, 19); s.L(14.6, 13)
            f.O(6.9, 17.1, 0.9)
        case .mug:
            s.RR(4.5, 8.5, 11.5, 11, 3.2)
            s.arc(16, 12.2, 2.8, -90, 90)
            s.M(8, 3.6); s.L(8, 5.8); s.M(12, 3.6); s.L(12, 5.8)
            f.RR(7.6, 12.6, 4.8, 2.2, 1.1)
        case .chip:
            s.RR(6.5, 6.5, 11, 11, 2.6)
            for x in [9.5, 14.5] as [CGFloat] { s.M(x, 3.5); s.L(x, 6.5); s.M(x, 17.5); s.L(x, 20.5) }
            for y in [9.5, 14.5] as [CGFloat] { s.M(3.5, y); s.L(6.5, y); s.M(17.5, y); s.L(20.5, y) }
            f.RR(10, 10, 4, 4, 1.2)
        case .ram:
            s.RR(3, 7.5, 18, 8.5, 2); s.M(7, 16); s.L(7, 19); s.M(12, 16); s.L(12, 19); s.M(17, 16); s.L(17, 19)
            f.RR(6, 10.4, 3, 2.6, 0.8); f.RR(10.5, 10.4, 3, 2.6, 0.8); f.RR(15, 10.4, 3, 2.6, 0.8)
        case .doc:
            s.M(6.5, 3.5); s.L(13.6, 3.5); s.L(18.5, 8.4); s.L(18.5, 19); s.C(18.5, 19.9, 17.9, 20.5, 17, 20.5); s.L(6.5, 20.5)
            s.C(5.6, 20.5, 5, 19.9, 5, 19); s.L(5, 5); s.C(5, 4.1, 5.6, 3.5, 6.5, 3.5); s.Z()
            s.M(13.6, 3.5); s.L(13.6, 8.4); s.L(18.5, 8.4)
            s.M(8.4, 12.6); s.L(15.2, 12.6); s.M(8.4, 16); s.L(12.6, 16)
        case .mail:
            s.RR(3.5, 5.5, 17, 13, 3); s.M(4.6, 7.4); s.L(12, 13.2); s.L(19.4, 7.4)
            f.O(12, 13.2, 1)
        case .photo:
            s.RR(3.5, 4.5, 17, 15, 3.4); s.M(4.5, 17); s.L(9.6, 12); s.L(13.2, 15.4); s.L(15.8, 13.2); s.L(19.5, 17)
            f.O(9, 9.2, 1.7)
        case .globe:
            s.O(12, 12, 8.5); s.M(3.5, 12); s.L(20.5, 12); s.E(12, 12, 3.7, 8.5)
            f.O(12, 12, 1.2)
        case .drive:
            s.M(4.4, 13.4); s.L(6.9, 6.7); s.C(7.1, 6.2, 7.6, 5.8, 8.2, 5.8); s.L(15.8, 5.8); s.C(16.4, 5.8, 16.9, 6.2, 17.1, 6.7); s.L(19.6, 13.4)
            s.RR(3.5, 13.4, 17, 6.2, 2.6)
            f.O(16.6, 16.5, 1.1); s.M(6.6, 16.5); s.L(11.5, 16.5)
        case .clock:
            s.O(12, 12, 8.5); s.M(12, 7); s.L(12, 12); s.L(15.4, 14)
            f.O(12, 12, 1.2)
        case .warn:
            s.M(12, 3.8); s.L(21, 19.6); s.C(21.3, 20.2, 20.9, 20.8, 20.2, 20.8); s.L(3.8, 20.8); s.C(3.1, 20.8, 2.7, 20.2, 3, 19.6); s.Z()
            s.M(12, 9.6); s.L(12, 14.2); f.O(12, 17.4, 1.1)
        case .folder:
            s.M(3.5, 8.5); s.C(3.5, 7.4, 4.4, 6.5, 5.5, 6.5); s.L(9.4, 6.5); s.L(11.4, 8.6); s.L(18.5, 8.6)
            s.C(19.6, 8.6, 20.5, 9.5, 20.5, 10.6); s.L(20.5, 17); s.C(20.5, 18.1, 19.6, 19, 18.5, 19); s.L(5.5, 19)
            s.C(4.4, 19, 3.5, 18.1, 3.5, 17); s.Z()
            f.RR(7.2, 12.4, 4.6, 2.2, 1.1)
        case .heart:
            s.M(12, 19.6); s.C(6, 15.4, 3.5, 12.3, 3.5, 9); s.C(3.5, 6.5, 5.4, 4.6, 7.7, 4.6); s.C(9.5, 4.6, 11.1, 5.6, 12, 7.2)
            s.C(12.9, 5.6, 14.5, 4.6, 16.3, 4.6); s.C(18.6, 4.6, 20.5, 6.5, 20.5, 9); s.C(20.5, 12.3, 18, 15.4, 12, 19.6); s.Z()
            f.O(8, 8.8, 1.1)
        case .gear:
            for kIdx in 0..<8 {
                let a = Double(kIdx) * 45
                let pts: [(Double, CGFloat)] = [(a - 11, 6.8), (a - 7, 9.2), (a + 7, 9.2), (a + 11, 6.8)]
                for (j, q) in pts.enumerated() {
                    let rad = q.0 * .pi / 180
                    let x = 12 + q.1 * CGFloat(cos(rad)), y = 12 + q.1 * CGFloat(sin(rad))
                    if kIdx == 0 && j == 0 { s.M(x, y) } else { s.L(x, y) }
                }
            }
            s.Z(); f.O(12, 12, 2.1)
        case .command:
            s.M(9, 9); s.L(15, 9); s.L(15, 15); s.L(9, 15); s.Z()
            for (cx, cy) in [(6.6, 6.6), (17.4, 6.6), (6.6, 17.4), (17.4, 17.4)] as [(CGFloat, CGFloat)] { s.O(cx, cy, 2.4) }
            f.O(12, 12, 1)
        case .search:
            s.O(10.5, 10.5, 6.3); s.M(15.2, 15.2); s.L(20.2, 20.2)
            f.O(10.5, 10.5, 1.4)
        case .power:
            s.arc(12, 13, 7.6, 305, 595); s.M(12, 3.8); s.L(12, 11.4)
            f.O(12, 13.4, 1.2)
        case .wifi:
            s.arc(12, 18, 12.4, 233, 307); s.arc(12, 18, 8, 227, 313); s.arc(12, 18, 3.8, 220, 320)
            f.O(12, 18.2, 1.6)
        case .check:
            s.O(12, 12, 8.5); s.M(8, 12.4); s.L(11, 15.4); s.L(16.2, 9.4)
        case .lock:
            s.RR(5.5, 10.5, 13, 9.5, 2.6); s.M(8.5, 10.5); s.L(8.5, 8); s.arc(12, 8, 3.5, 180, 360, move: false)
            s.L(15.5, 10.5); f.O(12, 15, 1.4)
        case .bolt:
            s.M(13.4, 3.5); s.L(5.5, 13.4); s.L(11.2, 13.4); s.L(10.2, 20.5); s.L(18.5, 10.2); s.L(12.6, 10.2); s.Z()
        }
        return (s.p, f.p)
    }
}

struct VIconView: View {
    let icon: VIcon
    var stroke: Color
    var fill: Color
    var lineWidth: CGFloat = 1.8
    var body: some View {
        Canvas { ctx, size in
            let side = min(size.width, size.height)
            let (s, f) = icon.paths(size: side)
            let off = CGSize(width: (size.width - side) / 2, height: (size.height - side) / 2)
            ctx.translateBy(x: off.width, y: off.height)
            ctx.stroke(s, with: .color(stroke), style: StrokeStyle(lineWidth: lineWidth * side / 24, lineCap: .round, lineJoin: .round))
            ctx.fill(f, with: .color(fill))
        }
    }
}

/// Chuyển tên SF Symbol đã dùng rải rác trong UI sang icon riêng của Vutidy.
enum IconAlias {
    static let map: [String: VIcon] = [
        "sparkles": .smartScan, "tray.full": .systemJunk, "tray.full.fill": .systemJunk, "hammer": .devJunk, "trash": .trash, "trash.fill": .trash,
        "hand.raised": .privacy, "shield": .protection, "bolt": .optimization, "wrench.and.screwdriver": .maintenance,
        "xmark.app": .uninstaller, "arrow.down.circle": .updater, "chart.pie": .spaceLens, "doc.badge.clock": .largeFiles,
        "square.on.square": .duplicates, "icloud": .cloud, "archivebox": .quarantine, "archivebox.fill": .quarantine,
        "wrench.and.screwdriver.fill": .sliders, "checkmark.shield.fill": .protection, "exclamationmark.shield.fill": .protection,
        "exclamationmark.triangle.fill": .warn, "exclamationmark.triangle": .warn, "magnifyingglass": .search,
        "list.bullet.rectangle.fill": .doc, "arrow.down.circle.fill": .updater, "shippingbox.fill": .box, "shippingbox": .box,
        "dot.radiowaves.left.and.right": .wifi, "internaldrive.fill": .drive, "folder.fill": .folder, "doc.text.fill": .doc,
        "envelope.fill": .mail, "photo.fill": .photo, "globe": .globe, "safari.fill": .globe, "clock.fill": .clock,
        "hammer.fill": .hammer, "curlybraces": .braces, "cup.and.saucer.fill": .mug, "brain": .chip, "cpu": .chip,
        "memorychip": .ram, "power": .power, "speedometer": .optimization, "heart.fill": .heart, "heart": .heart,
        "gearshape": .gear, "gearshape.fill": .gear, "gearshape.2.fill": .gear, "command": .command, "externaldrive": .drive,
        "cube.fill": .box, "folder.badge.minus": .folder, "chevron.left.forwardslash.chevron.right": .code,
        "wrench.fill": .sliders, "flame.fill": .bolt, "terminal.fill": .code, "exclamationmark": .warn,
        "network": .wifi, "memorychip.fill": .ram, "square.stack.3d.up.fill": .box, "checkmark.circle": .check,
        "magnifyingglass.circle": .search, "arrow.clockwise": .updater, "lock.fill": .lock,
        "externaldrive.badge.timemachine": .clock, "clock.arrow.circlepath": .clock, "doc": .doc, "internaldrive": .drive,
        "xmark.shield": .protection, "ladybug.fill": .malware, "ladybug": .malware, "list.bullet.rectangle": .doc,
    ]

    static func icon(for symbol: String) -> VIcon? {
        if symbol.hasPrefix("v."), let i = VIcon(rawValue: String(symbol.dropFirst(2))) { return i }
        return map[symbol]
    }
}

/// Vẽ glyph: icon riêng nếu có, ngược lại rơi về SF Symbol.
struct Glyph: View {
    let symbol: String
    var size: CGFloat
    var stroke: Color
    var fill: Color
    var body: some View {
        if let i = IconAlias.icon(for: symbol) {
            VIconView(icon: i, stroke: stroke, fill: fill).frame(width: size, height: size)
        } else {
            Image(systemName: symbol).font(.system(size: size * 0.85, weight: .semibold)).foregroundStyle(stroke).frame(width: size, height: size)
        }
    }
}
