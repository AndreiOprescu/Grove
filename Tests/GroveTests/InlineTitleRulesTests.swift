import Testing
import Foundation
@testable import Grove

/// What a title field does when focus leaves it without Return or Esc.
struct InlineTitleRulesTests {
    @Test func textLeftInTheFieldIsKept() {
        #expect(InlineTitleRules.onBlur(text: "Call mum") == .commit)
        #expect(InlineTitleRules.onBlur(text: "  Call mum \n") == .commit)
    }

    @Test func emptyOrBlankTextIsDropped() {
        #expect(InlineTitleRules.onBlur(text: "") == .cancel)
        #expect(InlineTitleRules.onBlur(text: "   ") == .cancel)
        #expect(InlineTitleRules.onBlur(text: " \n\t ") == .cancel)
    }

    @Test func renameWithNoChangeIsDropped() {
        #expect(InlineTitleRules.onBlur(text: "Write report", initial: "Write report") == .cancel)
        #expect(InlineTitleRules.onBlur(text: " Write report ", initial: "Write report") == .cancel)
    }

    @Test func renameWithANewTitleIsKept() {
        #expect(InlineTitleRules.onBlur(text: "Write the report", initial: "Write report") == .commit)
    }

    @Test func clearingAnOldTitleIsDroppedNotSaved() {
        #expect(InlineTitleRules.onBlur(text: "", initial: "Write report") == .cancel)
    }
}
