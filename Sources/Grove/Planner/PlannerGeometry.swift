import CoreGraphics

struct PlannerGeometry: Equatable {
    var hourHeight: CGFloat = 64          // zoom range 36...160
    var gutterWidth: CGFloat = 52

    static let zoomRange: ClosedRange<CGFloat> = 36...160
    /// Shortest height a block is drawn at, so the title of a 5 minute block can still be read.
    static let minBlockHeight: CGFloat = 22
    /// A block that starts closer than this to the one under it would cover that block's title row.
    static let titleRowHeight: CGFloat = 32

    var totalHeight: CGFloat { hourHeight * 24 }
    func y(forMinute m: Int) -> CGFloat { CGFloat(m) / 60 * hourHeight }
    func minute(forY y: CGFloat) -> Int { Int((y / hourHeight * 60).rounded()) }

    /// The shortest length, in minutes, that a block is drawn at at this zoom.
    var minDrawnMinutes: Int { Int((Self.minBlockHeight / (hourHeight / 60)).rounded(.up)) }
    /// How many minutes the title row of a block covers at this zoom.
    var tightMinutes: Int { Int((Self.titleRowHeight / (hourHeight / 60)).rounded(.up)) }
}
