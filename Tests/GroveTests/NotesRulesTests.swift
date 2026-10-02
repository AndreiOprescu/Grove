import Testing
import Foundation
import GroveCore
@testable import Grove

/// Titles, templates, the list filter and the preview line of a note.
struct NotesRulesTests {
    private func note(_ title: String, kind: NoteKind = .note, pinned: Bool = false, body: String = "") -> Note {
        Note(title: title, body: body, kind: kind, date: nil, pinned: pinned)
    }

    @Test func dailyTitle() {
        #expect(NotesRules.dailyTitle(DayKey("2026-10-02")) == "Friday, 2 October 2026")
        #expect(NotesRules.dailyTitle(DayKey("2026-12-31")) == "Thursday, 31 December 2026")
    }

    @Test func weeklyTitle() {
        #expect(NotesRules.weeklyTitle(DayKey("2026-09-28")) == "Week 40 · 28 Sep – 4 Oct")
        #expect(NotesRules.weeklyTitle(DayKey("2026-10-26")) == "Week 44 · 26 Oct – 1 Nov")
    }

    @Test func weekNumbersFollowTheCalendarWeek() {
        #expect(NotesRules.weekNumber(DayKey("2024-12-30")) == 1)    // belongs to week 1 of 2025
        #expect(NotesRules.weekNumber(DayKey("2026-01-05")) == 2)
        #expect(NotesRules.weekNumber(DayKey("2026-12-28")) == 53)
    }

    @Test func templates() {
        #expect(NotesRules.template(.daily) == "## Plan\n\n## Notes\n\n## Reflection\n")
        #expect(NotesRules.template(.weekly) == "## Goals\n\n## Notes\n\n## Review\n")
        #expect(NotesRules.template(.note) == "")
    }

    @Test func filters() {
        let a = note("A", kind: .daily), b = note("B", kind: .weekly), c = note("C", pinned: true), d = note("D")
        let all = [a, b, c, d]
        let none: (String) -> [String] = { _ in [] }
        #expect(NotesRules.filter(all, .all, tagsOf: none).count == 4)
        #expect(NotesRules.filter(all, .daily, tagsOf: none).map(\.title) == ["A"])
        #expect(NotesRules.filter(all, .weekly, tagsOf: none).map(\.title) == ["B"])
        #expect(NotesRules.filter(all, .pinned, tagsOf: none).map(\.title) == ["C"])
        #expect(NotesRules.filter(all, .tag("work"), tagsOf: { $0 == d.id ? ["Work"] : [] }).map(\.title) == ["D"])   // any letter case
    }

    @Test func previewSkipsHeadingsAndMarks() {
        #expect(NotesRules.preview("## Plan\n\nCall **Sam** about [[Trip|2D6F1B1C-0000-4000-8000-000000000000]]\nmore") == "Call Sam about Trip")
        #expect(NotesRules.preview("# Only a heading\n\n") == "")
        #expect(NotesRules.preview("- [ ] Pack bags ⟦t:A⟧") == "Pack bags")
        #expect(NotesRules.preview("![pic](grove-image:X)\nHello") == "Hello")
    }

    @Test func previewIsShort() {
        let long = String(repeating: "word ", count: 60)
        #expect(NotesRules.preview(long).count <= 91)
    }

    @Test func copyTitles() {
        #expect(NotesRules.copyTitle("Ideas", existing: ["Ideas"]) == "Ideas copy")
        #expect(NotesRules.copyTitle("Ideas", existing: ["Ideas", "Ideas copy"]) == "Ideas copy 2")
        #expect(NotesRules.copyTitle("Ideas", existing: ["Ideas", "Ideas copy", "Ideas copy 2"]) == "Ideas copy 3")
    }

    @Test func newTitlesDoNotRepeat() {
        #expect(NotesRules.untitled(existing: []) == "Untitled")
        #expect(NotesRules.untitled(existing: ["Untitled", "untitled 2"]) == "Untitled 3")
    }
}
