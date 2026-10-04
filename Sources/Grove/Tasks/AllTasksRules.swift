import GroveCore

/// The order of the Planner screen's task list, which shows every open task. Plain functions, so tests can check them.
enum AllTasksRules {
    /// Splits tasks (already in list order) into the two parts of the list.
    /// `noDay`: inbox, then week tasks (earliest week first), then someday. A day task with no date counts as inbox.
    /// `byDay`: tasks with a day, earliest day first, so late ones are on top. One flat list with no day headings.
    /// Tasks that tie keep the order they came in.
    static func split(_ tasks: [TaskItem]) -> (noDay: [TaskItem], byDay: [TaskItem]) {
        var noDay: [(group: Int, week: DayKey, index: Int, task: TaskItem)] = []
        var byDay: [(day: DayKey, index: Int, task: TaskItem)] = []
        for (i, t) in tasks.enumerated() {
            if t.bucket == .day, let d = t.planDate {
                byDay.append((d, i, t))
            } else {
                noDay.append((group(t.bucket), t.planWeek ?? "", i, t))
            }
        }
        noDay.sort { ($0.group, $0.week, $0.index) < ($1.group, $1.week, $1.index) }
        byDay.sort { ($0.day, $0.index) < ($1.day, $1.index) }
        return (noDay.map(\.task), byDay.map(\.task))
    }

    private static func group(_ bucket: TaskBucket) -> Int {
        switch bucket {
        case .inbox, .day: 0
        case .week: 1
        case .someday: 2
        }
    }
}
