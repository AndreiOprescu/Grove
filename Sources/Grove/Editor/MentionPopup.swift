import SwiftUI
import AppKit
import GroveCore

@Observable @MainActor
final class MentionPopupModel {
    var items: [MentionSuggestion] = []
    var selected = 0
}

/// The list that opens under the caret after `[[`. It lives in its own small window, so no scroll view
/// or panel can cut it off, and the text keeps the keyboard.
@MainActor
final class MentionPopup {
    let model = MentionPopupModel()
    var onPick: ((MentionSuggestion) -> Void)?
    private var panel: NSPanel?
    private weak var parent: NSWindow?

    static let rowHeight: CGFloat = 30
    static let width: CGFloat = 300

    var isVisible: Bool { panel?.isVisible == true }
    var current: MentionSuggestion? { model.items.indices.contains(model.selected) ? model.items[model.selected] : nil }

    /// `caret` is a rectangle in screen coordinates. The list opens under it, or over it when there is no room.
    func show(_ items: [MentionSuggestion], at caret: NSRect, in window: NSWindow, theme: Theme) {
        guard !items.isEmpty else { hide(); return }
        if model.items.map(\.id) != items.map(\.id) { model.selected = 0 }
        model.items = items

        let height = CGFloat(items.count) * Self.rowHeight + 12
        let panel = self.panel ?? makePanel(theme: theme)
        self.panel = panel

        var origin = NSPoint(x: caret.minX, y: caret.minY - height - 4)
        if let screen = window.screen ?? NSScreen.main {
            let area = screen.visibleFrame
            if origin.y < area.minY { origin.y = caret.maxY + 4 }
            origin.x = min(max(area.minX + 4, origin.x), area.maxX - Self.width - 4)
        }
        panel.setFrame(NSRect(x: origin.x, y: origin.y, width: Self.width, height: height), display: true)
        if parent !== window {
            parent?.removeChildWindow(panel)
            window.addChildWindow(panel, ordered: .above)
            parent = window
        }
        panel.orderFront(nil)
    }

    func hide() {
        guard let panel else { return }
        parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        parent = nil
    }

    func move(_ delta: Int) {
        guard !model.items.isEmpty else { return }
        model.selected = (model.selected + delta + model.items.count) % model.items.count
    }

    private func makePanel(theme: Theme) -> NSPanel {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 100),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.isReleasedWhenClosed = false
        p.becomesKeyOnlyIfNeeded = true
        let list = MentionList(model: model, pick: { [weak self] s in self?.onPick?(s) }).environment(\.theme, theme)
        p.contentView = NSHostingView(rootView: list)
        return p
    }
}

struct MentionList: View {
    var model: MentionPopupModel
    var pick: (MentionSuggestion) -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                row(item, selected: index == model.selected)
                    .contentShape(Rectangle())
                    .onTapGesture { pick(item) }
            }
        }
        .padding(6)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(theme.line, lineWidth: 1))
    }

    private func row(_ item: MentionSuggestion, selected: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon(item.ref.type))
                .font(.system(size: 12))
                .foregroundStyle(theme.accent)
                .frame(width: 16)
            Text(item.title)
                .font(.system(size: 13))
                .foregroundStyle(theme.ink)
                .lineLimit(1)
            Spacer(minLength: 6)
            Text(item.kind)
                .font(.system(size: 11))
                .foregroundStyle(theme.muted)
        }
        .padding(.horizontal, 8)
        .frame(height: MentionPopup.rowHeight)
        .background(selected ? theme.accent.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 6))
    }

    private func icon(_ type: ItemType) -> String {
        switch type {
        case .task: "checkmark.circle"
        case .note: "note.text"
        case .event: "calendar"
        }
    }
}
