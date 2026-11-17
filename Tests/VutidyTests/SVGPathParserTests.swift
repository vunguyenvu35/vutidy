import Testing
import Foundation
import CoreGraphics
@testable import CoreKit

@Suite struct SVGPathParserTests {
    private func box(_ d: String, k: CGFloat = 1) -> CGRect { SVGPathParser.path(d, scale: k).boundingBoxOfPath }
    private func near(_ a: CGFloat, _ b: CGFloat, _ eps: CGFloat = 0.05) -> Bool { abs(a - b) <= eps }

    @Test func linesAndClose() {
        let p = SVGPathParser.path("M0 0h10v10z")
        #expect(p.boundingBoxOfPath == CGRect(x: 0, y: 0, width: 10, height: 10))
    }

    @Test func relativeAndImplicitLineTo() {
        #expect(SVGPathParser.path("M2 2l3 3").currentPoint == CGPoint(x: 5, y: 5))
        #expect(SVGPathParser.path("M0 0 5 5 10 0").currentPoint == CGPoint(x: 10, y: 0))   // cặp sau M là lineto
        #expect(SVGPathParser.path("M8 8l-4 4 4 4").currentPoint == CGPoint(x: 8, y: 16))
    }

    @Test func compactArcFlagsMatchSpacedForm() {
        // "a8 8 0 1116 0": cờ large=1, sweep=1 dính liền x=16. Nửa trên của đường tròn tâm (12,17), bán kính 8.
        let compact = box("M4 17a8 8 0 1116 0")
        let spaced = box("M4 17a8 8 0 1 1 16 0")
        #expect(compact == spaced)
        #expect(near(compact.minX, 4) && near(compact.maxX, 20) && near(compact.minY, 9) && near(compact.maxY, 17))
    }

    @Test func arcSweepDirection() {
        // sweep=1 đi theo chiều kim đồng hồ trên màn hình: từ (4,17) sang (20,17) bằng cung phía TRÊN; sweep=0 là phía dưới.
        #expect(near(box("M4 17A8 8 0 0 1 20 17").minY, 9))
        #expect(near(box("M4 17A8 8 0 0 0 20 17").maxY, 25))
    }

    @Test func cloudStaysInsideTheIconGrid() {
        let b = box("M7 18h10a4 4 0 000-8 6 6 0 00-11.5 1.5A3.5 3.5 0 007 18z")
        #expect(b.minX > 1 && b.maxX < 23 && b.minY > 1 && b.maxY < 23)
    }

    @Test func smoothCubicAndScale() {
        #expect(SVGPathParser.path("M0 0c0 5 5 5 5 0s5-5 5 0").currentPoint == CGPoint(x: 10, y: 0))
        let b = box("M0 0h10v10z", k: 2)
        #expect(b.width == 20 && b.height == 20)
    }

    @Test func eyeShapeFromMockup() {
        let b = box("M2 12s4-7 10-7 10 7 10 7-4 7-10 7S2 12 2 12z")
        #expect(near(b.minX, 2) && near(b.maxX, 22))
        #expect(b.minY < 7 && b.maxY > 17)
    }

    @Test func malformedInputDoesNotCrash() {
        #expect(box("") == .null)
        _ = box("M1")
        _ = box("L5 5")
        _ = box("M0 0 a")
        _ = box("xyz")
    }
}
