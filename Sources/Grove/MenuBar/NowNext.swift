import Foundation
import GroveCore

/// The two lines at the top of the menu bar window.
struct NowNext: Equatable {
    var now: String
    var next: String
}

/// "Now: <block>" and "Next: <block> in 25 min" (PLAN §5.7). Plain rules, so a test can check them.
enum NowNextRules {
    /// `blocks` are the timed blocks of today. A block of a finished task is left out: it is not what you do now.
    static func make(blocks: [PlannerBlock], minute: Int) -> NowNext {
        let open = blocks.filter { !$0.isDone }
        // When blocks overlap, "now" is the one that started last.
        let running = open.filter { $0.startMinute <= minute && minute < $0.endMinute }
            .max { ($0.startMinute, $0.id) < ($1.startMinute, $1.id) }
        let coming = open.filter { $0.startMinute > minute }
            .min { ($0.startMinute, $0.id) < ($1.startMinute, $1.id) }
        return NowNext(
            now: running.map { "Now: \($0.title)" } ?? "Nothing planned right now",
            next: coming.map { "Next: \($0.title) \(inText($0.startMinute - minute))" } ?? "Nothing else today")
    }

    /// 25 → "in 25 min", 60 → "in 1 h", 90 → "in 1 h 30 min"
    static func inText(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "in \(m) min" }
        return m == 0 ? "in \(h) h" : "in \(h) h \(m) min"
    }
}
