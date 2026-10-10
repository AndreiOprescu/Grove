import Foundation
import GroveCore

/// Subtasks of one goal block. Each block has its own list: another block of the same goal does not share it.
/// Every change is one undo step.
extension AppStore {
    func blockSubtasks(of eventId: String) -> [BlockSubtaskItem] {
        (try? repos.blockSubtasks.forEvent(eventId)) ?? []
    }

    /// Adds a subtask at the end of the block's list. Nil when the title is empty or the block is not a goal block.
    @discardableResult
    func addBlockSubtask(to eventId: String, title: String) -> String? {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let e = try? repos.events.get(eventId), e.goalId != nil else { return nil }
        let sort = (blockSubtasks(of: eventId).map(\.sort).max() ?? 0) + 1
        let sub = BlockSubtaskItem(eventId: eventId, title: name, sort: sort)
        var m = Mutation(name: "New Subtask")
        m.blockSubtasks.append((nil, sub))
        guard commit(m) else { return nil }
        return sub.id
    }

    /// Ticks a subtask done, or back to open. The block itself stays as it is.
    func toggleBlockSubtask(_ id: String) {
        guard let old = try? repos.blockSubtasks.get(id) else { return }
        var new = old
        new.doneAt = old.doneAt == nil ? Stamp.now() : nil
        var m = Mutation(name: new.doneAt == nil ? "Reopen Subtask" : "Complete Subtask")
        m.blockSubtasks.append((old, new))
        commit(m)
    }

    /// Saves a new title. Does nothing when the title is empty or the same.
    func renameBlockSubtask(_ id: String, to raw: String) {
        guard let old = try? repos.blockSubtasks.get(id), let name = SubtaskRules.renamed(raw, from: old.title) else { return }
        var new = old
        new.title = name
        var m = Mutation(name: "Rename Subtask")
        m.blockSubtasks.append((old, new))
        commit(m)
    }

    func deleteBlockSubtask(_ id: String) {
        guard let old = try? repos.blockSubtasks.get(id) else { return }
        var m = Mutation(name: "Delete Subtask")
        m.blockSubtasks.append((old, nil))
        commit(m)
    }

    // MARK: The popover

    /// Opens the subtask popover on a goal block, or on an old goal block that still has subtasks.
    func openBlockSubtasks(_ eventId: String) {
        guard let e = try? repos.events.get(eventId), e.taskId == nil,
              e.goalId != nil || !blockSubtasks(of: eventId).isEmpty else { return }
        editingBlockSubtasks = eventId
    }

    func closeBlockSubtasks() { editingBlockSubtasks = nil }
}
