import Testing
import Foundation
import CoreGraphics
@testable import CoreKit

@Suite struct FanHitTestTests {
    let layout = FanHitTest.Layout(rotations: [-26, -13, 0, 13, 26])
    let width: CGFloat = 760

    @Test func centreOfMiddleCardHitsIt() {
        #expect(FanHitTest.card(at: CGPoint(x: width / 2, y: 30 + 118), width: width, current: nil, layout: layout) == 2)
    }

    /// Thẻ xoay +26° (cuối dải) nằm lệch sang PHẢI và thấp hơn thẻ giữa; -26° thì lệch sang trái — khớp với hình vẽ.
    @Test func rotatedCardsLandWhereTheyAreDrawn() {
        let r: CGFloat = 3 * 236 - 118                       // khoảng cách từ trục xoay tới tâm thẻ khi đứng yên
        for (i, deg) in [(0, -26.0), (1, -13.0), (3, 13.0), (4, 26.0)] {
            let t = deg * .pi / 180
            let centre = CGPoint(x: width / 2 + r * CGFloat(sin(t)), y: 3 * 236 + 30 - r * CGFloat(cos(t)))
            #expect(FanHitTest.contains(centre, card: i, lifted: false, width: width, layout: layout), "thẻ \(i)")
        }
        #expect(!FanHitTest.contains(CGPoint(x: width / 2 - 250, y: 150), card: 4, lifted: false, width: width, layout: layout))
    }

    @Test func emptyAreaHitsNothing() {
        #expect(FanHitTest.card(at: CGPoint(x: 5, y: 5), width: width, current: nil, layout: layout) == nil)
        #expect(FanHitTest.card(at: CGPoint(x: width / 2, y: 385), width: width, current: 2, layout: layout) == nil)
    }

    @Test func liftedCardExtendsAboveItsRestShape() {
        let p = CGPoint(x: width / 2, y: 30 - 20)               // phía trên đỉnh thẻ giữa khi đứng yên
        #expect(!FanHitTest.contains(p, card: 2, lifted: false, width: width, layout: layout))
        #expect(FanHitTest.contains(p, card: 2, lifted: true, width: width, layout: layout))
        #expect(FanHitTest.card(at: p, width: width, current: 2, layout: layout) == 2)
    }

    /// Lỗi đã gặp: giữa hai thẻ cuối, thẻ bên phải đè lên phần đã nâng của thẻ bên trái và "cướp" con trỏ.
    @Test func currentCardKeepsPointerInOverlapWithNeighbour() {
        var stuck = 0
        for xi in stride(from: 0, through: Int(width), by: 4) {
            for yi in stride(from: 0, through: 390, by: 4) {
                let p = CGPoint(x: xi, y: yi)
                guard FanHitTest.contains(p, card: 3, lifted: true, width: width, layout: layout),
                      FanHitTest.contains(p, card: 4, lifted: false, width: width, layout: layout) else { continue }
                // Không có thẻ đang chọn: thẻ phải trên cùng thắng. Đang chọn thẻ 3: phải giữ nguyên.
                #expect(FanHitTest.card(at: p, width: width, current: nil, layout: layout) == 4)
                #expect(FanHitTest.card(at: p, width: width, current: 3, layout: layout) == 3)
                stuck += 1
            }
        }
        #expect(stuck > 50, "phải có vùng chồng đáng kể giữa thẻ 3 (đã nâng) và thẻ 4")
    }

    @Test func movingOutOfCurrentCardSwitchesToNeighbour() {
        // Điểm chỉ thuộc thẻ 4 (không thuộc thẻ 3 đã nâng) → chuyển sang thẻ 4.
        for xi in stride(from: 0, through: Int(width), by: 4) {
            for yi in stride(from: 0, through: 390, by: 4) {
                let p = CGPoint(x: xi, y: yi)
                if FanHitTest.contains(p, card: 4, lifted: false, width: width, layout: layout),
                   !FanHitTest.contains(p, card: 3, lifted: true, width: width, layout: layout) {
                    #expect(FanHitTest.card(at: p, width: width, current: 3, layout: layout) == 4)
                    return
                }
            }
        }
        Issue.record("không tìm được điểm chỉ thuộc thẻ 4")
    }
}
