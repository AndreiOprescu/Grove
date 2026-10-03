import SwiftUI
import GroveCore

/// ⌘K: search tasks, events and notes, run commands, jump to a day (PLAN §5.5 item 11).
/// Up and down choose a row. Return runs it. Esc closes. A `>` first keeps only commands.
struct CommandPalette: View {
    @Environment(AppStore.self) private var store
    @Environment(\.theme) private var theme
    @FocusState private var focused: Bool
    @State private var selected = 0

    var body: some View {
        let rows = store.paletteItems(for: store.paletteText)
        let chosen = min(selected, max(0, rows.count - 1))
        ZStack(alignment: .top) {
            Color.black.opacity(0.28).ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { store.paletteOpen = false }
            VStack(spacing: 0) {
                field
                Divider().overlay(theme.line)
                results(rows, chosen: chosen)
                footer
            }
            .frame(width: 560)
            .panel()
            .shadow(color: .black.opacity(0.25), radius: 24, y: 10)
            .padding(.top, 90)
        }
        .onAppear { selected = 0; focused = true }
        .onChange(of: store.paletteText) { selected = 0 }
    }

    // MARK: The box

    private var field: some View {
        @Bindable var store = store
        return HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(theme.muted)
            TextField("Search, or type > for commands", text: $store.paletteText)
                .textFieldStyle(.plain)
                .font(theme.body(17))
                .foregroundStyle(theme.ink)
                .focused($focused)
                .onSubmit { runChosen() }
                .onKeyPress(.downArrow) { move(1); return .handled }
                .onKeyPress(.upArrow) { move(-1); return .handled }
                .onKeyPress(.escape) { self.store.paletteOpen = false; return .handled }
            Text("esc").font(theme.body(10.5, weight: .semibold)).foregroundStyle(theme.muted)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 5).fill(theme.surface2))
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
    }

    // The key handlers read the rows and the choice when the key is pressed, not when the view was drawn.
    // Two quick presses can come before the next draw.

    private func move(_ step: Int) {
        let count = store.paletteItems(for: store.paletteText).count
        guard count > 0 else { return }
        selected = max(0, min(count - 1, min(selected, count - 1) + step))
    }

    private func runChosen() {
        let rows = store.paletteItems(for: store.paletteText)
        guard !rows.isEmpty else { return }
        store.runPalette(rows[min(selected, rows.count - 1)])
    }

    // MARK: The rows

    @ViewBuilder private func results(_ rows: [PaletteItem], chosen: Int) -> some View {
        if rows.isEmpty {
            Text(emptyText).font(theme.body(13)).foregroundStyle(theme.muted)
                .frame(maxWidth: .infinity, alignment: .leading).padding(16)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { i, item in
                            row(item, isChosen: i == chosen).id(item.id)
                        }
                    }
                    .padding(8)
                }
                .frame(height: min(CGFloat(rows.count) * 44 + 16, 360))
                .onChange(of: chosen) { if rows.indices.contains(chosen) { proxy.scrollTo(rows[chosen].id) } }
            }
        }
    }

    private var emptyText: String {
        PaletteRules.asksForDay(store.paletteText)
            ? "Type a day, like fri, tomorrow or oct 9."
            : "Nothing found."
    }

    private func row(_ item: PaletteItem, isChosen: Bool) -> some View {
        Button { store.runPalette(item) } label: {
            HStack(spacing: 10) {
                Image(systemName: item.symbol).font(.system(size: 13))
                    .foregroundStyle(item.done ? theme.muted : theme.accent).frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title).font(theme.body(14)).strikethrough(item.done)
                        .foregroundStyle(item.done ? theme.muted : theme.ink).lineLimit(1)
                    if !item.detail.isEmpty {
                        Text(item.detail).font(theme.body(11)).foregroundStyle(theme.muted).lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if let key = item.shortcut {
                    Text(key).font(theme.body(11)).foregroundStyle(theme.muted)
                }
            }
            .padding(.horizontal, 10).frame(height: 42)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(isChosen ? theme.accent.opacity(0.16) : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Text("↑↓ choose"); Text("⏎ open"); Text("> commands")
            Spacer()
        }
        .font(theme.body(11)).foregroundStyle(theme.muted)
        .padding(.horizontal, 16).padding(.vertical, 8)
        .overlay(alignment: .top) { Divider().overlay(theme.line) }
    }
}

/// The small "Search ⌘K" pill in the strip at the top of the window.
struct PaletteButton: View {
    @Environment(AppStore.self) private var store
    @Environment(\.theme) private var theme

    var body: some View {
        Button { store.togglePalette() } label: {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                Text("Search").font(theme.body(12))
                Text("⌘K").font(theme.body(10.5, weight: .semibold))
            }
            .foregroundStyle(theme.muted)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Capsule().fill(theme.surface2))
            .overlay(Capsule().strokeBorder(theme.line))
        }
        .buttonStyle(.plain)
        .help("Search and commands (⌘K)")
    }
}
