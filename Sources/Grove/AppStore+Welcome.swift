import Foundation
import GroveCore

/// The welcome card and the sample tasks (PLAN §9). `FirstRun` has the rules.
extension AppStore {
    /// "Got it": hides the card. The sample tasks stay.
    func dismissWelcome() {
        FirstRun.dismissWelcome(repos)
        welcomeVisible = false
        askForNotificationsAfterWelcome()
    }

    /// "Remove samples": deletes the sample tasks that are still there, as one undo step.
    func removeSamples() {
        var m = Mutation(name: "Remove Samples")
        for id in FirstRun.sampleTaskIds(repos) {
            if let one = deletion(ofTask: id, name: "Remove Samples") { m.append(one) }
        }
        commit(m)
        FirstRun.forgetSamples(repos)
        welcomeVisible = false
        askForNotificationsAfterWelcome()
    }

    /// Grove asks the Mac for notifications after the welcome card, not at once (PLAN §5.6).
    /// It asks only when the Mac has not been asked before.
    private func askForNotificationsAfterWelcome() {
        welcomeAsk = Task { [weak self] in
            guard let self else { return }
            await self.refreshNotifyStatus()
            if self.notifyStatus == .notAsked { await self.askForNotifications() }
        }
    }
}
