import Testing
import Foundation
import SwiftUI
@testable import Grove

/// The four themes as plain numbers (PLAN §6.1): the tokens, the light and dark variants, the contrast.
struct ThemeSpecTests {
    // MARK: The list

    @Test func fourThemesInTheOrderOfThePlan() {
        #expect(ThemeID.allCases == [.grove, .minimal, .futuristic, .vintage])
        #expect(ThemeSpec.all.map(\.id) == ThemeID.allCases)
        #expect(ThemeID.default == .grove)
    }

    @Test func everyThemeHasAName() {
        #expect(ThemeSpec.all.map(\.name) == ["Grove", "Minimal", "Futuristic", "Vintage"])
    }

    // MARK: Tokens

    @Test func groveTokensMatchThePlan() {
        let s = ThemeSpec.spec(.grove)
        #expect(s.bg.light == 0xF3EEE3 && s.bg.dark == 0x171C16)
        #expect(s.surface.light == 0xFBF8F1 && s.surface.dark == 0x1F261D)
        #expect(s.ink.light == 0x2F3A2C && s.ink.dark == 0xE6E9DF)
        #expect(s.accent.light == 0x5E7F4F && s.accent.dark == 0x8DB57A)
        #expect(s.radius == 16)
    }

    @Test func minimalTokensMatchThePlan() {
        let s = ThemeSpec.spec(.minimal)
        #expect(s.bg.light == 0xF7F7F5 && s.bg.dark == 0x121212)
        #expect(s.accent.light == 0x1B1B1A && s.accent.dark == 0xEDEDEA)
        #expect(s.accent2.light == 0x7C9A7E && s.accent2.dark == 0x93B596)
        #expect(s.radius == 10)
    }

    @Test func futuristicTokensMatchThePlan() {
        let s = ThemeSpec.spec(.futuristic)
        #expect(s.bg.dark == 0x070B16)
        #expect(s.ink.dark == 0xE4F0FF)
        #expect(s.accent.dark == 0x46F0D2 && s.accent2.dark == 0xA27BFF && s.accent3.dark == 0xFF6FB5)
        #expect(s.surface.dark == 0x161E3A && s.surface.darkAlpha == 0.55)
        #expect(s.surface2.dark == 0x3C508C && s.surface2.darkAlpha == 0.22)
        #expect(s.line.dark == 0x78A0FF && s.line.darkAlpha == 0.20)
        #expect(s.radius == 14)
    }

    @Test func vintageTokensMatchThePlan() {
        let s = ThemeSpec.spec(.vintage)
        #expect(s.bg.light == 0xE6D8BA && s.surface.light == 0xF3E9D2)
        #expect(s.accent.light == 0x8C3B2E && s.accent2.light == 0x3F5B4A && s.accent3.light == 0xB8862B)
        #expect(s.line.light == 0xC8B38D)
        #expect(s.radius == 3)
    }

    // MARK: Light and dark

    @Test func groveAndMinimalFollowTheSystem() {
        #expect(ThemeSpec.spec(.grove).scheme == .system)
        #expect(ThemeSpec.spec(.minimal).scheme == .system)
        #expect(ThemeSpec.spec(.grove).colorScheme == nil)
    }

    @Test func futuristicIsDarkOnlyAndVintageIsLightOnly() {
        #expect(ThemeSpec.spec(.futuristic).scheme == .dark)
        #expect(ThemeSpec.spec(.futuristic).colorScheme == .dark)
        #expect(ThemeSpec.spec(.vintage).scheme == .light)
        #expect(ThemeSpec.spec(.vintage).colorScheme == .light)
    }

