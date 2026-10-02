import Testing
import Foundation
@testable import GroveCore

/// The hidden task mark on a check box line, and the editor rules around it.
struct TaskMarkTests {
    let id = "11111111-2222-3333-4444-555555555555"
    private func mark(_ id: String) -> String { NoteParser.marker(for: id) }

    private func marks(_ text: String) -> [String] {
        let ns = text as NSString
        return MarkdownSpans.scan(text).filter { $0.kind == .taskMark }.map { ns.substring(with: $0.range) }
    }

    // MARK: Reading

    @Test func theMarkIsASpanWithItsSpace() {
        let text = "- [ ] Buy milk \(mark("T1"))"
        #expect(marks(text) == [" ⟦t:T1⟧"])
    }

    @Test func aMarkIsOneUnitForTheCaret() {
        let text = "- [ ] Buy milk \(mark("T1"))"
        let spans = MarkdownSpans.scan(text)
        let at = (text as NSString).range(of: "⟦").location
        // A caret inside the mark moves to an edge.
        let snapped = MarkdownSpans.snapped(NSRange(location: at + 2, length: 0), in: spans)
        #expect(snapped.length == 0 && (snapped.location == at - 1 || snapped.location == (text as NSString).length))
        // A change that touches the mark takes all of it.
        let whole = MarkdownSpans.expanded(NSRange(location: at + 1, length: 1), in: spans)
        #expect(whole == NSRange(location: at - 1, length: (text as NSString).length - (at - 1)))
    }

    @Test func aTextWithoutMarksHasNoMarkSpan() {
        #expect(marks("- [ ] Buy milk").isEmpty)
        #expect(marks("⟦t:⟧ and ⟦x:1⟧").isEmpty)
    }

    @Test func aMarkInsideCodeIsPlainText() {
        #expect(marks("- [ ] see `\(mark("T1"))`").isEmpty)
    }

    @Test func theMarkDoesNotChangeTheOtherSpans() {
        let text = "- [x] Buy milk #home \(mark("T1"))"
        let kinds = MarkdownSpans.scan(text).map(\.kind)
        #expect(kinds.contains(.listPrefix) && kinds.contains(.tag) && kinds.contains(.checkedText) && kinds.contains(.taskMark))
    }

    // MARK: Delete keys beside a mark

    @Test func backspaceAfterTheMarkDeletesTheLetterBeforeIt() {
        let text = "- [ ] Buy milk \(mark("T1"))"
        let ns = text as NSString
        let spans = MarkdownSpans.scan(text)
        let end = ns.length
        let result = MarkdownSpans.deletionBesideMark(NSRange(location: end - 1, length: 1), replacement: "", in: spans, text: ns)
        // "Buy milk" ends before the space that belongs to the mark.
        let k = ns.range(of: "milk").location + 3
        #expect(result == .redirect(NSRange(location: k, length: 1)))
    }

    @Test func backspaceWithNothingToDeleteDoesNothing() {
        let text = "- [ ] \(mark("T1"))"
        let ns = text as NSString
        let spans = MarkdownSpans.scan(text)
        #expect(MarkdownSpans.deletionBesideMark(NSRange(location: ns.length - 1, length: 1), replacement: "", in: spans, text: ns) == .swallow)
    }

    @Test func forwardDeleteBeforeTheMarkDeletesTheLineBreak() {
        let text = "- [ ] Buy milk \(mark("T1"))\nNext"
        let ns = text as NSString
        let spans = MarkdownSpans.scan(text)
        let start = ns.range(of: " ⟦").location
        let result = MarkdownSpans.deletionBesideMark(NSRange(location: start, length: 1), replacement: "", in: spans, text: ns)
        #expect(result == .redirect(NSRange(location: ns.range(of: "\n").location, length: 1)))
    }

    @Test func forwardDeleteAtTheEndOfTheTextDoesNothing() {
        let text = "- [ ] Buy milk \(mark("T1"))"
        let ns = text as NSString
        let spans = MarkdownSpans.scan(text)
        let start = ns.range(of: " ⟦").location
        #expect(MarkdownSpans.deletionBesideMark(NSRange(location: start, length: 1), replacement: "", in: spans, text: ns) == .swallow)
    }

    @Test func otherEditsAreLeftAlone() {
        let text = "- [ ] Buy milk \(mark("T1"))"
        let ns = text as NSString
        let spans = MarkdownSpans.scan(text)
        #expect(MarkdownSpans.deletionBesideMark(NSRange(location: 8, length: 1), replacement: "", in: spans, text: ns) == .unchanged)
        #expect(MarkdownSpans.deletionBesideMark(NSRange(location: ns.length - 1, length: 1), replacement: "x", in: spans, text: ns) == .unchanged)
        #expect(MarkdownSpans.deletionBesideMark(NSRange(location: 8, length: 3), replacement: "", in: spans, text: ns) == .unchanged)
    }

