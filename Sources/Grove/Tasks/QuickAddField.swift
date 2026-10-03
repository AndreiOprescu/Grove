import SwiftUI
import GroveCore

/// One line to add a task. Shows what the parser understood while you type.
struct QuickAddField: View {
    @Environment(AppStore.self) private var store
    @Environment(\.theme) private var theme
    /// Where a task goes when the text names no date.
    let placement: TaskPlacement
    let placementLabel: String
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill").foregroundStyle(theme.accent)
                TextField("Add a task…", text: $text)
                    .textFieldStyle(.plain)
                    .font(theme.body(13))
                    .focused($focused)
                    .onSubmit(submit)
                    .onExitCommand { text = ""; focused = false }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.surface2))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(focused ? theme.accent : theme.line, lineWidth: focused ? 1.5 : 1))

            if text.trimmingCharacters(in: .whitespaces).isEmpty {
                if focused {
                    Text("Try “Call mum tomorrow 6pm for 20m #home /Errands !2”")
                        .font(theme.body(10)).foregroundStyle(theme.muted)
                }
            } else {
                preview
            }
        }
        .onChange(of: store.quickAddRequest) { _, _ in focused = true }
    }

    private var preview: some View {
        let lists = ((try? store.repos.lists.all()) ?? []).map(\.name)
        let r = QuickAddParser(today: .today(), lists: lists).parse(text)
        return FlowLayout(spacing: 4) {
            if !r.chips.contains(where: { $0.kind == .date }) {
                Chip(text: placementLabel, symbol: "tray", tint: theme.accent)
            }
            ForEach(Array(r.chips.enumerated()), id: \.offset) { _, chip in
                Chip(text: chip.text, symbol: TaskFormat.symbol(chip.kind), tint: theme.accent)
            }
        }
    }

    private func submit() {
        guard let task = store.quickAdd(text, default: placement) else { return }
        text = ""
        focused = true
        let landed = Self.label(for: task)
        if landed != placementLabel { store.showToast("Added to \(landed)") }
    }

    /// Short name of the place a task lives in.
    static func label(for task: TaskItem) -> String {
        switch task.bucket {
        case .day: task.planDate.map { TaskFormat.dayLabel($0) } ?? "Day"
        case .week: "this week"
        case .someday: "Someday"
        case .inbox: "Inbox"
        }
    }
}
