import Testing
import Foundation
@testable import GroveCore

struct MarkdownSpansTests {
    let id = "11111111-2222-3333-4444-555555555555"

    /// The text covered by every span that `pick` accepts, in order.
    private func found(_ text: String, in range: NSRange? = nil, _ pick: (SpanKind) -> Bool) -> [String] {
        let ns = text as NSString
        return MarkdownSpans.scan(text, in: range).filter { pick($0.kind) }.map { ns.substring(with: $0.range) }
    }

    private func isHeading(_ k: SpanKind) -> Bool { if case .heading = k { true } else { false } }
    private func isMention(_ k: SpanKind) -> Bool { if case .mention = k { true } else { false } }
    private func isImage(_ k: SpanKind) -> Bool { if case .image = k { true } else { false } }
    private func isCheckbox(_ k: SpanKind) -> Bool { if case .checkbox = k { true } else { false } }

    // MARK: Lines

    @Test func headings() {
        #expect(found("## Title") { isHeading($0) } == ["## Title"])
        #expect(found("## Title") { $0 == .headingMark } == ["## "])
        #expect(MarkdownSpans.scan("### x").contains { $0.kind == .heading(3) })
        #expect(found("####### seven") { isHeading($0) }.isEmpty)
        #expect(found("#nospace") { isHeading($0) }.isEmpty)
    }

    @Test func listMarks() {
        #expect(found("- one") { $0 == .listMark } == ["- "])
        #expect(found("- one") { $0 == .listPrefix } == ["- "])
        #expect(found("  1. two") { $0 == .listMark } == ["1. "])
        #expect(found("  1. two") { $0 == .listPrefix } == ["  1. "])
        #expect(found("* star") { $0 == .listMark } == ["* "])
        #expect(found("plain") { $0 == .listMark }.isEmpty)
    }

    @Test func checklists() {
        #expect(found("- [x] done thing") { $0 == .checkbox(checked: true) } == ["[x]"])
        #expect(found("- [ ] todo") { $0 == .checkbox(checked: false) } == ["[ ]"])
        #expect(found("- [X] done thing") { $0 == .checkedText } == ["done thing"])
        #expect(found("- [ ] todo") { $0 == .checkedText }.isEmpty)
        #expect(found("  - [ ] nested") { $0 == .listPrefix } == ["  - [ ] "])
        #expect(found("- [ ] todo") { isCheckbox($0) } == ["[ ]"])
    }

    @Test func quotes() {
        #expect(found("> wise words") { $0 == .quote } == ["> wise words"])
        #expect(found("> wise words") { $0 == .quoteMark } == ["> "])
    }

    // MARK: Inline text

    @Test func boldItalicAndCode() {
        #expect(found("a **b** c") { $0 == .bold } == ["b"])
        #expect(found("a **b** c") { $0 == .syntax } == ["**", "**"])
        #expect(found("a *b* c") { $0 == .italic } == ["b"])
        #expect(found("use `x` now") { $0 == .code } == ["x"])
        #expect(found("use `x` now") { $0 == .syntax } == ["`", "`"])
    }

    @Test func tripleStarsAreBoldAndItalic() {
        #expect(found("***x***") { $0 == .bold } == ["x"])
        #expect(found("***x***") { $0 == .italic } == ["x"])
        #expect(found("***x***") { $0 == .syntax } == ["***", "***"])
    }

    @Test func italicCanSitInsideBold() {
        #expect(found("**a *b* c**") { $0 == .bold } == ["a *b* c"])
        #expect(found("**a *b* c**") { $0 == .italic } == ["b"])
    }

    @Test func starsThatDoNotMakeEmphasisAreLeftAlone() {
        #expect(found("2 * 3 * 4") { $0 == .italic }.isEmpty)
        #expect(found("a ** b ** c") { $0 == .bold }.isEmpty)
        #expect(found("lone * star") { $0 == .italic }.isEmpty)
        #expect(found("**unclosed") { $0 == .bold }.isEmpty)
    }

    @Test func codeKeepsItsContentLiteral() {
        #expect(found("use `**x**` now") { $0 == .bold }.isEmpty)
        #expect(found("`[[A|\(id)]]`") { isMention($0) }.isEmpty)
    }

    @Test func emphasisDoesNotCrossLines() {
        #expect(found("**a\nb**") { $0 == .bold }.isEmpty)
    }

    @Test func listMarkerStarIsNotItalic() {
        #expect(found("* one *two*") { $0 == .italic } == ["two"])
    }

    // MARK: Mentions and images

    @Test func mentionWithIdHidesTheBracketsAndTheId() {
        let text = "see [[Buy milk|\(id)]] ok"
        #expect(found(text) { isMention($0) } == ["[[Buy milk|\(id)]]"])
        #expect(found(text) { $0 == .hidden } == ["[[", "|\(id)]]"])
        let m = MarkdownSpans.scan(text).first { isMention($0.kind) }
        #expect(m?.kind == .mention(id: id, title: "Buy milk"))
    }

    @Test func mentionWithoutIdStillBecomesAChip() {
        let text = "see [[Buy milk]]"
        #expect(found(text) { isMention($0) } == ["[[Buy milk]]"])
        #expect(found(text) { $0 == .hidden } == ["[[", "]]"])
        #expect(MarkdownSpans.scan(text).first { isMention($0.kind) }?.kind == .mention(id: nil, title: "Buy milk"))
    }

