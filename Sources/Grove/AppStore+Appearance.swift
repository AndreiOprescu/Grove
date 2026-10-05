import SwiftUI
import GroveCore

/// The theme and the motion switch (PLAN §6, §5.8). They are view preferences of this Mac, so they live in
/// UserDefaults like the planner settings.
extension AppStore {
    var theme: Theme { Theme.make(themeID) }

    /// The look the window is forced into. nil follows the Mac (Grove, Minimal).
    var colorScheme: ColorScheme? { ThemeSpec.spec(themeID).colorScheme }

    /// Switches live: the colours cross-fade in 0.35 s.
    func setTheme(_ id: ThemeID) {
        guard id != themeID else { return }
        withAnimation(.easeInOut(duration: 0.35)) { themeID = id }
        UserDefaults.standard.set(id.rawValue, forKey: "appearance.theme")
    }

    func nextTheme() { setTheme(themeID.next) }

    func setMotion(_ on: Bool) {
        motionSetting = on
        UserDefaults.standard.set(on, forKey: "appearance.motion")
        showToast(on ? "Motion on" : "Motion off")
    }
}

extension AppStore {
    /// How many of a day's tasks are done. Tasks planned for that day count; cancelled ones do not.
    func plantProgress(on day: DayKey) -> PlantProgress {
        let tasks = (try? repos.tasks.forDay(day)) ?? []
        return PlantProgress(done: tasks.filter(\.isDone).count, total: tasks.count)
    }
}

/// When the moving parts may move (PLAN §6.3).
enum MotionRules {
    /// The Motion switch must be on, and the Mac must not ask to reduce motion.
    static func isOn(setting: Bool, reduceMotion: Bool) -> Bool { setting && !reduceMotion }

    /// The ambient background only draws while the window is the key window, to save energy.
    static func ambientRuns(motionOn: Bool, windowIsKey: Bool) -> Bool { motionOn && windowIsKey }
}

extension AppStore {
    /// How many tasks are finished. The Garden plant grows with this number.
    func gardenDone() -> Int { (try? repos.tasks.doneCount()) ?? 0 }
}
