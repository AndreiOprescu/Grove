import Testing
import Foundation
import GroveCore
@testable import Grove

/// The chosen theme and the motion switch on a real store. They are saved, so the next launch looks the same.
@MainActor
@Suite(.serialized)
struct ThemeStoreTests {
    private let defaults = UserDefaults.standard
    private let keys = ["appearance.theme", "appearance.motion"]

    private func clean() { keys.forEach(defaults.removeObject(forKey:)) }
    private func makeStore() throws -> AppStore { AppStore(repos: Repos(db: try Database.inMemory())) }

    @Test func theDefaultIsGroveWithMotionOn() throws {
        clean(); defer { clean() }
        let s = try makeStore()
        #expect(s.themeID == .grove)
        #expect(s.motionSetting)
    }

    @Test func aChosenThemeIsSavedAndComesBack() throws {
        clean(); defer { clean() }
        try makeStore().setTheme(.vintage)
        #expect(defaults.string(forKey: "appearance.theme") == "vintage")
        #expect(try makeStore().themeID == .vintage)
    }

    @Test func anUnknownSavedThemeFallsBackToGrove() throws {
        clean(); defer { clean() }
        defaults.set("neon-rainbow", forKey: "appearance.theme")
        #expect(try makeStore().themeID == .grove)
    }

    @Test func nextThemeWalksTheListAndWrapsAround() throws {
        clean(); defer { clean() }
        let s = try makeStore()
        var seen: [ThemeID] = []
        for _ in 0..<5 { s.nextTheme(); seen.append(s.themeID) }
        #expect(seen == [.minimal, .futuristic, .vintage, .grove, .minimal])
    }

    @Test func theMotionSwitchIsSaved() throws {
        clean(); defer { clean() }
        let s = try makeStore()
        s.setMotion(false)
        #expect(!s.motionSetting)
        #expect(try !makeStore().motionSetting)
        s.setMotion(true)
        #expect(try makeStore().motionSetting)
    }

    @Test func theThemeCommandsRunFromThePalette() throws {
        clean(); defer { clean() }
        let s = try makeStore()
        s.run(.toggleTheme)
        #expect(s.themeID == .minimal)
        s.run(.toggleMotion)
        #expect(!s.motionSetting)
        #expect(!s.paletteOpen)
    }

    @Test func theThemeIsLiveInTheStore() throws {
        clean(); defer { clean() }
        let s = try makeStore()
        s.setTheme(.futuristic)
        #expect(s.theme.kind == .futuristic)
        #expect(s.colorScheme == .dark)
        s.setTheme(.grove)
        #expect(s.colorScheme == nil)
    }
}
