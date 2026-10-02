import Testing
@testable import GroveCore

struct PlannerMathTests {
    func span(_ id: String, _ s: Int, _ e: Int) -> Span { Span(id: id, start: s, end: e) }

    // MARK: snap
    @Test func snapsToNearestStepBothWays() {
        #expect(PlannerMath.snap(62, step: 5) == 60)
        #expect(PlannerMath.snap(63, step: 5) == 65)
        #expect(PlannerMath.snap(67, step: 15) == 60)
        #expect(PlannerMath.snap(68, step: 15) == 75)
        #expect(PlannerMath.snap(63, step: 1) == 63)
    }

    // MARK: clamp
    @Test func clampMoveKeepsBlockInsideDay() {
        #expect(PlannerMath.clampMove(start: -30, length: 60) == 0)
        #expect(PlannerMath.clampMove(start: 1430, length: 60) == 1380)
        #expect(PlannerMath.clampMove(start: 600, length: 60) == 600)
    }

    // MARK: resize
    @Test func resizeTopHasFiveMinuteMinimum() {
        #expect(PlannerMath.resizeTop(start: 600, end: 660, newStart: 640, step: 5) == (640, 660))
        #expect(PlannerMath.resizeTop(start: 600, end: 660, newStart: 700, step: 5) == (655, 660))
        #expect(PlannerMath.resizeTop(start: 600, end: 660, newStart: -20, step: 5) == (0, 660))
        #expect(PlannerMath.resizeTop(start: 600, end: 660, newStart: 612, step: 5) == (610, 660))
    }

    @Test func resizeBottomHasFiveMinuteMinimum() {
        #expect(PlannerMath.resizeBottom(start: 600, end: 660, newEnd: 700, step: 5) == (600, 700))
        #expect(PlannerMath.resizeBottom(start: 600, end: 660, newEnd: 500, step: 5) == (600, 605))
        #expect(PlannerMath.resizeBottom(start: 600, end: 660, newEnd: 1500, step: 5) == (600, 1440))
    }

    // MARK: layout
    @Test func layoutNoOverlapGivesOneColumnEach() {
        let p = PlannerMath.layoutColumns([span("a", 0, 60), span("b", 120, 180)])
        #expect(p["a"] == Placement(column: 0, columns: 1))
        #expect(p["b"] == Placement(column: 0, columns: 1))
    }

    @Test func layoutTwoOverlappingGivesTwoColumns() {
        let p = PlannerMath.layoutColumns([span("a", 0, 60), span("b", 30, 90)])
        #expect(p["a"] == Placement(column: 0, columns: 2))
        #expect(p["b"] == Placement(column: 1, columns: 2))
    }

    @Test func layoutChainReusesColumnZero() {
        // A overlaps B, B overlaps C, A does not overlap C.
        let p = PlannerMath.layoutColumns([span("a", 0, 60), span("b", 30, 90), span("c", 60, 120)])
        #expect(p["a"]?.column == 0)
        #expect(p["b"]?.column == 1)
        #expect(p["c"]?.column == 0)
        #expect(p.values.allSatisfy { $0.columns == 2 })
    }

    @Test func touchingBlocksDoNotOverlap() {
        let p = PlannerMath.layoutColumns([span("a", 0, 60), span("b", 60, 120)])
        #expect(p["a"] == Placement(column: 0, columns: 1))
        #expect(p["b"] == Placement(column: 0, columns: 1))
    }

    @Test func layoutIsStableForEmptyInput() {
        #expect(PlannerMath.layoutColumns([]).isEmpty)
    }

    // MARK: ripple
    @Test func rippleCascadesThroughThreeBlocks() {
        let moved = span("m", 600, 660)
        let others = [span("a", 630, 690), span("b", 690, 750), span("c", 750, 780)]
        let out = PlannerMath.ripple(moved: moved, others: others)
        let byId = Dictionary(uniqueKeysWithValues: out.map { ($0.id, $0) })
        #expect(byId["a"] == span("a", 660, 720))
        #expect(byId["b"] == span("b", 720, 780))
        #expect(byId["c"] == span("c", 780, 810))
    }

    @Test func rippleReturnsOnlyChangedBlocks() {
        let moved = span("m", 600, 660)
        let others = [span("before", 540, 600), span("hit", 630, 690), span("far", 900, 960)]
        let out = PlannerMath.ripple(moved: moved, others: others)
        #expect(out.map(\.id) == ["hit"])
    }

    @Test func rippleClampsAtEndOfDay() {
        let moved = span("m", 1380, 1440)
        let out = PlannerMath.ripple(moved: moved, others: [span("a", 1400, 1430)])
        #expect(out == [span("a", 1410, 1440)])
    }

    // MARK: free slot
    @Test func firstFreeSlotFindsGap() {
        let busy = [span("a", 540, 600), span("b", 630, 700)]
        #expect(PlannerMath.firstFreeSlot(length: 30, busy: busy, from: 540, until: 1080, step: 5) == 600)
        #expect(PlannerMath.firstFreeSlot(length: 45, busy: busy, from: 540, until: 1080, step: 5) == 700)
        #expect(PlannerMath.firstFreeSlot(length: 30, busy: [], from: 543, until: 1080, step: 5) == 545)
    }

    @Test func firstFreeSlotReturnsNilWhenFull() {
        #expect(PlannerMath.firstFreeSlot(length: 30, busy: [span("a", 540, 1080)], from: 540, until: 1080, step: 5) == nil)
        #expect(PlannerMath.firstFreeSlot(length: 30, busy: [], from: 1060, until: 1080, step: 5) == nil)
    }

    // MARK: label
    @Test func labelFormatsDuration() {
        #expect(PlannerMath.label(start: 675, end: 765) == "11:15 – 12:45 · 1h 30m")
        #expect(PlannerMath.label(start: 540, end: 585) == "09:00 – 09:45 · 45m")
        #expect(PlannerMath.label(start: 540, end: 600) == "09:00 – 10:00 · 1h")
        #expect(PlannerMath.label(start: 1380, end: 1440) == "23:00 – 24:00 · 1h")
    }
}
