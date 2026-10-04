import Foundation

/// The numbers and the words of the Day Spread (PLAN §8, layout B). Plain values, so the tests need no view.
enum SpreadRules {
    /// The task list on the left is 300 to 420 pt wide. The user drags its edge.
    static let tasksRange: ClosedRange<Double> = 300...420
    static let tasksDefault = 340.0
    /// The note column has one width. The timeline in the centre takes what is left.
    static let noteWidth = 340.0
    static let timelineMinimum = 280.0
    static let gap = 12.0
    static let side = 16.0

    /// The window width where the widest task list still leaves the timeline its minimum.
    static var minimumWindowWidth: Double {
        2 * side + 2 * gap + tasksRange.upperBound + timelineMinimum + noteWidth
    }

    static func clampTasks(_ width: Double) -> Double {
        min(tasksRange.upperBound, max(tasksRange.lowerBound, width))
    }

    /// The line under the big date.
    static func subtitle(isToday: Bool, greeting: String, progress: PlantProgress) -> String {
        if isToday { return "\(greeting) · \(progress.growthText)" }
        return progress.total == 0 ? "Nothing planned" : "\(progress.percent)% of the day grown"
    }
}