    @Test func emphasisCanWrapAMention() {
        let text = "**[[A|\(id)]]**"
        #expect(found(text) { $0 == .bold } == ["[[A|\(id)]]"])
        #expect(found(text) { isMention($0) } == ["[[A|\(id)]]"])
    }

    @Test func imageHidesItsMarkup() {
        let text = "![front door](grove-image:\(id))"
        #expect(found(text) { isImage($0) } == [text])
        #expect(found(text) { $0 == .hidden } == ["![", "](grove-image:\(id))"])
        #expect(MarkdownSpans.scan(text).first { isImage($0.kind) }?.kind == .image(id: id))
    }

    @Test func imageWithoutAltOnlyHidesTheAddress() {
        let text = "![](grove-image:\(id))"
        #expect(found(text) { $0 == .hidden } == ["(grove-image:\(id))"])
    }

    @Test func tagsAndLinks() {
        #expect(found("call #home now") { $0 == .tag } == ["#home"])
        #expect(found("#home") { $0 == .tag } == ["#home"])
        #expect(found("a#b") { $0 == .tag }.isEmpty)
        #expect(found("# Title") { $0 == .tag }.isEmpty)
        #expect(found("see https://example.com/x, ok") { if case .link = $0 { true } else { false } } == ["https://example.com/x"])
        let link = MarkdownSpans.scan("go (https://a.b/c).").first { if case .link = $0.kind { true } else { false } }
        #expect(link?.kind == .link("https://a.b/c"))
    }

    // MARK: Positions

    @Test func rangesAreUTF16OffsetsInTheWholeText() {
        let ns = "a\n**b**" as NSString
        let bold = MarkdownSpans.scan(ns as String).first { $0.kind == .bold }
        #expect(bold?.range == NSRange(location: 4, length: 1))
        #expect(ns.substring(with: bold!.range) == "b")
        // an emoji is two UTF-16 units
        let emoji = MarkdownSpans.scan("😀 **b**").first { $0.kind == .bold }
        #expect(emoji?.range == NSRange(location: 5, length: 1))
    }

    @Test func scanningARangeOnlyReadsTheLinesItTouches() {
        let text = "**a**\n**b**\n**c**"
        let all = found(text) { $0 == .bold }
        #expect(all == ["a", "b", "c"])
        let middle = found(text, in: NSRange(location: 7, length: 1)) { $0 == .bold }
        #expect(middle == ["b"])
        let spans = MarkdownSpans.scan(text, in: NSRange(location: 7, length: 1))
        #expect(spans.first { $0.kind == .bold }?.range.location == 8)
    }

    @Test func emptyTextHasNoSpans() {
        #expect(MarkdownSpans.scan("").isEmpty)
        #expect(MarkdownSpans.scan("\n\n").isEmpty)
    }

    // MARK: Chips behave as one character

    private func spans(_ text: String) -> [TextSpan] { MarkdownSpans.scan(text) }

    @Test func aCaretInsideAChipMovesToItsEdge() {
        let text = "a [[B|\(id)]] c"
        let s = spans(text)
        let start = 2, end = 2 + "[[B|\(id)]]".utf16.count
        #expect(MarkdownSpans.snapped(NSRange(location: start + 3, length: 0), in: s, movingForward: true) == NSRange(location: end, length: 0))
        #expect(MarkdownSpans.snapped(NSRange(location: start + 3, length: 0), in: s, movingForward: false) == NSRange(location: start, length: 0))
        // the edges are fine as they are
        #expect(MarkdownSpans.snapped(NSRange(location: start, length: 0), in: s) == NSRange(location: start, length: 0))
        #expect(MarkdownSpans.snapped(NSRange(location: end, length: 0), in: s) == NSRange(location: end, length: 0))
    }

    @Test func aSelectionGrowsToWholeChips() {
        let text = "a [[B|\(id)]] c"
        let s = spans(text)
        let start = 2, end = 2 + "[[B|\(id)]]".utf16.count
        let grown = MarkdownSpans.snapped(NSRange(location: start + 2, length: 3), in: s)
        #expect(grown == NSRange(location: start, length: end - start))
        #expect(MarkdownSpans.snapped(NSRange(location: 0, length: 4), in: s) == NSRange(location: 0, length: end))
    }

    @Test func deletingPartOfAChipDeletesTheWholeChip() {
        let text = "a [[B|\(id)]] c"
        let s = spans(text)
        let start = 2, end = 2 + "[[B|\(id)]]".utf16.count
        let whole = NSRange(location: start, length: end - start)
        #expect(MarkdownSpans.expanded(NSRange(location: end - 1, length: 1), in: s) == whole)   // Backspace after it
        #expect(MarkdownSpans.expanded(NSRange(location: start, length: 1), in: s) == whole)     // Delete before it
        #expect(MarkdownSpans.expanded(NSRange(location: start - 1, length: 3), in: s) == NSRange(location: start - 1, length: end - start + 1))
        #expect(MarkdownSpans.expanded(NSRange(location: 0, length: 1), in: s) == NSRange(location: 0, length: 1))
        #expect(MarkdownSpans.expanded(NSRange(location: end, length: 1), in: s) == NSRange(location: end, length: 1))
    }

    @Test func typingInsideAChipLandsAfterIt() {
        let text = "[[B|\(id)]]"
        let s = spans(text)
        #expect(MarkdownSpans.expanded(NSRange(location: 3, length: 0), in: s) == NSRange(location: text.utf16.count, length: 0))
        #expect(MarkdownSpans.expanded(NSRange(location: 0, length: 0), in: s) == NSRange(location: 0, length: 0))
    }
}
