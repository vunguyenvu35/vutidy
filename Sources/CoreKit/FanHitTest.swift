import Foundation
import CoreGraphics

/// Hit-test cho dải thẻ xếp quạt ở Smart Scan. Các thẻ xoay quanh một trục nằm thấp bên dưới và chồng lên nhau,
/// thẻ đang được rê chuột còn được nâng lên và phóng to. Nếu chỉ dùng vùng ở vị trí nghỉ thì thẻ bên cạnh
/// "cướp" con trỏ khi nó còn nằm trên phần đã nâng của thẻ hiện tại. Ở đây thẻ đang chọn được ưu tiên giữ
/// chừng nào con trỏ còn trong hình dạng ĐÃ NÂNG của nó (hysteresis).
public enum FanHitTest {
    public struct Layout: Sendable {
        public var cardSize = CGSize(width: 232, height: 236)
        public var top: CGFloat = 30
        /// Vị trí trục xoay dưới đỉnh thẻ, tính theo chiều cao thẻ (CSS: transform-origin 50% 300%).
        public var pivot: CGFloat = 3
        public var lift: CGFloat = 34
        public var scale: CGFloat = 1.06
        public var rotations: [Double]
        public init(rotations: [Double]) { self.rotations = rotations }
    }

    /// Điểm `p` (toạ độ của khung chứa, rộng `width`) có nằm trong thẻ `i` không.
    public static func contains(_ p: CGPoint, card i: Int, lifted: Bool, width: CGFloat, layout l: Layout) -> Bool {
        let w = l.cardSize.width, h = l.cardSize.height
        let cx = width / 2, cy = l.top + h / 2
        let pivot = CGPoint(x: cx, y: l.top + l.pivot * h)
        let t = l.rotations[i] * .pi / 180
        // Hoàn tác phép xoay (SwiftUI: góc dương = chiều kim đồng hồ trên màn hình, trục y hướng xuống).
        let dx = p.x - pivot.x, dy = p.y - pivot.y
        var qx = pivot.x + dx * cos(t) + dy * sin(t)
        var qy = pivot.y - dx * sin(t) + dy * cos(t)
        if lifted {
            qy += l.lift                                   // hoàn tác dịch lên
            qx = cx + (qx - cx) / l.scale                  // hoàn tác phóng to quanh tâm thẻ
            qy = cy + (qy - cy) / l.scale
        }
        return abs(qx - cx) <= w / 2 && abs(qy - cy) <= h / 2
    }

    /// Thẻ nằm dưới con trỏ: ưu tiên thẻ `current` (đã nâng), nếu không thì thẻ trên cùng ở vị trí nghỉ.
    public static func card(at p: CGPoint, width: CGFloat, current: Int?, layout l: Layout) -> Int? {
        if let c = current, l.rotations.indices.contains(c), contains(p, card: c, lifted: true, width: width, layout: l) { return c }
        for i in l.rotations.indices.reversed() where contains(p, card: i, lifted: false, width: width, layout: l) { return i }
        return nil
    }
}
