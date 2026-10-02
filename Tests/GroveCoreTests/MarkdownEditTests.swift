import Testing
import Foundation
@testable import GroveCore

/// Text is written with the caret as `|`, or a selection between `‹` and `›`.
struct MarkdownEditTests {
    private func parse(_ marked: String) -> (text: String, sel: NSRange) {
        let ns = marked as NSString
        let open = ns.range(of: "‹"), close = ns.range(of: "›")
        if open.location != NSNotFound {
            let text = marked.replacingOccurrences(of: "‹", with: "").replacingOccurrences(of: "›", with: "")
            return (text, NSRange(location: open.location, length: close.location - open.location - 1))
        }
        let bar = ns.range(of: "|")
        return (marked.replacingOccurrences(of: "|", with: ""), NSRange(location: bar.location, length: 0))
    }

    /// Applies an edit and writes the result with the new selection marked. Nil when the edit does nothing.
    private func run(_ marked: String, _ op: (String, NSRange) -> TextEdit?) -> String? {
        let (text, sel) = parse(marked)
        guard let e = op(text, sel) else { return nil }
        let out = (text as NSString).replacingCharacters(in: e.range, with: e.replacement) as NSString
        if e.selection.length == 0 {
            return out.replacingCharacters(in: NSRange(location: e.selection.location, length: 0), with: "|")
        }
        let closed = out.replacingCharacters(in: NSRange(location: e.selection.location + e.selection.length, length: 0), with: "›") as NSString
        return closed.replacingCharacters(in: NSRange(location: e.selection.location, length: 0), with: "‹")
    }

    private func enter(_ s: String) -> String? { run(s) { MarkdownEdit.enter(in: $0, selection: $1) } }
    private func tab(_ s: String) -> String? { run(s) { MarkdownEdit.indent(in: $0, selection: $1, outdent: false) } }
    private func backTab(_ s: String) -> String? { run(s) { MarkdownEdit.indent(in: $0, selection: $1, outdent: true) } }
    private func wrap(_ marker: String, _ s: String) -> String? { run(s) { MarkdownEdit.toggleWrap(marker, in: $0, selection: $1) } }
    private func line(_ style: LineStyle, _ s: String) -> String? { run(s) { MarkdownEdit.toggleLine(style, in: $0, selection: $1) } }

    // MARK: Return continues a list

