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

/// Rules for how the planner gives up space when the window is tight.
enum PlannerLayoutRules {
    /// The unscheduled tray is 230 wide. The grid next to it needs about 450 to stay readable.
    static let trayMinContentWidth: CGFloat = 680

    static func trayFits(contentWidth: CGFloat) -> Bool { contentWidth >= trayMinContentWidth }


    /// How many minutes after a block's start another block would cover its text rows.
    /// A block that shows a short description has one more row than one that shows a title only.
    static func tightMinutes(hourHeight: CGFloat, blockHeight: CGFloat, hasSummary: Bool) -> Int {
        let shows = hasSummary && blockTextLines(height: blockHeight, hasSummary: true).summary > 0
        let rows = PlannerGeometry.titleRowHeight + (shows ? 14 : 0)
        return Int((rows / (hourHeight / 60)).rounded(.up))
    }

    /// How far right (in points) a block on top must start to leave the title and short description readable.
    /// It never takes more than half the column.
    static func textClearance(title: String, summary: String, columnWidth: Double) -> Double {
        min(columnWidth * 0.5, max(38 + 6 * Double(title.count), 28 + 5.6 * Double(summary.count)))
    }

    /// How many text lines a block of this height can show, split between its title and its short description.
    /// The title keeps at least one line. A short description needs a second line to appear at all.
    static func blockTextLines(height: CGFloat, hasSummary: Bool) -> (title: Int, summary: Int) {
        let lines = max(1, Int((height - 28) / 15) + 1)
        guard hasSummary, lines >= 2 else { return (lines, 0) }
        let title = min(2, lines - 1)
        return (title, lines - title)
    }

}
