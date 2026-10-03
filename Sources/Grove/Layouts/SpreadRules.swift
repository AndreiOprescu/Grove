import Foundation

/// The numbers and the words of the Day Spread (PLAN §8, layout B). Plain values, so the tests need no view.
enum SpreadRules {
    /// The timeline column is 300 to 420 pt wide. The user drags its edge.
    static let timelineRange: ClosedRange<Double> = 300...420
    static let timelineDefault = 340.0
    /// The note column has one width. The task list takes what is left.
    static let noteWidth = 340.0
    static let tasksMinimum = 280.0
    static let gap = 12.0
    static let side = 16.0

    /// The window width where the widest timeline still leaves the task list its minimum.
    static var minimumWindowWidth: Double {
        2 * side + 2 * gap + timelineRange.upperBound + tasksMinimum + noteWidth
    }

    static func clampTimeline(_ width: Double) -> Double {
        min(timelineRange.upperBound, max(timelineRange.lowerBound, width))
    }

    /// The line under the big date.
    static func subtitle(isToday: Bool, greeting: String, progress: PlantProgress) -> String {
        if isToday { return "\(greeting) · \(progress.growthText)" }
        return progress.total == 0 ? "Nothing planned" : "\(progress.percent)% of the day grown"
    }
}