    @Test func returnContinuesLists() {
        let table: [(String, String)] = [
            ("- one|", "- one\n- |"),
            ("* one|", "* one\n* |"),
            ("1. one|", "1. one\n2. |"),
            ("9. nine|", "9. nine\n10. |"),
            ("- [x] done|", "- [x] done\n- [ ] |"),
            ("- [ ] todo|", "- [ ] todo\n- [ ] |"),
            ("  - nested|", "  - nested\n  - |"),
            ("> quote|", "> quote\n> |"),
            ("- one|two", "- one\n- |two"),
            ("intro\n- one|", "intro\n- one\n- |"),
        ]
        for (input, want) in table { #expect(enter(input) == want, "input: \(input)") }
    }

    @Test func returnOnAnEmptyItemLeavesTheList() {
        #expect(enter("- |") == "|")
        #expect(enter("1. |") == "|")
        #expect(enter("- [ ] |") == "|")
        #expect(enter("> |") == "|")
        #expect(enter("a\n- |") == "a\n|")
    }

    @Test func returnOnAnEmptyNestedItemMovesItOneLevelOut() {
        #expect(enter("  - |") == "- |")
        #expect(enter("    1. |") == "  1. |")
    }

    @Test func returnLeavesOtherLinesAlone() {
        #expect(enter("hello|") == nil)
        #expect(enter("# Title|") == nil)
        #expect(enter("|") == nil)
        #expect(enter("- ‹one›") == nil)   // a selection is replaced by the normal new line
        #expect(enter("|- one") == nil)    // caret before the marker
    }

    // MARK: Tab

    @Test func tabIndentsListItems() {
        #expect(tab("- a|") == "  - a|")
        #expect(tab("1. a|") == "  1. a|")
        #expect(tab("- [ ] a|") == "  - [ ] a|")
        #expect(tab("|- a") == "  |- a")
    }

    @Test func backTabMovesItemsOut() {
        #expect(backTab("  - a|") == "- a|")
        #expect(backTab("    - a|") == "  - a|")
        #expect(backTab(" - a|") == "- a|")
        #expect(backTab("- a|") == nil)
    }

    @Test func tabOnPlainTextDoesNothing() {
        #expect(tab("hello|") == nil)
        #expect(backTab("  hello|") == nil)
    }

    @Test func tabIndentsEveryListLineInASelection() {
        #expect(tab("‹- a\n- b›") == "‹  - a\n  - b›")
        #expect(tab("‹- a\nplain›") == "‹  - a\nplain›")
        #expect(backTab("‹  - a\n  - b›") == "‹- a\n- b›")
        // triple-click selects the line with its newline; the next line must stay as it is
        #expect(tab("‹- a\n›- b") == "‹  - a\n›- b")
    }

    // MARK: Bold, italic and code

    @Test func wrapsASelection() {
        #expect(wrap("**", "say ‹word› now") == "say **‹word›** now")
        #expect(wrap("*", "say ‹word› now") == "say *‹word›* now")
        #expect(wrap("`", "‹x›") == "`‹x›`")
    }

    @Test func wrapAtACaretMakesAPairAndPutsTheCaretInside() {
        #expect(wrap("**", "say |") == "say **|**")
        #expect(wrap("*", "|") == "*|*")
    }

    @Test func wrapAgainRemovesTheMarkers() {
        #expect(wrap("**", "say **‹word›** now") == "say ‹word› now")
        #expect(wrap("*", "*‹x›*") == "‹x›")
        #expect(wrap("`", "`‹x›`") == "‹x›")
        #expect(wrap("**", "**|**") == "|")
        #expect(wrap("**", "‹**x**›") == "‹x›")   // the markers are inside the selection
    }

    @Test func boldAndItalicDoNotMistakeEachOther() {
        #expect(wrap("*", "**‹x›**") == "***‹x›***")   // bold is not italic
        #expect(wrap("*", "***‹x›***") == "**‹x›**")   // removes only the italic
        #expect(wrap("**", "***‹x›***") == "*‹x›*")    // removes only the bold
        #expect(wrap("**", "*‹x›*") == "***‹x›***")
    }

    @Test func wrapDoesNotTouchAListMarkerBeforeTheSelection() {
        #expect(wrap("*", "* ‹item›") == "* *‹item›*")
    }

    // MARK: Line styles

    @Test func addsLineStyles() {
        #expect(line(.bullet, "one|") == "- one|")
        #expect(line(.numbered, "one|") == "1. one|")
        #expect(line(.checklist, "one|") == "- [ ] one|")
        #expect(line(.heading(2), "Title|") == "## Title|")
        #expect(line(.quote, "wise|") == "> wise|")
    }

    @Test func togglingTheSameStyleRemovesIt() {
        #expect(line(.bullet, "- one|") == "one|")
        #expect(line(.numbered, "3. one|") == "one|")
        #expect(line(.checklist, "- [x] one|") == "one|")
        #expect(line(.heading(2), "## Title|") == "Title|")
        #expect(line(.quote, "> wise|") == "wise|")
    }

    @Test func aDifferentStyleReplacesTheOldOne() {
        #expect(line(.numbered, "- one|") == "1. one|")
        #expect(line(.checklist, "- one|") == "- [ ] one|")
        #expect(line(.bullet, "- [ ] one|") == "- one|")
        #expect(line(.heading(2), "# Title|") == "## Title|")
        #expect(line(.bullet, "## Title|") == "- Title|")
    }

    @Test func lineStylesKeepIndentation() {
        #expect(line(.bullet, "  one|") == "  - one|")
        #expect(line(.numbered, "  - one|") == "  1. one|")
        #expect(line(.bullet, "  - one|") == "  one|")
    }

    @Test func lineStylesApplyToEveryLineOfASelection() {
        #expect(line(.numbered, "‹a\nb\nc›") == "‹1. a\n2. b\n3. c›")
        #expect(line(.bullet, "‹- a\n- b›") == "‹a\nb›")
        #expect(line(.bullet, "‹- a\nb›") == "‹- a\n- b›")          // not all had it: add to all
        #expect(line(.bullet, "‹a\n\nb›") == "‹- a\n\n- b›")        // empty lines are skipped
        #expect(line(.numbered, "‹a\n\nb›") == "‹1. a\n\n2. b›")
    }

    @Test func lineStyleOnAnEmptyLineAddsTheMarker() {
        #expect(line(.bullet, "|") == "- |")
        #expect(line(.heading(1), "x\n|") == "x\n# |")
    }

    // MARK: Checkbox

    @Test func clickingACheckboxFlipsIt() throws {
        func flip(_ text: String, at loc: Int) -> String? {
            MarkdownEdit.toggleCheckbox(in: text, at: loc).map { (text as NSString).replacingCharacters(in: $0.range, with: $0.replacement) }
        }
        #expect(flip("- [ ] a", at: 3) == "- [x] a")
        #expect(flip("- [x] a", at: 0) == "- [ ] a")
        #expect(flip("- [X] a", at: 6) == "- [ ] a")
        #expect(flip("x\n  - [ ] a", at: 5) == "x\n  - [x] a")
        #expect(flip("- a", at: 0) == nil)
        #expect(flip("plain", at: 2) == nil)
    }

    // MARK: Mentions

    @Test func findsTheOpenMentionBeforeTheCaret() throws {
        let (t1, s1) = parse("see [[Bu|")
        let a = try #require(MarkdownEdit.mentionTrigger(in: t1, caret: s1.location))
        #expect(a.query == "Bu" && a.range == NSRange(location: 4, length: 4))

        let (t2, s2) = parse("see [[|")
        #expect(MarkdownEdit.mentionTrigger(in: t2, caret: s2.location)?.query == "")

        let (t3, s3) = parse("[[Bu|y milk")   // only the text before the caret counts
        #expect(MarkdownEdit.mentionTrigger(in: t3, caret: s3.location)?.query == "Bu")

        let (t4, s4) = parse("a\n[[two words|")
        #expect(MarkdownEdit.mentionTrigger(in: t4, caret: s4.location)?.query == "two words")
    }

    @Test func noTriggerWhenTheMentionIsClosedOrBroken() {
        for marked in ["see [Bu|", "[[a]] b|", "[[a\n|", "plain|", "[[a]|"] {
            let (t, s) = parse(marked)
            #expect(MarkdownEdit.mentionTrigger(in: t, caret: s.location) == nil, "input: \(marked)")
        }
    }

    @Test func insertingAMentionReplacesWhatWasTyped() throws {
        let text = "see [[Bu"
        let trigger = try #require(MarkdownEdit.mentionTrigger(in: text, caret: 8))
        let id = "11111111-2222-3333-4444-555555555555"
        let edit = MarkdownEdit.insertMention(title: "Buy milk", id: id, replacing: trigger.range)
        let out = (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
        #expect(out == "see [[Buy milk|\(id)]]")
        #expect(edit.selection == NSRange(location: (out as NSString).length, length: 0))
    }

    @Test func insertedMentionIsReadBackByTheParser() throws {
        let id = "11111111-2222-3333-4444-555555555555"
        let edit = MarkdownEdit.insertMention(title: "Plan [draft] | v2", id: id, replacing: NSRange(location: 0, length: 0))
        let found = try #require(ReferenceParser.mentions(in: edit.replacement).first)
        #expect(found.id == id)
        #expect(found.title == "Plan draft v2")
    }
}
