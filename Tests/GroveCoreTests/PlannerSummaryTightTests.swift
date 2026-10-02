import Testing
@testable import GroveCore

/// A block that shows a short description has three text rows, so it stays "tight" for longer.
struct PlannerSummaryTightTests {
    @Test func aParentCanHaveItsOwnTightLimit() {
        let spans = [Span(id: "p", start: 0, end: 120), Span(id: "c", start: 40, end: 60)]
        // Same limit for everyone: 40 minutes is not less than 30, so the child is not tight.
        #expect(PlannerMath.layoutLayers(spans, minLength: 0, tightWithin: 30)["c"]?.tight == false)
        // The parent has a short description, so it keeps 45 minutes for itself.
        #expect(PlannerMath.layoutLayers(spans, minLength: 0, tightWithin: 30, tightWithinById: ["p": 45])["c"]?.tight == true)
        // A limit for another block changes nothing.
        #expect(PlannerMath.layoutLayers(spans, minLength: 0, tightWithin: 30, tightWithinById: ["x": 45])["c"]?.tight == false)
    }
}
