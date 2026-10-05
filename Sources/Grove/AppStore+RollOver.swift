import Foundation
import GroveCore

/// The end-of-day card (PLAN §5.1.7). `RollOver` has the rules.
extension AppStore {
    /// The day the card is about. Uses the test clock when one is set.
    private var rollOverToday: DayKey { reminderNow().day }

    /// What the card offers: open tasks that had a block yesterday. Empty once the person answered today.
    func rollOverItems() -> [RollOverItem] {
        let today = rollOverToday
        guard !RollOver.isHandled(repos, today: today) else { return [] }
        return (try? RollOver.items(repos, today: today)) ?? []
    }

    /// "Move to today": the tasks get today as their day and lose yesterday's blocks, so they show as sticky notes.
    /// One undo step.
    func moveRollOver() {
        let today = rollOverToday
        var m = Mutation(name: "Move to Today")
        for item in rollOverItems() {
            m.tasks.append((item.task, placed(item.task, in: .day(today))))
            for b in item.blocks { m.events.append((b, nil)) }
        }
        commit(m)
        RollOver.markHandled(repos, today: today)
        revision += 1
    }

    /// "Leave": nothing changes. The card does not come back today.
    func leaveRollOver() {
        RollOver.markHandled(repos, today: rollOverToday)
        revision += 1
    }
}
