import SwiftUI
import GroveCore

/// Layout B, the home screen (PLAN §8): a header with the date, then three columns.
/// The timeline of the day · the tasks · the note of the day (the task panel takes its place while a task is selected).
struct DaySpreadView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.theme) private var theme
    @AppStorage("spread.timelineWidth") private var savedWidth = SpreadRules.timelineDefault
    /// The width while the edge is being dragged. Saved when the drag ends.
    @State private var liveWidth: Double?
    @State private var dragStart: Double?

    private var timelineWidth: Double { SpreadRules.clampTimeline(liveWidth ?? savedWidth) }

    var body: some View {
        let _ = store.revision
        VStack(spacing: 12) {
            SpreadHeader()
            HStack(alignment: .top, spacing: 0) {
                PlannerView(column: true)
                    .frame(width: timelineWidth)
                resizeHandle
                TasksPane(spread: true)
                    .frame(minWidth: SpreadRules.tasksMinimum)
                Color.clear.frame(width: SpreadRules.gap)
                rightColumn
                    .frame(width: SpreadRules.noteWidth)
            }
        }
        .padding(.horizontal, SpreadRules.side).padding(.bottom, 16)
        .padding(.top, 34)   // the window buttons sit in this space (the title bar is hidden)
        .animation(.easeInOut(duration: 0.2), value: store.selectedTaskId)
    }

    @ViewBuilder private var rightColumn: some View {
        if let id = store.selectedTaskId {
            TaskInspector(taskId: id)
                .frame(maxHeight: .infinity, alignment: .top)
                .transition(.opacity)
        } else {
            DayNoteColumn(day: store.selectedDay)
                .transition(.opacity)
        }
    }

    /// A thin strip between the timeline and the tasks. Drag it to make the timeline wider or narrower.
    private var resizeHandle: some View {
        Color.clear
            .frame(width: SpreadRules.gap)
            .contentShape(Rectangle())
            .pointerStyle(.columnResize)
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { v in
                        if dragStart == nil { dragStart = timelineWidth }
                        liveWidth = SpreadRules.clampTimeline((dragStart ?? timelineWidth) + v.translation.width)
                    }
                    .onEnded { _ in
                        if let liveWidth { savedWidth = liveWidth }
                        liveWidth = nil
                        dragStart = nil
                    }
            )
            .help("Drag to change the width of the timeline")
            .accessibilityLabel("Timeline width")
    }
}

/// The big date, the greeting, the growth of the day, the week strip and the plant.
struct SpreadHeader: View {
    @Environment(AppStore.self) private var store
    @Environment(\.theme) private var theme

    var body: some View {
        let _ = store.revision
        let day = store.selectedDay
        let progress = store.plantProgress(on: day)
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(day.date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .themedHeading(theme, 28, weight: .semibold)
                    .foregroundStyle(theme.ink)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(SpreadRules.subtitle(isToday: day == .today(), greeting: Greeting.now(), progress: progress))
                    .font(theme.body(12)).foregroundStyle(theme.muted).lineLimit(1)
            }
            .layoutPriority(1)
            HStack(spacing: 6) {
                Button { store.stepDay(-1) } label: { Image(systemName: "chevron.left") }
                    .help("Previous day")
                    .accessibilityLabel("Previous day")
                Button("Today") { store.showToday() }
                    .fixedSize()
                    .disabled(day == .today())
                Button { store.stepDay(1) } label: { Image(systemName: "chevron.right") }
                    .help("Next day")
                    .accessibilityLabel("Next day")
            }
            .buttonStyle(.bordered)
            Spacer(minLength: 0)
            WeekStrip(shown: [day]).frame(maxWidth: 420)
            GrowingPlant(progress: progress, height: 44)
        }
    }
}

/// The note of the chosen day, in the third column. A day with no note yet shows a button to start one.
/// Today's note is made when the column opens, because the page is about today.
struct DayNoteColumn: View {
    @Environment(AppStore.self) private var store
    @Environment(\.theme) private var theme
    let day: DayKey

    var body: some View {
        let _ = store.revision
        Group {
            if let note = store.existingDailyNote(for: day) {
                NoteEditorPane(noteId: note.id, compact: true).id(note.id)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "leaf").font(.system(size: 22)).foregroundStyle(theme.accent)
                    Text("No note for this day yet.").font(theme.body(13)).foregroundStyle(theme.muted)
                    Button("Start a note") { store.dailyNote(for: day) }
                        .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .panel()
            }
        }
        .task(id: day) { if day == .today() { store.dailyNote(for: day) } }
    }
}
