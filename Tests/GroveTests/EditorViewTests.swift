import Testing
import SwiftUI
import AppKit
import GroveCore
@testable import Grove

/// Drives the real editor view in an off-screen window, the way the keyboard would.
@MainActor
struct EditorViewTests {
    final class Box { var text: String; init(_ t: String) { text = t } }

    struct Host: View {
        let box: Box
        let services: EditorServices
        let controller: EditorController
        @State var text: String
        var body: some View {
            RichTextEditor(text: Binding(get: { text }, set: { text = $0; box.text = $0 }), controller: controller, services: services)
                .environment(\.theme, Theme.grove)
                .frame(width: 400)
        }
    }

    struct Rig {
        var view: GroveTextView
        var box: Box
        var controller: EditorController
        var window: NSWindow
    }

    private func makeRig(_ text: String, services: EditorServices = EditorServices()) throws -> Rig {
        _ = NSApplication.shared
        let box = Box(text)
        let controller = EditorController()
        let host = NSHostingView(rootView: Host(box: box, services: services, controller: controller, text: text))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        func find(_ v: NSView) -> GroveTextView? {
            if let t = v as? GroveTextView { return t }
            for s in v.subviews { if let t = find(s) { return t } }
            return nil
        }
        let view = try #require(find(host))
        window.makeFirstResponder(view)
        return Rig(view: view, box: box, controller: controller, window: window)
    }

    private let id = "11111111-2222-3333-4444-555555555555"

    @Test func typingUpdatesTheBinding() throws {
        let r = try makeRig("")
        r.view.insertText("hello", replacementRange: NSRange(location: 0, length: 0))
        #expect(r.box.text == "hello")
    }

    @Test func returnContinuesABulletList() throws {
        let r = try makeRig("- one")
        r.view.setSelectedRange(NSRange(location: 5, length: 0))
        r.view.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        #expect(r.box.text == "- one\n- ")
    }

    @Test func returnOnAnEmptyBulletEndsTheList() throws {
        let r = try makeRig("- one\n- ")
        r.view.setSelectedRange(NSRange(location: 8, length: 0))
        r.view.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        #expect(r.box.text == "- one\n")
    }

    @Test func tabIndentsAListItem() throws {
        let r = try makeRig("- one\n- two")
        r.view.setSelectedRange(NSRange(location: 11, length: 0))
        r.view.doCommand(by: #selector(NSResponder.insertTab(_:)))
        #expect(r.box.text == "- one\n  - two")
    }

    @Test func backspaceAfterAMentionDeletesTheWholeMention() throws {
        let text = "a [[Buy milk|\(id)]]"
        let r = try makeRig(text)
        r.view.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        r.view.doCommand(by: #selector(NSResponder.deleteBackward(_:)))
        #expect(r.box.text == "a ")
    }

    @Test func aCaretThatEntersAMentionMovesToTheFarEdge() throws {
        let text = "a [[Buy milk|\(id)]] z"
        let r = try makeRig(text)
        let start = 2, end = 2 + "[[Buy milk|\(id)]]".utf16.count
        // moving right from before it jumps over it
        r.view.setSelectedRange(NSRange(location: start, length: 0))
        r.view.setSelectedRange(NSRange(location: start + 1, length: 0))
        #expect(r.view.selectedRange() == NSRange(location: end, length: 0))
        // moving left from after it jumps back over it
        r.view.setSelectedRange(NSRange(location: end, length: 0))
        r.view.setSelectedRange(NSRange(location: end - 1, length: 0))
        #expect(r.view.selectedRange() == NSRange(location: start, length: 0))
    }

    @Test func typingInsideAMentionLandsAfterIt() throws {
        let text = "[[Buy milk|\(id)]]"
        let r = try makeRig(text)
        r.view.insertText("x", replacementRange: NSRange(location: 4, length: 0))
        #expect(r.box.text == text + "x")
    }

    @Test func boldWrapsTheSelection() throws {
        let r = try makeRig("make this loud")
        r.view.setSelectedRange(NSRange(location: 5, length: 4))
        r.controller.format(.bold)
        #expect(r.box.text == "make **this** loud")
    }

    @Test func theChecklistButtonTurnsALineIntoAChecklist() throws {
        let r = try makeRig("buy milk")
        r.view.setSelectedRange(NSRange(location: 3, length: 0))
        r.controller.format(.line(.checklist))
        #expect(r.box.text == "- [ ] buy milk")
    }

    @Test func aNewImageGoesInAsMarkupAndIsStored() throws {
        var stored: [Data] = []
        var s = EditorServices()
        s.storeImage = { data in stored.append(data); return "11111111-2222-3333-4444-555555555555" }
        let r = try makeRig("see", services: s)
        r.view.setSelectedRange(NSRange(location: 3, length: 0))
        r.view.onImages?([(data: Data([1, 2, 3]), name: "door")])
        #expect(stored.count == 1)
        #expect(r.box.text.contains("![door](grove-image:\(id))"))
    }

    @Test func anUnreadableImageShowsAToastAndChangesNothing() throws {
        var told: [String] = []
        var s = EditorServices()
        s.notify = { told.append($0) }
        let r = try makeRig("see", services: s)
        r.view.onImages?([(data: Data(), name: "junk")])
        #expect(r.box.text == "see")
        #expect(told.count == 1)
    }

    @Test func aDroppedTaskBecomesAMention() throws {
        var s = EditorServices()
        s.title = { $0 == "T1" ? "Buy milk" : nil }
        let r = try makeRig("ab", services: s)
        r.view.onTaskDrop?("T1", 1)
        #expect(r.box.text == "a[[Buy milk|T1]]b")
    }

    @Test func aTaskThatIsGoneIsNotDropped() throws {
        let r = try makeRig("ab")
        r.view.onTaskDrop?("nope", 1)
        #expect(r.box.text == "ab")
    }

    @Test func typingBracketsOpensThePickerAndChoosingInsertsAMention() throws {
        var s = EditorServices()
        s.suggest = { _ in [MentionSuggestion(ref: ItemRef(.task, "T1"), title: "Buy milk", kind: "Task")] }
        let r = try makeRig("see ", services: s)
        r.view.setSelectedRange(NSRange(location: 4, length: 0))
        r.view.insertText("[[bu", replacementRange: r.view.selectedRange())
        r.view.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        #expect(r.box.text == "see [[Buy milk|T1]]")
    }

    @Test func escapeClosesThePickerAndReturnThenMakesALineBreak() throws {
        var s = EditorServices()
        s.suggest = { _ in [MentionSuggestion(ref: ItemRef(.task, "T1"), title: "Buy milk", kind: "Task")] }
        let r = try makeRig("", services: s)
        r.view.insertText("[[bu", replacementRange: NSRange(location: 0, length: 0))
        r.view.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
        r.view.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        #expect(r.box.text.hasPrefix("[[bu"))
        #expect(!r.box.text.contains("T1"))
    }
}

extension EditorViewTests {
    @Test func escapeKeyIsKeptByTheEditorWhileItsListIsOpen() throws {
        var s = EditorServices()
        s.suggest = { _ in [MentionSuggestion(ref: ItemRef(.task, "T1"), title: "Buy milk", kind: "Task")] }
        let r = try makeRig("", services: s)
        // no list yet: Esc is not the editor's
        #expect(r.view.onEscape?() == false)
        r.view.insertText("[[bu", replacementRange: NSRange(location: 0, length: 0))
        #expect(r.view.onEscape?() == true)
        #expect(r.view.onEscape?() == false)
    }
}
