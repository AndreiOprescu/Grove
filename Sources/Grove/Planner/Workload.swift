import Foundation
import GroveCore

/// The numbers behind the workload bar under the timeline title: planned time against the busy-day limit.
enum Workload {
    /// How full the bar is, from 0 to 1. A limit of 0 is full.
    static func fraction(planned: Int, limit: Int) -> Double {
        guard limit > 0 else { return 1 }
        return max(0, min(1, Double(planned) / Double(limit)))
    }

    /// True when there is more planned than the limit. Exactly the limit is still fine.
    static func isOver(planned: Int, limit: Int) -> Bool { planned > limit }

    /// "6h 30m/9h"
    static func label(planned: Int, limit: Int) -> String {
        PlannerMath.duration(planned) + "/" + PlannerMath.duration(limit)
    }
}
