import Testing
import CoreGraphics
@testable import Grove

struct PlannerRulesTests {
    @Test func trayNeedsRoomForItselfAndAReadableGrid() {
        #expect(PlannerLayoutRules.trayFits(contentWidth: 900))
        #expect(PlannerLayoutRules.trayFits(contentWidth: PlannerLayoutRules.trayMinContentWidth))
        #expect(!PlannerLayoutRules.trayFits(contentWidth: PlannerLayoutRules.trayMinContentWidth - 1))
    }

    @Test func taskListAndInspectorTogetherLeaveNoRoomForTheTrayAtTheDefaultWindow() {
        // 1280 window − task list 320 − inspector 340 − the planner's own side padding 32.
        #expect(!PlannerLayoutRules.trayFits(contentWidth: 1280 - 320 - 340 - 32))
        // With only the task list open there is room.
        #expect(PlannerLayoutRules.trayFits(contentWidth: 1280 - 320 - 32))
    }
}
