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
    /// The lengths, in minutes, in the "Duration" entry of a block's menu.
    static let durationChoices = [15, 30, 45, 60, 90, 120, 180, 240]

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

    /// How a task block splits its text lines between title, short description and subtasks.
    /// The title keeps one line and the short description comes next, as before. Subtasks get the lines left.
    /// When they do not all fit, the last line says how many are hidden ("+3 more").
    /// With no line left, a small count sits in the title row instead (`badge`).
    /// Lines the subtasks do not need go back to the title (at most 2 with a description) and the description.
    static func blockRows(height: CGFloat, hasSummary: Bool, subtaskCount: Int) -> BlockRows {
        let old = blockTextLines(height: height, hasSummary: hasSummary)
        guard subtaskCount > 0 else {
            return BlockRows(title: old.title, summary: old.summary, subtasks: 0, moreRow: false, badge: false)
        }
        let summary = old.summary > 0 ? 1 : 0
        let left = old.title + old.summary - 1 - summary
        if left <= 0 {
            return BlockRows(title: 1, summary: summary, subtasks: 0, moreRow: false, badge: true)
        }
        if left < subtaskCount {
            return BlockRows(title: 1, summary: summary, subtasks: left - 1, moreRow: true, badge: false)
        }
        let rest = left - subtaskCount
        if summary > 0 {
            let more = min(1, rest)
            return BlockRows(title: 1 + more, summary: summary + rest - more, subtasks: subtaskCount, moreRow: false, badge: false)
        }
        return BlockRows(title: 1 + rest, summary: 0, subtasks: subtaskCount, moreRow: false, badge: false)
    }
}

/// The text lines of a task block. See `PlannerLayoutRules.blockRows`.
struct BlockRows: Equatable {
    var title: Int
    var summary: Int
    /// Subtask rows shown, from the top of the list.
    var subtasks: Int
    /// A last row that says what is not shown.
    var moreRow: Bool
    /// No line for subtasks at all: a small "1/4" sits in the title row.
    var badge: Bool

    func hidden(of total: Int) -> Int { max(0, total - subtasks) }
}
