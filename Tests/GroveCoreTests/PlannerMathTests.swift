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

    // MARK: layout (overlaps cascade, they never share the width)
    private func layers(_ spans: [Span], minLength: Int = 0, tightWithin: Int = 30) -> [String: Layer] {
        PlannerMath.layoutLayers(spans, minLength: minLength, tightWithin: tightWithin)
    }

    @Test func noOverlapMeansNoLayers() {
        let l = layers([span("a", 0, 60), span("b", 120, 180)])
        #expect(l["a"]?.depth == 0 && l["a"]?.parent == nil)
        #expect(l["b"]?.depth == 0 && l["b"]?.parent == nil)
    }

    @Test func touchingBlocksDoNotOverlap() {
        let l = layers([span("a", 0, 60), span("b", 60, 120)])
        #expect(l["a"]?.depth == 0 && l["b"]?.depth == 0)
    }

    @Test func shortBlockInsideALongOneSitsOnTopOfIt() throws {
        // 09:00-14:00 with a 5 minute block at 11:00. The long block keeps the whole width.
        let l = layers([span("short", 660, 665), span("long", 540, 840)])
        #expect(l["long"]?.depth == 0 && l["long"]?.parent == nil)
        #expect(l["short"]?.depth == 1 && l["short"]?.parent == "long")
        #expect(l["short"]?.tight == false)
        let under = try #require(l["long"]), over = try #require(l["short"])
        #expect(under.order < over.order)   // painted first = underneath
    }

    @Test func blocksStartingTogetherPutTheLongOneUnder() {
        let l = layers([span("short", 540, 545), span("long", 540, 840)])
        #expect(l["long"]?.depth == 0)
        #expect(l["short"]?.parent == "long")
        #expect(l["short"]?.tight == true)   // would hide the long block's title, so it is pushed right
    }

    @Test func aBlockStartingJustAfterAnotherIsTight() {
        let l = layers([span("a", 540, 600), span("b", 550, 610)], tightWithin: 30)
        #expect(l["b"]?.tight == true)
        let far = layers([span("a", 540, 600), span("b", 580, 640)], tightWithin: 30)
        #expect(far["b"]?.tight == false)
    }

    @Test func chainOfOverlapsStepsDownOneLevelEach() {
        let l = layers([span("a", 0, 60), span("b", 30, 90), span("c", 60, 120)], tightWithin: 10)
        #expect(l["a"]?.depth == 0)
        #expect(l["b"]?.depth == 1 && l["b"]?.parent == "a")
        #expect(l["c"]?.depth == 2 && l["c"]?.parent == "b")
    }

    @Test func aBlockSitsOnTheMostIndentedBlockUnderIt() {
        // c overlaps both a and b. b is already indented on a, so c must sit on b to stay clear of both.
        let l = layers([span("a", 0, 300), span("b", 60, 120), span("c", 90, 150)], tightWithin: 10)
        #expect(l["b"]?.parent == "a")
        #expect(l["c"]?.parent == "b")
        #expect(l["c"]?.depth == 2)
    }

    @Test func tinyBlocksCountAsTallAsTheyAreDrawn() {
        // A 10 minute block is drawn at least 20 minutes tall, so a block that starts at minute 12 is covered by it.
        let spans = [span("a", 0, 10), span("b", 12, 60)]
        #expect(layers(spans, minLength: 0)["b"]?.depth == 0)
        let drawn = layers(spans, minLength: 20)
        #expect(drawn["b"]?.parent == "a" && drawn["b"]?.tight == true)
    }

    @Test func paintOrderIsStartTimeThenLongestFirst() throws {
        let l = layers([span("late", 100, 130), span("short", 0, 10), span("long", 0, 90)])
        #expect(l.values.sorted { $0.order < $1.order }.map(\.order) == [0, 1, 2])
        #expect(l["long"]?.order == 0)
        #expect(l["short"]?.order == 1)
        #expect(l["late"]?.order == 2)
    }

    @Test func layoutIsStableForEmptyInput() {
        #expect(layers([]).isEmpty)
    }

    @Test func indentsAddUpAlongTheChainAndStopAtTheMaximum() {
        let l = layers([span("a", 0, 300), span("b", 100, 200), span("c", 150, 250), span("d", 160, 240)], tightWithin: 30)
        let ind = PlannerMath.indents(l, far: 14, tight: { _ in 60 }, maxIndent: 100)
        #expect(ind["a"] == 0)
        #expect(ind["b"] == 14)            // far from a
        #expect(ind["c"] == 28)            // far from b (start 50 minutes later)
        #expect(ind["d"] == 88)            // tight on c (starts 10 minutes after it)
        let capped = PlannerMath.indents(l, far: 14, tight: { _ in 60 }, maxIndent: 50)
        #expect(capped["d"] == 50)
    }

    @Test func aLongBlockThatNothingCoversHasNoIndent() {
        let l = layers([span("long", 0, 600), span("x", 100, 105)])
        #expect(PlannerMath.indents(l, far: 14, tight: { _ in 60 }, maxIndent: 100)["long"] == 0)
    }

    @Test func tightShiftCanDependOnTheBlockUnderneath() {
        // The shift reveals the title of the block below, so a longer title can ask for a bigger shift.
        let l = layers([span("wide", 0, 300), span("a", 0, 10), span("b", 5, 15)], tightWithin: 30)
        let ind = PlannerMath.indents(l, far: 14, tight: { $0 == "wide" ? 40 : 90 }, maxIndent: 500)
        #expect(ind["a"] == 40)             // sits on "wide"
        #expect(ind["b"] == 130)            // sits on "a": 40 + 90
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
