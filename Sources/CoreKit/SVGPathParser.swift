import Foundation
import CoreGraphics

/// Bộ phân tích thuộc tính `d` của SVG `<path>` → `CGPath`, để dùng nguyên đường vẽ từ bản thiết kế.
/// Hỗ trợ M m L l H h V v C c S s A a Z z, kể cả cách viết nén của cung tròn (`a8 8 0 1116 0`: cờ dính liền số).
public enum SVGPathParser {
    public static func path(_ d: String, scale k: CGFloat = 1) -> CGPath {
        var r = Reader(Array(d.utf8))
        let path = CGMutablePath()
        var cur = CGPoint.zero, start = CGPoint.zero
        var lastCubic: CGPoint?                 // điểm điều khiển thứ hai của cung bezier trước (cho S/s)
        var cmd: UInt8 = 0

        func P(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * k, y: p.y * k) }

        while true {
            r.skipSeparators()
            if r.atEnd { break }
            if let c = r.command() { cmd = c } else if cmd == 0 { break }
            let rel = cmd >= 97
            let up = rel ? cmd - 32 : cmd
            let ox = rel ? cur.x : 0, oy = rel ? cur.y : 0
            var cubic: CGPoint?

            switch up {
            case UInt8(ascii: "M"):
                guard let x = r.number(), let y = r.number() else { return path }
                cur = CGPoint(x: x + ox, y: y + oy); start = cur
                path.move(to: P(cur))
                cmd = rel ? UInt8(ascii: "l") : UInt8(ascii: "L")      // cặp toạ độ kế tiếp là lineto
            case UInt8(ascii: "L"):
                guard let x = r.number(), let y = r.number() else { return path }
                cur = CGPoint(x: x + ox, y: y + oy); path.addLine(to: P(cur))
            case UInt8(ascii: "H"):
                guard let x = r.number() else { return path }
                cur.x = x + ox; path.addLine(to: P(cur))
            case UInt8(ascii: "V"):
                guard let y = r.number() else { return path }
                cur.y = y + oy; path.addLine(to: P(cur))
            case UInt8(ascii: "C"):
                guard let x1 = r.number(), let y1 = r.number(), let x2 = r.number(), let y2 = r.number(), let x = r.number(), let y = r.number() else { return path }
                let c2 = CGPoint(x: x2 + ox, y: y2 + oy)
                path.addCurve(to: P(CGPoint(x: x + ox, y: y + oy)), control1: P(CGPoint(x: x1 + ox, y: y1 + oy)), control2: P(c2))
                cur = CGPoint(x: x + ox, y: y + oy); cubic = c2
            case UInt8(ascii: "S"):
                guard let x2 = r.number(), let y2 = r.number(), let x = r.number(), let y = r.number() else { return path }
                let c1 = lastCubic.map { CGPoint(x: 2 * cur.x - $0.x, y: 2 * cur.y - $0.y) } ?? cur
                let c2 = CGPoint(x: x2 + ox, y: y2 + oy)
                path.addCurve(to: P(CGPoint(x: x + ox, y: y + oy)), control1: P(c1), control2: P(c2))
                cur = CGPoint(x: x + ox, y: y + oy); cubic = c2
            case UInt8(ascii: "A"):
                guard let rx = r.number(), let ry = r.number(), let rot = r.number(),
                      let large = r.flag(), let sweep = r.flag(), let x = r.number(), let y = r.number() else { return path }
                let end = CGPoint(x: x + ox, y: y + oy)
                addArc(to: path, from: cur, rx: rx, ry: ry, rotation: rot, large: large, sweep: sweep, end: end, k: k)
                cur = end
            case UInt8(ascii: "Z"):
                path.closeSubpath(); cur = start
            default:
                return path
            }
            lastCubic = cubic
        }
        return path
    }

    // MARK: Cung elip (SVG F.6.5) → các đoạn bezier

    private static func addArc(to path: CGMutablePath, from p0: CGPoint, rx rx0: CGFloat, ry ry0: CGFloat, rotation: CGFloat,
                               large: Bool, sweep: Bool, end p1: CGPoint, k: CGFloat) {
        var rx = abs(rx0), ry = abs(ry0)
        if rx == 0 || ry == 0 || p0 == p1 { path.addLine(to: CGPoint(x: p1.x * k, y: p1.y * k)); return }
        let phi = rotation * .pi / 180, cp = cos(phi), sp = sin(phi)
        let dx = (p0.x - p1.x) / 2, dy = (p0.y - p1.y) / 2
        let x1p = cp * dx + sp * dy, y1p = -sp * dx + cp * dy
        let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
        if lambda > 1 { let s = lambda.squareRoot(); rx *= s; ry *= s }
        let num = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p
        let den = rx * rx * y1p * y1p + ry * ry * x1p * x1p
        let coef = (large == sweep ? -1 : 1) * max(0, num / den).squareRoot()
        let cxp = coef * rx * y1p / ry, cyp = -coef * ry * x1p / rx
        let cx = cp * cxp - sp * cyp + (p0.x + p1.x) / 2
        let cy = sp * cxp + cp * cyp + (p0.y + p1.y) / 2

        func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            let a = atan2(ux * vy - uy * vx, ux * vx + uy * vy)
            return a
        }
        let theta1 = angle(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
        var delta = angle((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry)
        if !sweep && delta > 0 { delta -= 2 * .pi }
        if sweep && delta < 0 { delta += 2 * .pi }

        let n = max(1, Int((abs(delta) / (.pi / 2)).rounded(.up) - 1e-9))
        let step = delta / CGFloat(n)
        let t = 4.0 / 3.0 * tan(step / 4)
        func map(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: (cx + rx * x * cp - ry * y * sp) * k, y: (cy + rx * x * sp + ry * y * cp) * k)
        }
        var a = theta1
        for _ in 0..<n {
            let b = a + step
            path.addCurve(to: map(cos(b), sin(b)),
                          control1: map(cos(a) - t * sin(a), sin(a) + t * cos(a)),
                          control2: map(cos(b) + t * sin(b), sin(b) - t * cos(b)))
            a = b
        }
    }

    // MARK: Đọc ký tự

    private struct Reader {
        let b: [UInt8]
        var i = 0
        init(_ b: [UInt8]) { self.b = b }
        var atEnd: Bool { i >= b.count }
        mutating func skipSeparators() { while i < b.count, [32, 44, 9, 10, 13].contains(b[i]) { i += 1 } }
        mutating func command() -> UInt8? {
            guard i < b.count else { return nil }
            let c = b[i]
            guard (65...90).contains(c) || (97...122).contains(c), c != 101, c != 69 else { return nil }
            i += 1; return c
        }
        mutating func flag() -> Bool? {
            skipSeparators()
            guard i < b.count, b[i] == 48 || b[i] == 49 else { return nil }
            defer { i += 1 }
            return b[i] == 49
        }
        mutating func number() -> CGFloat? {
            skipSeparators()
            let s = i
            if i < b.count, b[i] == 43 || b[i] == 45 { i += 1 }
            var digits = false
            while i < b.count, (48...57).contains(b[i]) { i += 1; digits = true }
            if i < b.count, b[i] == 46 {
                i += 1
                while i < b.count, (48...57).contains(b[i]) { i += 1; digits = true }
            }
            guard digits else { i = s; return nil }
            if i < b.count, b[i] == 101 || b[i] == 69 {
                var j = i + 1
                if j < b.count, b[j] == 43 || b[j] == 45 { j += 1 }
                if j < b.count, (48...57).contains(b[j]) { while j < b.count, (48...57).contains(b[j]) { j += 1 }; i = j }
            }
            return CGFloat(Double(String(decoding: b[s..<i], as: UTF8.self)) ?? 0)
        }
    }
}
