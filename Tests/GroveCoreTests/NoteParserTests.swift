import Testing
import Foundation
@testable import GroveCore

/// What the app reads out of a note's text: `#tags` and `- [ ]` lines.
struct NoteParserTests {
    // MARK: Tags

    @Test func findsTagsInText() {
        #expect(NoteParser.tags(in: "Plan #work and #Home-2 today") == ["work", "Home-2"])
    }

    @Test func aHeadingIsNotATag() {
        #expect(NoteParser.tags(in: "# Title\n## Plan\n###Odd") == [])
    }

    @Test func numbersAndLinksAreNotTags() {
        #expect(NoteParser.tags(in: "issue #123, see http://a.b/c#top, mail a#b") == [])
    }

    @Test func codeMentionsAndImagesAreSkipped() {
        let text = "`#code` and [[Task #1|ID1]] and ![a #pic](grove-image:X) and #real"
        #expect(NoteParser.tags(in: text) == ["real"])
    }

    @Test func sameTagInAnyCaseCountsOnce() {
        #expect(NoteParser.tags(in: "#Work #work #WORK #play") == ["Work", "play"])
    }

    @Test func aTagAtTheStartOfALine() {
        #expect(NoteParser.tags(in: "#idea\nmore") == ["idea"])
    }

    // MARK: Check boxes

    @Test func findsCheckBoxLines() {
        let body = "## Plan\n- [ ] Call Sam\n- [x] Send file\n  - [X] Nested\ntext\n- [ ] "
        let boxes = NoteParser.checkboxes(in: body)
        #expect(boxes.map(\.line) == [1, 2, 3])
        #expect(boxes.map(\.text) == ["Call Sam", "Send file", "Nested"])
        #expect(boxes.map(\.checked) == [false, true, true])
        #expect(boxes.allSatisfy { $0.taskId == nil })
    }

    @Test func readsTheHiddenTaskMarker() {
        let body = "- [ ] Call Sam ⟦t:ABC-123⟧\n- [x] Done thing\u{20}⟦t:Z9⟧"
        let boxes = NoteParser.checkboxes(in: body)
        #expect(boxes.map(\.taskId) == ["ABC-123", "Z9"])
        #expect(boxes.map(\.text) == ["Call Sam", "Done thing"])   // the marker is not part of the text
    }

    @Test func addingAMarkerToALine() {
        let body = "a\n- [ ] Call Sam\nb"
        let out = NoteParser.addingMarker(body, line: 1, taskId: "T1")
        #expect(out == "a\n- [ ] Call Sam ⟦t:T1⟧\nb")
        // A line that has a marker keeps it.
        #expect(NoteParser.addingMarker(out, line: 1, taskId: "T2") == out)
    }

    @Test func tickingALine() {
        let body = "- [ ] One ⟦t:A⟧\n- [x] Two"
        #expect(NoteParser.settingChecked(body, line: 0, to: true) == "- [x] One ⟦t:A⟧\n- [x] Two")
        #expect(NoteParser.settingChecked(body, line: 1, to: false) == "- [ ] One ⟦t:A⟧\n- [ ] Two")
        // A line that is not a check box is left alone.
        #expect(NoteParser.settingChecked("plain", line: 0, to: true) == "plain")
    }

    @Test func theMarkerIsHiddenFromSearchAndTitles() {
        #expect(NoteParser.withoutMarkers("- [ ] Call ⟦t:A1⟧ now") == "- [ ] Call now")
    }
}
