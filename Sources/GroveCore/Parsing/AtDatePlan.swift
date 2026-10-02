import Foundation

/// What one `@date` line of a note becomes when it goes to the planner (PLAN §5.5 item 2).
/// This is only text work. The store makes the event or the task.
public struct AtDatePlan: Equatable, Sendable {
    /// The words of the line with the token, the list marker and the hidden task mark taken out.
    public var title: String
    public var day: DayKey
    /// Minute of the day. Nil when the token named a day and no time.
    public var startMinute: Int?
    /// Minutes the user asked for ("for 1h"). Nil when the user did not say.
    public var durationMin: Int?
    /// The line is an open check box. It makes a task and a block. Any other line makes an event.
    public var isTask: Bool
    /// The task that the check box already has.
    public var taskId: String?
    /// Indent and list marker, as typed.
    public var head: String

    /// An event with a time and no length lasts this long.
    public static let eventMinutes = 60
    /// A task block with a time and no length lasts this long.
    public static let blockMinutes = 30
}

public enum AtDatePlanner {
    /// Reads one line. Nil when it has no `@date` token, no words besides the token, or is a ticked box.
    /// - Parameter noteDay: The day of a daily note. A token with a time and no day uses it.
    public static func plan(line raw: String, noteDay: DayKey?, today: DayKey = .today()) -> AtDatePlan? {
        let line = raw.trimmingCharacters(in: .newlines)
        let ns = line as NSString
        let prefix = MarkdownEdit.prefix(of: line)
        let bodyStart = prefix?.length ?? line.prefix { $0 == " " }.count
        var isTask = false
        if case .checklist(_, let checked)? = prefix.map(\.kind) {
            if checked { return nil }
            isTask = true
        } else if line.contains("⟦t:") {
            return nil
        }
        guard let hit = AtDateParser.find(in: line, today: today), hit.range.location >= bodyStart else { return nil }

        var title = ns.replacingCharacters(in: hit.range, with: "") as NSString
        title = title.substring(from: min(bodyStart, title.length)) as NSString
        let words = NoteParser.withoutMarkers(title as String)
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        guard !words.isEmpty else { return nil }

        let taskId = isTask ? NoteParser.checkboxes(in: line).first?.taskId : nil
        return AtDatePlan(title: words, day: hit.day ?? noteDay ?? today, startMinute: hit.startMinute, durationMin: hit.durationMin,
                          isTask: isTask, taskId: taskId, head: ns.substring(to: bodyStart))
    }

    /// The minutes the new event or block covers. Nil when the plan has no time.
    public static func span(_ plan: AtDatePlan, defaultMinutes: Int) -> (start: Int, end: Int)? {
        guard let start = plan.startMinute else { return nil }
        let length = max(5, plan.durationMin ?? defaultMinutes)
        return (start, min(1440, start + length))
    }

    /// "Fri 3 Oct", "Fri 3 Oct, 15:00" or "Fri 3 Oct, 15:00–16:00".
    public static func whenLabel(day: DayKey, start: Int?, end: Int?) -> String {
        let weekdays = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        var label = "\(weekdays[day.weekdayIndex - 1]) \(day.day) \(months[day.month - 1])"
        guard let start else { return label }
        label += ", " + clock(start)
        if let end, end > start { label += "–" + clock(min(end, 1439)) }
        return label
    }

    private static func clock(_ minute: Int) -> String { String(format: "%02d:%02d", minute / 60, minute % 60) }

    /// The line after a check box went to the planner: the words, when, and the hidden mark of the task.
    /// The token is gone. The box keeps its place in the list.
    public static func taskLine(_ plan: AtDatePlan, taskId: String, when: String) -> String {
        plan.head + plan.title + " · " + when + " " + NoteParser.marker(for: taskId)
    }

    /// The line after an event was made: a link to it, then when. `mention` is `[[Title|ID]]`.
    public static func eventLine(_ plan: AtDatePlan, mention: String, when: String) -> String {
        plan.head + mention + " · " + when
    }
}
