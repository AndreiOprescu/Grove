import GroveCore

/// The small rules behind goals. Plain functions, so tests can check them.
enum GoalRules {
    /// A target is at least one planner step and at most a whole week, in minutes.
    static let minTarget = PlannerMath.minLength
    static let maxTarget = 7 * 24 * 60
    /// The length of a goal block that is dragged into a day, in minutes.
    static let defaultBlockLength = 60
    /// A new goal asks for 5 hours a week. The stepper in the panel moves in half hours.
    static let defaultTarget = 300
    static let targetStep = 30

    static func clampTarget(_ minutes: Int) -> Int { max(minTarget, min(maxTarget, minutes)) }

    /// The seven days of the week that holds `day`: Monday to Sunday, or Sunday to Saturday.
    /// This is the week the planner shows (setting `calendar.weekStartsSunday`).
    static func week(of day: DayKey, sundayFirst: Bool) -> ClosedRange<DayKey> {
        let first = CalendarRules.weekStart(of: day, sundayFirst: sundayFirst)
        return first...first.adding(days: 6)
    }

    /// The colour a block of the goal gets: the goal's own colour, or the accent colour when it has none.
    static func blockColor(of goal: GoalItem) -> String { goal.color.isEmpty ? "accent" : goal.color }

    /// A goal title with the white space cut off. Empty when there is nothing to show.
    static func cleanTitle(_ title: String) -> String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    // MARK: Panel text

    /// The target after one click on the stepper: half an hour more or less, never under half an hour, never over a week.
    static func stepTarget(_ minutes: Int, up: Bool) -> Int {
        clampTarget(max(targetStep, minutes + (up ? targetStep : -targetStep)))
    }

    /// Minutes as hours without the unit: "5", "2.5", "0.25". Two decimals at most, trailing zeros cut.
    static func hours(_ minutes: Int) -> String {
        let hundredths = Int((Double(max(0, minutes)) / 60 * 100).rounded())
        let whole = hundredths / 100, part = hundredths % 100
        if part == 0 { return "\(whole)" }
        return part % 10 == 0 ? "\(whole).\(part / 10)" : "\(whole).\(part < 10 ? "0" : "")\(part)"
    }

    /// "2.5 / 5 h". Over the target is fine: "6 / 5 h".
    static func progressText(done: Int, target: Int) -> String { "\(hours(done)) / \(hours(target)) h" }

    /// "+1h planned", or nil when no block of the goal waits in the week.
    static func plannedText(_ planned: Int) -> String? { planned > 0 ? "+\(hours(planned))h planned" : nil }

    /// "5 h / week", next to the stepper.
    static func targetText(_ minutes: Int) -> String { "\(hours(minutes)) h / week" }

    /// How much of the bar is solid (done) and how much is lighter (planned), each from 0 to 1.
    /// Together they never pass 1, so a goal over its target shows a full solid bar.
    static func bar(done: Int, planned: Int, target: Int) -> (done: Double, planned: Double) {
        guard target > 0 else { return (0, 0) }
        let d = min(1, max(0, Double(done) / Double(target)))
        let p = min(1 - d, max(0, Double(planned) / Double(target)))
        return (d, p)
    }

    /// The title of the panel's week: "This week" when `today` is in it, else "5–11 Oct" or "28 Sep–4 Oct".
    static func weekLabel(_ week: ClosedRange<DayKey>, today: DayKey) -> String {
        if week.contains(today) { return "This week" }
        let first = week.lowerBound, last = week.upperBound
        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        func name(_ d: DayKey) -> String { months[max(0, min(11, d.month - 1))] }
        if first.month == last.month { return "\(first.day)–\(last.day) \(name(last))" }
        return "\(first.day) \(name(first))–\(last.day) \(name(last))"
    }

    /// One sentence for VoiceOver: "Read, 2.5 / 5 h, +1h planned".
    static func accessibilityText(title: String, done: Int, planned: Int, target: Int) -> String {
        [title, progressText(done: done, target: target), plannedText(planned)].compactMap { $0 }.joined(separator: ", ")
    }
}