    // MARK: Make task

    @Test func aPlainLineBecomesACheckBoxWithAMark() throws {
        let text = "Call Sam about the trip"
        let target = try #require(MarkdownEdit.taskTarget(in: text, selection: NSRange(location: 5, length: 0)))
        #expect(target.title == "Call Sam about the trip")
        let edit = MarkdownEdit.taskLine(for: target, in: text, taskId: "T1")
        #expect(edit.replacement == "- [ ] Call Sam about the trip ⟦t:T1⟧")
        #expect(edit.range == NSRange(location: 0, length: 23))
        // The caret stays before the hidden mark.
        #expect(edit.selection == NSRange(location: "- [ ] Call Sam about the trip".utf16.count, length: 0))
    }

    @Test func aSelectionNamesTheTaskAndTheWholeLineStays() throws {
        let text = "I need to call Sam about the trip"
        let sel = (text as NSString).range(of: "call Sam")
        let target = try #require(MarkdownEdit.taskTarget(in: text, selection: sel))
        #expect(target.title == "call Sam")
        #expect(MarkdownEdit.taskLine(for: target, in: text, taskId: "T1").replacement == "- [ ] I need to call Sam about the trip ⟦t:T1⟧")
    }

    @Test func aBulletBecomesACheckBoxAndKeepsItsIndent() throws {
        let text = "intro\n  - Pack the bags"
        let target = try #require(MarkdownEdit.taskTarget(in: text, selection: NSRange(location: 12, length: 0)))
        #expect(target.title == "Pack the bags")
        let edit = MarkdownEdit.taskLine(for: target, in: text, taskId: "T1")
        #expect(edit.replacement == "  - [ ] Pack the bags ⟦t:T1⟧")
        #expect(edit.range == NSRange(location: 6, length: 17))
    }

    @Test func aHeadingLosesItsHashes() throws {
        let text = "## Book flights"
        let target = try #require(MarkdownEdit.taskTarget(in: text, selection: NSRange(location: 0, length: 0)))
        #expect(MarkdownEdit.taskLine(for: target, in: text, taskId: "T1").replacement == "- [ ] Book flights ⟦t:T1⟧")
    }

    @Test func aCheckBoxKeepsItsBox() throws {
        let text = "- [x] Done already"
        let target = try #require(MarkdownEdit.taskTarget(in: text, selection: NSRange(location: 8, length: 0)))
        #expect(MarkdownEdit.taskLine(for: target, in: text, taskId: "T1").replacement == "- [x] Done already ⟦t:T1⟧")
    }

    @Test func noTargetForAnEmptyLineSeveralLinesOrATaskThatExists() {
        #expect(MarkdownEdit.taskTarget(in: "one\n\ntwo", selection: NSRange(location: 4, length: 0)) == nil)
        #expect(MarkdownEdit.taskTarget(in: "- [ ] \nnext", selection: NSRange(location: 2, length: 0)) == nil)
        #expect(MarkdownEdit.taskTarget(in: "one\ntwo", selection: NSRange(location: 1, length: 5)) == nil)
        #expect(MarkdownEdit.taskTarget(in: "- [ ] Buy milk ⟦t:T1⟧", selection: NSRange(location: 8, length: 0)) == nil)
    }

    @Test func theLineIsFoundWhenItIsTheLastOneOrHasAWindowsBreak() throws {
        let last = try #require(MarkdownEdit.taskTarget(in: "a\nLast line", selection: NSRange(location: 11, length: 0)))
        #expect(last.title == "Last line" && last.line == NSRange(location: 2, length: 9))
        let crlf = try #require(MarkdownEdit.taskTarget(in: "First\r\nSecond", selection: NSRange(location: 1, length: 0)))
        #expect(crlf.line == NSRange(location: 0, length: 5))
    }

    @Test func theNewLineIsAReadableCheckBoxWithATask() throws {
        let text = "Call Sam"
        let target = try #require(MarkdownEdit.taskTarget(in: text, selection: NSRange(location: 0, length: 0)))
        let edit = MarkdownEdit.taskLine(for: target, in: text, taskId: id)
        let boxes = NoteParser.checkboxes(in: edit.replacement)
        #expect(boxes == [NoteCheckbox(line: 0, checked: false, text: "Call Sam", taskId: id)])
    }
}