    @Test func aLockedThemeLooksTheSameInBothVariants() {
        for id in [ThemeID.futuristic, .vintage] {
            let s = ThemeSpec.spec(id)
            for t in s.allTones { #expect(t.light == t.dark && t.lightAlpha == t.darkAlpha) }
        }
    }

    // MARK: Blobs

    @Test func everyThemeHasThreeBlobs() {
        for s in ThemeSpec.all { #expect(s.blobs.count == 3) }
    }

    @Test func blobsAreFainterInMinimalAndFuturistic() {
        #expect(ThemeSpec.spec(.grove).blobOpacity == 0.55)
        #expect(ThemeSpec.spec(.vintage).blobOpacity == 0.55)
        #expect(ThemeSpec.spec(.minimal).blobOpacity == 0.35)
        #expect(ThemeSpec.spec(.futuristic).blobOpacity == 0.35)
    }

    // MARK: Contrast (PLAN §10: ink on surface at least 4.5 to 1 in every theme)

    @Test func contrastMathKnowsTheExtremes() {
        #expect(abs(ColorMath.contrast(0x000000, 0xFFFFFF) - 21) < 0.001)
        #expect(abs(ColorMath.contrast(0x777777, 0x777777) - 1) < 0.001)
    }

    @Test func halfWhiteOverBlackIsGrey() {
        #expect(ColorMath.over(0xFFFFFF, alpha: 0.5, on: 0x000000) == 0x808080)
        #expect(ColorMath.over(0x123456, alpha: 1, on: 0xFFFFFF) == 0x123456)
        #expect(ColorMath.over(0x123456, alpha: 0, on: 0xFFFFFF) == 0xFFFFFF)
    }

    @Test func inkReadsOnEveryLayerInEveryVariant() {
        for s in ThemeSpec.all {
            for dark in [false, true] {
                let bg = s.bg.rgb(dark: dark)
                let surface = ColorMath.over(s.surface.rgb(dark: dark), alpha: s.surface.alpha(dark: dark), on: bg)
                let surface2 = ColorMath.over(s.surface2.rgb(dark: dark), alpha: s.surface2.alpha(dark: dark), on: surface)
                let ink = s.ink.rgb(dark: dark)
                for (name, layer) in [("bg", bg), ("surface", surface), ("surface2", surface2)] {
                    let ratio = ColorMath.contrast(ink, layer)
                    #expect(ratio >= 4.5, "\(s.name) \(dark ? "dark" : "light"): ink on \(name) is \(ratio)")
                }
            }
        }
    }

    // MARK: The SwiftUI theme

    @Test func aThemeCarriesItsSpec() {
        for id in ThemeID.allCases {
            let t = Theme.make(id)
            #expect(t.kind == id)
            #expect(t.id == id.rawValue)
            #expect(t.radius == ThemeSpec.spec(id).radius)
        }
    }

    @Test func personalityFollowsThePlan() {
        let g = Theme.make(.grove), m = Theme.make(.minimal), f = Theme.make(.futuristic), v = Theme.make(.vintage)
        #expect(!g.squareChecks && !m.squareChecks && f.squareChecks && v.squareChecks)
        #expect(f.glass && !g.glass && !m.glass && !v.glass)
        #expect(v.paper && !g.paper)
        #expect(f.gridLines && !v.gridLines)
        #expect(f.upperHeadings && !g.upperHeadings)
        #expect(m.hairlines && !g.hairlines)
    }
}

/// The moving background and the motion switch (PLAN §6.3).
struct AmbientMotionTests {
    @Test func theThreePeriodsAre22And28And34Seconds() {
        #expect(AmbientMath.periods == [22, 28, 34])
    }

    @Test func aBlobStaysNearTheWindowAtAnyTime() {
        for i in 0..<3 {
            for t in stride(from: 0.0, through: 200, by: 1.7) {
                let c = AmbientMath.centre(index: i, time: t)
                #expect(c.x > 0.1 && c.x < 0.9 && c.y > 0.1 && c.y < 0.9)
            }
        }
    }

    @Test func aBlobMovesSlowly() {
        let a = AmbientMath.centre(index: 0, time: 10), b = AmbientMath.centre(index: 0, time: 11)
        let step = hypot(a.x - b.x, a.y - b.y)
        #expect(step > 0 && step < 0.08)   // under 8% of the window in one second
    }

    @Test func theBlobsDoNotMoveTogether() {
        let a = AmbientMath.centre(index: 0, time: 5), b = AmbientMath.centre(index: 1, time: 5)
        #expect(a.x != b.x || a.y != b.y)
    }

    @Test func aBlobIs46PercentOfTheLongSide() {
        #expect(abs(AmbientMath.diameter(width: 1000, height: 600) - 460) < 0.001)
        #expect(abs(AmbientMath.diameter(width: 600, height: 1000) - 460) < 0.001)
    }

    @Test func motionNeedsTheSwitchAndNoReduceMotion() {
        #expect(MotionRules.isOn(setting: true, reduceMotion: false))
        #expect(!MotionRules.isOn(setting: false, reduceMotion: false))
        #expect(!MotionRules.isOn(setting: true, reduceMotion: true))
        #expect(!MotionRules.isOn(setting: false, reduceMotion: true))
    }

    @Test func theBackgroundOnlyRunsInTheKeyWindow() {
        #expect(MotionRules.ambientRuns(motionOn: true, windowIsKey: true))
        #expect(!MotionRules.ambientRuns(motionOn: true, windowIsKey: false))
        #expect(!MotionRules.ambientRuns(motionOn: false, windowIsKey: true))
    }
}
