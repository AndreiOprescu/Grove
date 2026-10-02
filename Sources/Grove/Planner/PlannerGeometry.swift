import CoreGraphics

struct PlannerGeometry: Equatable {
    var hourHeight: CGFloat = 64          // zoom range 36...160
    var gutterWidth: CGFloat = 52

    static let zoomRange: ClosedRange<CGFloat> = 36...160

    var totalHeight: CGFloat { hourHeight * 24 }
    func y(forMinute m: Int) -> CGFloat { CGFloat(m) / 60 * hourHeight }
    func minute(forY y: CGFloat) -> Int { Int((y / hourHeight * 60).rounded()) }
}
