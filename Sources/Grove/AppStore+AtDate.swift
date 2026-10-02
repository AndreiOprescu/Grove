import Foundation
import GroveCore

/// A line with `@fri 3pm` in a note goes to the planner (PLAN §5.5 item 2).
extension AppStore {
    /// Makes the event, or the task and its block, that the line asks for. One undo step.
    /// - A line with no check box makes an event: one hour long, or all day when the token has no time.
    /// - An open check box makes a task and a block of half an hour. A task the box already has is moved there.
    /// - Returns the text the line becomes, or nil when the line cannot go (no token, a ticked box, no words).
    ///   The editor writes the text into the note. It keeps the link to the new item.
    func addToPlanner(line: String, inNote noteId: String) -> String? {
        guard let source = note(noteId),
              let plan = AtDatePlanner.plan(line: line, noteDay: source.kind == .daily ? source.date : nil) else { return nil }
        var change = Mutation(name: "Add to Planner")
        let text: String
        if plan.isTask {
            guard let made = taskChange(plan, from: source, into: &change) else { return nil }
            text = made
        } else {
            let span = AtDatePlanner.span(plan, defaultMinutes: AtDatePlan.eventMinutes)
            let event = EventItem(title: plan.title, start: WallTime(day: plan.day, minute: span?.start ?? 0),
                                  end: WallTime(day: plan.day, minute: span?.end ?? 0), allDay: span == nil,
                                  notes: ReferenceParser.mention(title: source.title, id: source.id))
            change.events.append((nil, event))
            text = AtDatePlanner.eventLine(plan, mention: ReferenceParser.mention(title: event.title, id: event.id),
                                           when: AtDatePlanner.whenLabel(day: plan.day, start: span?.start, end: span?.end))
        }
        guard commit(change) else { return nil }
        showToast("Added to the planner: \(plan.title)")
        return text
    }

    /// The task and block of a check box line, added to `change`. Returns the new text of the line.
    private func taskChange(_ plan: AtDatePlan, from source: Note, into change: inout Mutation) -> String? {
        var task: TaskItem
        if let id = plan.taskId, let old = self.task(id) {
            task = old
            change.tasks.append((old, task))
        } else {
            guard var made = quickAddChange(plan.title, default: .day(plan.day), notes: origin(of: source)) else { return nil }
            made.change.events = []   // words in the title may have asked for a block. The token decides.
            change = made.change
            change.name = "Add to Planner"
            task = made.task
        }
        // A block that is already there keeps its length unless the token gives one.
        let existing = blocks(ofTask: task.id).first
        let length = plan.durationMin.map { max(5, $0) } ?? existing?.durationMinutes ?? task.estimateMin
        let span = AtDatePlanner.span(plan, defaultMinutes: length)
        task = planned(task, on: plan.day)
        if let span, plan.durationMin != nil || existing == nil { task.estimateMin = span.end - span.start }
        change.tasks[change.tasks.count - 1].after = task

        if let span {
            if var block = existing {
                let old = block
                block.start = WallTime(day: plan.day, minute: span.start)
                block.end = WallTime(day: plan.day, minute: span.end)
                change.events.append((old, block))
            } else {
                change.events.append((nil, blockEvent(for: task, day: plan.day, start: span.start, end: span.end)))
            }
        }
        return AtDatePlanner.taskLine(plan, taskId: task.id,
                                      when: AtDatePlanner.whenLabel(day: plan.day, start: span?.start, end: span?.end))
    }
}

/// A note dragged onto the planner (PLAN §5.5 item 8).
extension AppStore {
    /// Puts a note on a day and time: an event of half an hour, "📝 <note title>", with a link to the note in its notes.
    /// One undo step. Returns the event. Nil when the note is gone.
    @discardableResult
    func addNoteToPlanner(_ noteId: String, on day: DayKey, at minute: Int) -> EventItem? {
        guard let source = note(noteId) else { return nil }
        let length = AtDatePlan.blockMinutes
        let start = PlannerMath.clampMove(start: minute, length: length)
        let name = source.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let event = EventItem(title: "📝 " + (name.isEmpty ? "Untitled" : name),
                              start: WallTime(day: day, minute: start), end: WallTime(day: day, minute: start + length),
                              notes: ReferenceParser.mention(title: source.title, id: source.id))
        var change = Mutation(name: "Add Note to Planner")
        change.events.append((nil, event))
        guard commit(change) else { return nil }
        selection = [event.id]
        return event
    }
}
