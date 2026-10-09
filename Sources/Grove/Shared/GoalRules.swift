import GroveCore

/// A goal's week: what it counts, how much is done, how much is planned (done blocks included)
/// and the target, all in one unit (minutes or sessions).
struct GoalProgress: Equatable {
    var kind: GoalKind
    var done: Int
    var planned: Int
    var target: Int
}

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

    /// A sessions goal asks for 3 a week. The stepper moves by one, from 1 to 99.
    static let defaultCount = 3
    static let minCount = 1
    static let maxCount = 99

    static func clampCount(_ count: Int) -> Int { max(minCount, min(maxCount, count)) }

    /// The goal's weekly target in its own unit: minutes for hours, a count for sessions.
    static func target(of goal: GoalItem) -> Int { goal.kind == .hours ? goal.targetMin : goal.targetCount }

    static func defaultTarget(for kind: GoalKind) -> Int { kind == .hours ? defaultTarget : defaultCount }

    static func clamp(_ target: Int, kind: GoalKind) -> Int { kind == .hours ? clampTarget(target) : clampCount(target) }

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

    /// The target after one click on the stepper. Hours: half an hour more or less, never under half an hour,
    /// never over a week. Sessions: one more or less, from 1 to 99.
    static func stepTarget(_ value: Int, kind: GoalKind, up: Bool) -> Int {
        switch kind {
        case .hours: clampTarget(max(targetStep, value + (up ? targetStep : -targetStep)))
        case .sessions: clampCount(value + (up ? 1 : -1))
        }
    }

    /// "Hours" or "Sessions", for the picker.
    static func kindName(_ kind: GoalKind) -> String { kind == .hours ? "Hours" : "Sessions" }

    /// Minutes as hours without the unit: "5", "2.5", "0.25". Two decimals at most, trailing zeros cut.
    static func hours(_ minutes: Int) -> String {
        let hundredths = Int((Double(max(0, minutes)) / 60 * 100).rounded())
        let whole = hundredths / 100, part = hundredths % 100
        if part == 0 { return "\(whole)" }
        return part % 10 == 0 ? "\(whole).\(part / 10)" : "\(whole).\(part < 10 ? "0" : "")\(part)"
    }

    /// "2.5 / 5 h done" or "3 / 5 sessions done". Over the target is fine: "7 / 5 h done".
    static func progressText(_ p: GoalProgress) -> String {
        switch p.kind {
        case .hours: "\(hours(p.done)) / \(hours(p.target)) h done"
        case .sessions: "\(max(0, p.done)) / \(p.target) \(p.target == 1 ? "session" : "sessions") done"
        }
    }

    /// "4 h planned" or "2 sessions planned": every block of the week, done or not. "Nothing planned yet" for none.
    static func plannedText(_ p: GoalProgress) -> String {
        guard p.planned > 0 else { return "Nothing planned yet" }
        return switch p.kind {
        case .hours: "\(hours(p.planned)) h planned"
        case .sessions: "\(p.planned) \(p.planned == 1 ? "session" : "sessions") planned"
        }
    }

    /// "5 h / week" or "3 sessions / week", next to the stepper.
    static func targetText(_ kind: GoalKind, _ target: Int) -> String {
        switch kind {
        case .hours: "\(hours(target)) h / week"
        case .sessions: "\(target) \(target == 1 ? "session" : "sessions") / week"
        }
    }

    /// How far the solid part (done) and the lighter part (planned, done included) reach, each from 0 to 1.
    /// A goal at or over its target shows a full bar.
    static func bar(_ p: GoalProgress) -> (done: Double, planned: Double) {
        guard p.target > 0 else { return (0, 0) }
        func part(_ v: Int) -> Double { min(1, max(0, Double(v) / Double(p.target))) }
        return (part(p.done), max(part(p.done), part(p.planned)))
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

    /// One sentence for VoiceOver: "Read, 2.5 / 5 h done, 4 h planned".
    static func accessibilityText(title: String, _ p: GoalProgress) -> String {
        "\(title), \(progressText(p)), \(plannedText(p))"
    }
}
