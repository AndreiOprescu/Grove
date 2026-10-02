import Testing
import Foundation
@testable import GroveCore

struct ReferenceParserTests {
    let idA = "3F2A9B1C-0D4E-4F5A-8B6C-7D8E9F0A1B2C"
    let idB = "A1B2C3D4-E5F6-4A7B-8C9D-0E1F2A3B4C5D"

    private func parsed(_ text: String) -> [String] {
        ReferenceParser.mentions(in: text).map { "\($0.title)|\($0.id ?? "-")" }
    }

    // MARK: mentions

    @Test func plainTitleMention() {
        #expect(parsed("see [[Buy milk]] today") == ["Buy milk|-"])
    }

    @Test func mentionWithId() {
        #expect(parsed("see [[Buy milk|\(idA)]]") == ["Buy milk|\(idA)"])
    }

    @Test func severalMentionsKeepTheirOrder() {
        #expect(parsed("[[One]] and [[Two|\(idA)]] and [[One]]") == ["One|-", "Two|\(idA)", "One|-"])
    }

    @Test func spacesAroundTheTitleAreTrimmed() {
        #expect(parsed("[[  Buy milk  ]]") == ["Buy milk|-"])
    }

    @Test func emptyMentionIsIgnored() {
        #expect(parsed("[[]] and [[   ]] and [[|\(idA)]]").isEmpty)
    }

    @Test func mentionCannotSpanLines() {
        #expect(parsed("[[Buy\nmilk]]").isEmpty)
    }

    @Test func innerMentionWinsWhenNested() {
        #expect(parsed("[[a [[b]] c]]") == ["b|-"])
    }

    @Test func aBarWithoutARealIdStaysInTheTitle() {
        #expect(parsed("[[Yes|No]]") == ["Yes|No|-"])
        #expect(parsed("[[Tea|]]") == ["Tea||-"])
    }

    @Test func linksAndImagesAreNotMentions() {
        #expect(parsed("[site](https://example.com) ![pic](grove-image:\(idA)) [x]").isEmpty)
    }

    @Test func rangeCoversTheWholeMention() {
        let text = "a [[Buy milk|\(idA)]] b"
        let m = ReferenceParser.mentions(in: text)
        #expect(m.count == 1)
        #expect(m.first.map { String(text[$0.range]) } == "[[Buy milk|\(idA)]]")
    }

    // MARK: writing mentions

    @Test func mentionText() {
        #expect(ReferenceParser.mention(title: "Buy milk", id: idA) == "[[Buy milk|\(idA)]]")
        #expect(ReferenceParser.mention(title: "Buy milk", id: nil) == "[[Buy milk]]")
    }

    @Test func mentionTextCleansTitlesThatWouldBreakTheSyntax() {
        #expect(ReferenceParser.mention(title: "a [b] | c\nd", id: nil) == "[[a b c d]]")
        #expect(ReferenceParser.mention(title: " [] ", id: idA) == "[[Untitled|\(idA)]]")
    }

    @Test func rewritingChangesOnlyTheMatchingId() {
        let text = "x [[Old|\(idA)]] y [[Other|\(idB)]] z [[Old]]"
        let out = ReferenceParser.rewriting(text, id: idA, to: "Fresh")
        #expect(out == "x [[Fresh|\(idA)]] y [[Other|\(idB)]] z [[Old]]")
    }

    @Test func rewritingWithNoMatchReturnsTheSameText() {
        let text = "nothing [[here]]"
        #expect(ReferenceParser.rewriting(text, id: idA, to: "X") == text)
    }

    // MARK: images

    @Test func imageIdsInOrderWithoutDuplicates() {
        let text = "![a](grove-image:\(idA)) text ![](grove-image:\(idB)) ![again](grove-image:\(idA))"
        #expect(ReferenceParser.imageIDs(in: text) == [idA, idB])
    }

    @Test func otherImageLinksAreNotAttachments() {
        #expect(ReferenceParser.imageIDs(in: "![a](https://example.com/a.png) ![b](grove-image:nope)").isEmpty)
    }

    @Test func imageMarkup() {
        #expect(ReferenceParser.imageMarkup(id: idA, alt: "My shot") == "![My shot](grove-image:\(idA))")
        #expect(ReferenceParser.imageMarkup(id: idA, alt: "a]\nb") == "![a b](grove-image:\(idA))")
    }

    // MARK: search text

    @Test func searchTextDropsIdsAndKeepsWords() {
        let body = "call [[Dentist|\(idA)]] and [[Plain]] ![front door](grove-image:\(idB)) done ⟦t:\(idA)⟧"
        #expect(ReferenceParser.searchText(body) == "call Dentist and Plain front door done")
    }
}
