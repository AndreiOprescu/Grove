import GroveCore

/// The text rules behind the subtask list in the task panel. Plain functions, so tests can check them.
/// A subtask is a task with a parent: name = title, description = notes, duration = estimateMin, done = status.
enum SubtaskRules {
    /// The minutes offered in the duration menu of a subtask.
    static let durations = [5, 10, 15, 30, 45, 60, 90, 120]

    /// The menu choices, plus the current value when it is not one of them.
    static func durations(including current: Int) -> [Int] {
        Set(durations + [current]).filter { $0 > 0 }.sorted()
    }

    /// "15m" for the collapsed row. Nil for no duration.
    static func chip(_ minutes: Int) -> String? {
        minutes > 0 ? PlannerMath.duration(minutes) : nil
    }

    /// "2/4 · 1h 15m": done of total, then the time of all subtasks. Empty when there are none.
    static func summary(_ subs: [TaskItem]) -> String {
        guard !subs.isEmpty else { return "" }
        var text = "\(subs.filter(\.isDone).count)/\(subs.count)"
        let minutes = subs.reduce(0) { $0 + max(0, $1.estimateMin) }
        if minutes > 0 { text += " \u{B7} " + PlannerMath.duration(minutes) }
        return text
    }

    /// The section title: "Subtasks  2/4 · 1h 15m".
    static func header(_ subs: [TaskItem]) -> String {
        let s = summary(subs)
        return s.isEmpty ? "Subtasks" : "Subtasks  " + s
    }

    /// The name to save after the user edits a title, or nil when nothing should be saved
    /// (empty after trimming, or not different from `current`).
    static func renamed(_ raw: String, from current: String) -> String? {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty || name == current ? nil : name
    }

    /// The last row of a task block when not every subtask fits: "+3 more",
    /// or "1/4 subtasks" when no subtask row fits at all.
    static func moreLabel(hidden: Int, shown: Int, done: Int, total: Int) -> String {
        shown == 0 ? "\(done)/\(total) subtasks" : "+\(hidden) more"
    }

    /// The small count in a block's title row when no subtask row fits: "1/4".
    static func badge(done: Int, total: Int) -> String { "\(done)/\(total)" }
}
