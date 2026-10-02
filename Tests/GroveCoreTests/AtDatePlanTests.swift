import Testing
import Foundation
@testable import GroveCore

/// Reading an `@date` line and writing it back (PLAN §5.5 item 2).
struct AtDatePlanTests {
    let friday = DayKey("2026-10-02")
    let saturday = DayKey("2026-10-03")

    private func plan(_ line: String, noteDay: DayKey? = nil) -> AtDatePlan? {
        AtDatePlanner.plan(line: line, noteDay: noteDay, today: friday)
    }

    @Test func aPlainLineIsAnEvent() throws {
        let p = try #require(plan("Call Sam @tomorrow 3pm"))
        #expect(p.title == "Call Sam" && !p.isTask && p.taskId == nil)
        #expect(p.day == saturday && p.startMinute == 900 && p.durationMin == nil)
        #expect(p.head == "")
    }

    @Test func anOpenBoxIsATask() throws {
        let p = try #require(plan("- [ ] Write report @tomorrow 9am for 2h"))
        #expect(p.title == "Write report" && p.isTask && p.taskId == nil)
        #expect(p.startMinute == 540 && p.durationMin == 120)
        #expect(p.head == "- [ ] ")
    }

    @Test func aBoxThatHasATaskKeepsItsId() throws {
        let p = try #require(plan("- [ ] Write report @tomorrow 9am ⟦t:ABC⟧"))
        #expect(p.taskId == "ABC" && p.title == "Write report")
    }

    @Test func aTickedBoxIsRefused() {
        #expect(plan("- [x] Write report @tomorrow 9am") == nil)
    }

    @Test func aLineWithoutATokenIsRefused() {
        #expect(plan("Call Sam tomorrow") == nil)
        #expect(plan("mail me@home.com") == nil)
    }

    @Test func aTokenWithNoWordsAroundItIsRefused() {
        #expect(plan("@tomorrow 3pm") == nil)
        #expect(plan("- [ ] @tomorrow") == nil)
    }

    @Test func theTokenCanSitInTheMiddleOfTheWords() throws {
        #expect(try #require(plan("Call @tomorrow 3pm Sam")).title == "Call Sam")
    }

    @Test func aTimeAloneTakesTheNoteDayThenToday() throws {
        let other = DayKey("2026-10-20")
        let a = try #require(plan("Standup @14:00", noteDay: other))
        #expect(a.day == other && a.startMinute == 840)
        let b = try #require(plan("Standup @14:00"))
        #expect(b.day == friday)
    }

    @Test func aDayWordBeatsTheNoteDay() throws {
        let p = try #require(plan("Standup @tomorrow 14:00", noteDay: DayKey("2026-10-20")))
        #expect(p.day == saturday)
    }

    @Test func aDayAloneHasNoTime() throws {
        let p = try #require(plan("## Plan @tomorrow"))
        #expect(p.day == saturday && p.startMinute == nil && p.head == "## " && p.title == "Plan")
    }

    @Test func aListMarkerAndIndentStay() throws {
        #expect(try #require(plan("  - Lunch @tomorrow 12pm")).head == "  - ")
        #expect(try #require(plan("2. Lunch @tomorrow 12pm")).head == "2. ")
    }

    @Test func aTokenInsideThePrefixIsNotRead() {
        #expect(plan("@tomorrow") == nil)
    }

    // MARK: Length

    @Test func theSpanUsesTheLengthTheUserTyped() throws {
        let p = try #require(plan("Workshop @tomorrow 9am for 2h"))
        let s = try #require(AtDatePlanner.span(p, defaultMinutes: 60))
        #expect(s.start == 540 && s.end == 660)
    }

    @Test func theSpanUsesTheDefaultWhenNoLengthWasTyped() throws {
        let p = try #require(plan("Workshop @tomorrow 9am"))
        let s = try #require(AtDatePlanner.span(p, defaultMinutes: AtDatePlan.blockMinutes))
        #expect(s.start == 540 && s.end == 570)
    }

    @Test func theSpanStopsAtMidnight() throws {
        let p = try #require(plan("Late @tomorrow 23:30 for 2h"))
        let s = try #require(AtDatePlanner.span(p, defaultMinutes: 60))
        #expect(s.start == 1410 && s.end == 1440)
    }

    @Test func noTimeMeansNoSpan() throws {
        let p = try #require(plan("Holiday @tomorrow"))
        #expect(AtDatePlanner.span(p, defaultMinutes: 60) == nil)
    }

    // MARK: Writing the line back

    @Test func theWhenLabel() {
        #expect(AtDatePlanner.whenLabel(day: saturday, start: nil, end: nil) == "Sat 3 Oct")
        #expect(AtDatePlanner.whenLabel(day: saturday, start: 900, end: nil) == "Sat 3 Oct, 15:00")
        #expect(AtDatePlanner.whenLabel(day: saturday, start: 900, end: 960) == "Sat 3 Oct, 15:00–16:00")
        #expect(AtDatePlanner.whenLabel(day: saturday, start: 1410, end: 1440) == "Sat 3 Oct, 23:30–23:59")
    }

    @Test func aTaskLineKeepsItsBoxAndEndsWithTheMark() throws {
        let p = try #require(plan("- [ ] Write report @tomorrow 9am"))
        #expect(AtDatePlanner.taskLine(p, taskId: "ABC", when: "Sat 3 Oct, 09:00–09:30") == "- [ ] Write report · Sat 3 Oct, 09:00–09:30 ⟦t:ABC⟧")
    }

    @Test func anEventLineIsALinkThenWhen() throws {
        let p = try #require(plan("- Dentist @tomorrow 9am"))
        #expect(AtDatePlanner.eventLine(p, mention: "[[Dentist|E1]]", when: "Sat 3 Oct, 09:00–10:00") == "- [[Dentist|E1]] · Sat 3 Oct, 09:00–10:00")
    }

    @Test func theNewTaskLineIsStillOneBoxWithThatTask() throws {
        let p = try #require(plan("- [ ] Write report @tomorrow 9am"))
        let line = AtDatePlanner.taskLine(p, taskId: "ABC", when: "Sat 3 Oct")
        let box = try #require(NoteParser.checkboxes(in: line).first)
        #expect(box.taskId == "ABC" && !box.checked && box.text == "Write report · Sat 3 Oct")
        #expect(AtDateParser.find(in: line, today: friday) == nil)   // nothing left to add twice
    }
}
