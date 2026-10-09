import SwiftUI
import GroveCore

/// Goals: recurring work with a target of minutes per week and no date.
/// A goal is dragged into a day as a block. A block marked done adds its length to the goal that week.
/// Progress is worked out from the blocks each time, never stored. Every write is a single undo step.
extension AppStore {
    // MARK: Reading

    /// The goals in list order. Archived goals only when asked.
    func goals(includeArchived: Bool = false) -> [GoalItem] {
        (try? repos.goals.all(includeArchived: includeArchived)) ?? []
    }

    func goal(_ id: String) -> GoalItem? { try? repos.goals.get(id) }

    /// The planner's setting: does the week start on Sunday?
    var weekStartsSunday: Bool { UserDefaults.standard.bool(forKey: "calendar.weekStartsSunday") }

    /// Minutes done and planned this week, and the weekly target. The week is the one that holds `day`,
    /// the same week the planner shows. `sundayFirst` defaults to the planner setting.
    func goalProgress(_ id: String, weekOf day: DayKey, sundayFirst: Bool? = nil) -> (done: Int, planned: Int, target: Int) {
        let week = GoalRules.week(of: day, sundayFirst: sundayFirst ?? weekStartsSunday)
        let done = (try? repos.goals.doneMinutes(goalId: id, from: week.lowerBound, to: week.upperBound)) ?? 0
        let planned = (try? repos.goals.plannedMinutes(goalId: id, from: week.lowerBound, to: week.upperBound)) ?? 0
        return (done, planned, goal(id)?.targetMin ?? 0)
    }

    // MARK: Writing

    /// Sort value that puts a new goal after every existing one.
    private func nextGoalSort() -> Double {
        ((try? repos.db.queryOne("SELECT COALESCE(MAX(sort), 0) FROM goals") { $0.double(0) }) ?? 0) + 1
    }

    /// A new goal. Nil when the title is empty.
    @discardableResult
    func addGoal(title: String, targetMin: Int = GoalRules.defaultTarget) -> GoalItem? {
        let name = GoalRules.cleanTitle(title)
        guard !name.isEmpty else { return nil }
        let g = GoalItem(title: name, targetMin: GoalRules.clampTarget(targetMin), sort: nextGoalSort())
        var m = Mutation(name: "New Goal")
        m.goals.append((nil, g))
        return commit(m) ? g : nil
    }

    /// Changes the fields that are given. An empty title or a colour that is not one of the eight is ignored.
    /// Blocks that are already in the planner keep the title and colour they had.
    func updateGoal(_ id: String, title: String? = nil, notes: String? = nil, color: String? = nil,
                    targetMin: Int? = nil, archived: Bool? = nil) {
        guard let old = goal(id) else { return }
        var g = old
        if let title, !GoalRules.cleanTitle(title).isEmpty { g.title = GoalRules.cleanTitle(title) }
        if let notes { g.notes = notes }
        if let color, TaskColor.isValid(color) { g.color = color }
        if let targetMin { g.targetMin = GoalRules.clampTarget(targetMin) }
        if let archived { g.archived = archived }
        guard g != old else { return }
        var m = Mutation(name: "Edit Goal")
        m.goals.append((old, g))
        commit(m)
    }

    /// Deletes the goal. Its blocks stay in the planner as plain blocks (no goal, not done). Undo brings both back.
    func deleteGoal(_ id: String) {
        guard let old = goal(id) else { return }
        var m = Mutation(name: "Delete Goal")
        m.goals.append((old, nil))
        for e in (try? repos.events.blocks(forGoal: id)) ?? [] {
            var plain = e
            plain.goalId = nil
            plain.doneAt = nil
            m.events.append((e, plain))
        }
        commit(m)
    }

    /// Puts a block of the goal on the grid and selects it. It is a plain `.block` with no task. It keeps the goal's
    /// title and colour (the accent colour when the goal has none). The goal stays, so more blocks can be added.
    func scheduleGoal(goalId: String, day: DayKey, start: Int, length: Int = GoalRules.defaultBlockLength) {
        guard let goal = goal(goalId) else { return }
        let len = min(PlannerMath.dayEnd, PlannerMath.blockLength(length))
        let s = PlannerMath.clampMove(start: start, length: len)
        let e = EventItem(title: goal.title, start: WallTime(day: day, minute: s), end: WallTime(day: day, minute: s + len),
                          kind: .block, color: GoalRules.blockColor(of: goal), goalId: goal.id)
        var m = Mutation(name: "Schedule Goal")
        m.events.append((nil, e))
        if commit(m) { selection = [e.id] }
    }

    /// A goal dragged onto the grid. `raw` is the dragged text, `minute` the snapped minute under the pointer.
    /// Adds a block of the default length. False when the text is not a goal or the goal is gone.
    @discardableResult
    func dropGoalOnPlanner(raw: String, day: DayKey, minute: Int) -> Bool {
        guard let id = DragPayload.goalId(from: raw), goal(id) != nil else { return false }
        scheduleGoal(goalId: id, day: day, start: minute)
        return true
    }

    /// Marks a goal block done, or not done. Done blocks add their length to the goal. One undo step.
    func toggleGoalBlockDone(eventId: String) {
        guard let old = try? repos.events.get(eventId), old.goalId != nil else { return }
        var new = old
        new.doneAt = old.doneAt == nil ? Stamp.now() : nil
        var m = Mutation(name: new.doneAt == nil ? "Reopen Goal Block" : "Complete Goal Block")
        m.events.append((old, new))
        commit(m)
    }
}
