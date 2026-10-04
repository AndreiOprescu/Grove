import Testing
import CoreGraphics
@testable import Grove

struct PlannerRulesTests {
    @Test func aStickyNoteKeepsItsColourAndTilt() {
        // The same task always looks the same, also after a restart (no random hash).
        #expect(StickyRules.colorIndex(for: "task-1") == StickyRules.colorIndex(for: "task-1"))
        #expect(StickyRules.tilt(for: "task-1") == StickyRules.tilt(for: "task-1"))
        #expect(StickyRules.stableHash("abc") == 440920331)
    }

    @Test func stickyNotesUseTheThreeAccentsAndTiltOnlyALittle() {
        let ids = (0..<40).map { "id-\($0)" }
        let colours = Set(ids.map(StickyRules.colorIndex(for:)))
        #expect(colours == [0, 1, 2])
        let tilts = ids.map(StickyRules.tilt(for:))
        #expect(tilts.allSatisfy { abs($0) <= 1.5 })
        #expect(Set(tilts).count > 1)
    }

    @Test func theStripGrowsWithItsNotesUpToALimit() {
        #expect(StickyRules.stripHeight(content: 70) == 70)
        #expect(StickyRules.stripHeight(content: 600) == StickyRules.maxHeight)
        #expect(StickyRules.stripHeight(content: 0) == StickyRules.foldedHeight)
    }
}
