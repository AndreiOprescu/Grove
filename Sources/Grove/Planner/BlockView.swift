import SwiftUI
import AppKit
import GroveCore

enum DragMode { case move, resizeTop, resizeBottom, create }

/// A text field that grabs focus when it appears. Return saves. Esc cancels.
struct InlineTitleField: View {
    @State private var text: String
    let placeholder: String
    var onChange: (String) -> Void = { _ in }
    let onCommit: (String, _ commandHeld: Bool) -> Void
    let onCancel: () -> Void
    @FocusState private var focused: Bool

    init(initial: String, placeholder: String, onChange: @escaping (String) -> Void = { _ in },
         onCommit: @escaping (String, Bool) -> Void, onCancel: @escaping () -> Void) {
        _text = State(initialValue: initial)
        self.placeholder = placeholder
        self.onChange = onChange
        self.onCommit = onCommit
        self.onCancel = onCancel
    }

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .focused($focused)
            .onSubmit { onCommit(text, NSEvent.modifierFlags.contains(.command)) }
            .onExitCommand { onCancel() }
            .onChange(of: text) { _, new in onChange(new) }
            .onChange(of: focused) { _, isFocused in if !isFocused { onCancel() } }
            .onAppear { DispatchQueue.main.async { focused = true } }
    }
}

/// One block on the grid. Gestures report to the grid, which owns all live state.
struct BlockView: View {
    @Environment(\.theme) private var theme
    let block: PlannerBlock
    let start: Int
    let end: Int
    let size: CGSize
    /// True when the block lies on top of a longer block. It gets a solid base so the block below does not show through.
    let isOverlay: Bool
    let isSelected: Bool
    let isDragging: Bool
    let isRenaming: Bool
    let onTap: () -> Void
    let onDoubleTap: () -> Void
    let onToggleDone: () -> Void
    let onRename: (String) -> Void
    let onCancelRename: () -> Void
    /// (mode, value, ended)
    let onDrag: (DragMode, DragGesture.Value, Bool) -> Void

    private var tint: Color { theme.color(named: block.color) }
    private var length: Int { end - start }
    private var compact: Bool { length < 25 || size.height < 34 }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: min(8, theme.radius / 2), style: .continuous) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            content
                .padding(.leading, 9).padding(.trailing, 5).padding(.vertical, compact ? 0 : 3)
                .frame(width: size.width, height: size.height, alignment: compact ? .leading : .topLeading)
                .background(shape.fill(tint.opacity(block.isTaskBlock ? 0.10 : 0.16)))
                .overlay(alignment: .leading) {
                    Rectangle().fill(tint).frame(width: 3)
                }
                .overlay {
                    if block.isTaskBlock {
                        shape.strokeBorder(tint.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    }
                }
                .clipShape(shape)
                .overlay { if isSelected { shape.strokeBorder(theme.accent, lineWidth: 2) } }
                .opacity(block.isDone ? 0.55 : 1)
                .background { if isOverlay { shape.fill(theme.surface) } }
                .shadow(color: .black.opacity(isDragging ? 0.22 : (isOverlay ? 0.18 : 0)),
                        radius: isDragging ? 10 : 3, y: isDragging ? 4 : 1)
                .contentShape(shape)
                .gesture(
                    DragGesture(minimumDistance: 2, coordinateSpace: .named("plannerGrid"))
                        .onChanged { onDrag(.move, $0, false) }
                        .onEnded { onDrag(.move, $0, true) })
                .onTapGesture(count: 2, perform: onDoubleTap)
                .onTapGesture(perform: onTap)
                .pointerStyle(.grabIdle)
                .help("\(block.title) · \(PlannerMath.label(start: start, end: end))")

            handle(.top)
            handle(.bottom)
        }
        .frame(width: size.width, height: size.height)
    }

    @ViewBuilder private var content: some View {
        if isRenaming {
            InlineTitleField(initial: block.title, placeholder: "Title",
                             onCommit: { text, _ in onRename(text) }, onCancel: onCancelRename)
        } else if compact {
            HStack(spacing: 5) {
                checkbox
                Text(block.title).font(.system(size: 11, weight: .semibold, design: .rounded)).lineLimit(1)
                    .strikethrough(block.isDone)
            }
            .foregroundStyle(theme.ink)
        } else {
            VStack(alignment: .leading, spacing: 1) {
                // One row for time and length. A block laid on top of this one then hides at most this row.
                ViewThatFits(in: .horizontal) {
                    timeRow("\(PlannerMath.clock(start))–\(PlannerMath.clock(end)) · \(PlannerMath.duration(length))")
                        .fixedSize(horizontal: true, vertical: false)
                    timeRow("\(PlannerMath.clock(start))–\(PlannerMath.clock(end))")
                }
                HStack(alignment: .top, spacing: 5) {
                    checkbox
                    Text(block.title).font(.system(size: 12, weight: .semibold, design: .rounded))
                        .lineLimit(max(1, Int((size.height - 28) / 15) + 1))
                        .strikethrough(block.isDone)
                }
            }
            .foregroundStyle(theme.ink)
        }
    }

    private func timeRow(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold, design: .rounded)).monospacedDigit()
            .lineLimit(1)
            .foregroundStyle(tint)
    }

    @ViewBuilder private var checkbox: some View {
        if block.isTaskBlock {
            Button(action: onToggleDone) {
                Image(systemName: block.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: compact ? 11 : 13))
                    .foregroundStyle(block.isDone ? theme.accent : theme.muted)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(block.isDone ? "Mark not done" : "Mark done")
        }
    }

    private func handle(_ edge: VerticalEdge) -> some View {
        let h = min(6, max(2, size.height / 3))
        let mode: DragMode = edge == .top ? .resizeTop : .resizeBottom
        return Color.clear
            .frame(width: size.width, height: h)
            .contentShape(Rectangle())
            .pointerStyle(.frameResize(position: edge == .top ? .top : .bottom))
            .highPriorityGesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .named("plannerGrid"))
                    .onChanged { onDrag(mode, $0, false) }
                    .onEnded { onDrag(mode, $0, true) })
            .frame(width: size.width, height: size.height, alignment: edge == .top ? .top : .bottom)
    }
}
