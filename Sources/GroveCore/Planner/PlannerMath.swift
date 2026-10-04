import Foundation

/// A time range on one day, in minutes since midnight.
public struct Span: Equatable, Sendable {
    public var id: String
    public var start: Int
    public var end: Int
    public init(id: String, start: Int, end: Int) { self.id = id; self.start = start; self.end = end }
    public var length: Int { end - start }
}

/// Pure planner maths. No UI, no database. All values are minutes since midnight.
public enum PlannerMath {
    public static let dayEnd = 1440
    /// Blocks start, end and move on a 15 minute grid.
    public static let step = 15
    /// The shortest block the planner makes.
    public static let minLength = 15

    /// The length a task gets on the grid: its estimate, rounded up to the step, at least `minLength`.
    public static func blockLength(_ estimate: Int) -> Int {
        max(minLength, (estimate + step - 1) / step * step)
    }

    /// The next grid line after (`direction` > 0) or before (`direction` < 0) `minute`.
    /// A minute off the grid goes to the grid line next to it, not a whole step away.
    public static func stepped(_ minute: Int, by direction: Int, step: Int) -> Int {
        let step = max(1, step)
        if direction >= 0 { return (minute / step + 1) * step }
        return minute > 0 ? (minute - 1) / step * step : minute - step
    }

    /// Round to the nearest step. Halves round up.
    public static func snap(_ minute: Int, step: Int) -> Int {
        guard step > 1 else { return minute }
        return Int((Double(minute) / Double(step)).rounded(.toNearestOrAwayFromZero)) * step
    }

    /// Keep a block of `length` inside 00:00...24:00 when moving.
    public static func clampMove(start: Int, length: Int) -> Int {
        max(0, min(start, dayEnd - length))
    }

    /// Move the top edge. The end stays. The block keeps at least `minLen` minutes.
    public static func resizeTop(start: Int, end: Int, newStart: Int, step: Int, minLen: Int = 5) -> (Int, Int) {
        let s = max(0, min(snap(newStart, step: step), end - minLen))
        return (s, end)
    }

    /// Move the bottom edge. The start stays. The block keeps at least `minLen` minutes.
    public static func resizeBottom(start: Int, end: Int, newEnd: Int, step: Int, minLen: Int = 5) -> (Int, Int) {
        let e = min(dayEnd, max(snap(newEnd, step: step), start + minLen))
        return (start, e)
    }

    /// Push spans that overlap `moved` and start at or after `moved.start` down, cascading.
    /// Returns only the spans whose start changed. Clamps at 24:00 (may overlap there).
    public static func ripple(moved: Span, others: [Span]) -> [Span] {
        let candidates = others
            .filter { $0.id != moved.id && $0.start >= moved.start }
            .sorted { $0.start != $1.start ? $0.start < $1.start : $0.id < $1.id }
        var frontier = moved.end
        var changed: [Span] = []
        for s in candidates {
            guard s.start < frontier else { break }
            let newStart = min(frontier, dayEnd - s.length)
            if newStart != s.start { changed.append(Span(id: s.id, start: newStart, end: newStart + s.length)) }
            frontier = newStart + s.length
        }
        return changed
    }

    /// First start (on the step grid) with `length` free minutes before `until`. Nil if none.
    public static func firstFreeSlot(length: Int, busy: [Span], from: Int, until: Int, step: Int) -> Int? {
        let step = max(1, step)
        func ceilStep(_ m: Int) -> Int { (m + step - 1) / step * step }
        var candidate = ceilStep(max(0, from))
        for b in busy.sorted(by: { $0.start < $1.start }) {
            if b.end <= candidate { continue }
            if b.start >= candidate + length { break }
            candidate = ceilStep(b.end)
        }
        return candidate + length <= until ? candidate : nil
    }

    /// "11:15 – 12:45 · 1h 30m"
    public static func label(start: Int, end: Int) -> String {
        "\(clock(start)) – \(clock(end)) · \(duration(end - start))"
    }

    public static func clock(_ minute: Int) -> String {
        String(format: "%02d:%02d", minute / 60, minute % 60)
    }

    public static func duration(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m)m" }
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }
}
