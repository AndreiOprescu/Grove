import Foundation

/// What a title field does when focus leaves it without Return or Esc. A plain function, so tests can check it.
enum InlineTitleRules {
    enum BlurAction: Equatable { case commit, cancel }

    /// Text with something in it is kept. Empty text is dropped.
    /// `initial` is what the field started with (a rename). Unchanged text is dropped too, so it makes no undo step.
    static func onBlur(text: String, initial: String = "") -> BlurAction {
        let new = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let old = initial.trimmingCharacters(in: .whitespacesAndNewlines)
        return new.isEmpty || new == old ? .cancel : .commit
    }
}
