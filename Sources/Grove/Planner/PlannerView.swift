import SwiftUI
import GroveCore

enum PlannerMode: Int, CaseIterable, Identifiable {
    case day = 1, threeDay = 3, week = 7, month = 30
    var id: Int { rawValue }
    var label: String {
        switch self { case .day: "Day"; case .threeDay: "3 Days"; case .week: "Week"; case .month: "Month" }
    }
}

extension PlannerMode {
    /// Where a screen keeps its mode. The Today screen has none: it is always one day.
    static func storageKey(for screen: Screen) -> String? {
        switch screen {
        case .planner: "planner.mode"
        case .calendar: "calendar.mode"
        case .today, .notes: nil
        }
    }
}

/// The time grid with its header. It fills the Planner and the Calendar screens.
/// With `column` it is the timeline of the Day Spread: one day, a small header, no week strip and no tray.
struct PlannerView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.theme) private var theme

    private let column: Bool

    init(modeKey: String = "planner.mode", defaultMode: PlannerMode = .day, column: Bool = false) {
        _modeRaw = AppStorage(wrappedValue: defaultMode.rawValue, modeKey)
        self.column = column
    }

    @AppStorage private var modeRaw: Int
    @AppStorage("planner.hourHeight") private var hourHeight = 64.0
    @AppStorage("planner.snap") private var snapStep = 5
    @AppStorage("planner.workStart") private var workStart = 9 * 60
    @AppStorage("planner.workEnd") private var workEnd = 18 * 60
    @AppStorage("planner.trayOpen") private var trayOpen = true
    @AppStorage("shell.tasksOpen") private var tasksOpen = true
    @AppStorage("calendar.moodTint") private var moodTint = false
    @AppStorage("calendar.weekStartsSunday") private var sundayFirst = false

    @State private var geo = PlannerGeometry()
    @State private var dropToTray = false
    @State private var scrollRequest = 0
    @State private var plan: [(task: TaskItem, start: Int)]?
    /// Width inside the side padding. Starts wide so the first frame does not hide the tray.
    @State private var contentWidth: CGFloat = 10_000

    private var mode: PlannerMode { column ? .day : PlannerMode(rawValue: modeRaw) ?? .day }
    private var trayFits: Bool { !column && PlannerLayoutRules.trayFits(contentWidth: contentWidth) }
    private var showTray: Bool { trayOpen && trayFits }

    private var days: [DayKey] {
        switch mode {
        case .day: [store.selectedDay]
        case .threeDay: (0..<3).map { store.selectedDay.adding(days: $0) }
        case .week, .month: (0..<7).map { CalendarRules.weekStart(of: store.selectedDay, sundayFirst: sundayFirst).adding(days: $0) }   // month draws its own grid
        }
    }

    var body: some View {
        let _ = store.revision   // re-run this view after every saved change
        VStack(spacing: 10) {
            if column { columnHeader } else { header }
            if !column, mode == .day || mode == .threeDay { WeekStrip(shown: Set(days)) }
            if mode == .month {
                MonthView { _ in modeRaw = PlannerMode.day.rawValue }
                    .panel()
                    .clipShape(RoundedRectangle(cornerRadius: theme.radius, style: .continuous))
            } else {
                allDayStrip
                HStack(alignment: .top, spacing: 12) {
                    if showTray {
                        UnscheduledTray(day: store.selectedDay, isDropTarget: dropToTray,
                                        workStart: workStart, workEnd: workEnd, snapStep: snapStep)
                            .transition(.opacity)
                    }
                    VStack(spacing: 0) {
                        if days.count > 1 { dayHeaders }
                        PlannerGrid(days: days, geo: $geo, dropToTray: $dropToTray, scrollRequest: scrollRequest,
                                    snapStep: snapStep, workStart: workStart, workEnd: workEnd)
                    }
                    .panel()
                    .clipShape(RoundedRectangle(cornerRadius: theme.radius, style: .continuous))
                }
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { contentWidth = $0 }
        .padding(.horizontal, column ? 0 : 16).padding(.bottom, column ? 0 : 16)
        .padding(.top, column ? 0 : 34)   // the window buttons sit in this space (title bar is hidden)
        .onAppear { geo.hourHeight = CGFloat(hourHeight); takePlanRequest() }
        .onChange(of: store.planMyDayRequest) { takePlanRequest() }
        .onChange(of: store.todayRequest) { scrollRequest += 1 }
        .onChange(of: geo.hourHeight) { _, new in hourHeight = Double(new) }
        .onChange(of: hourHeight) { _, new in if CGFloat(new) != geo.hourHeight { geo.hourHeight = CGFloat(new) } }   // the View ▸ Zoom menu writes here
        .alert("Busy day", isPresented: Binding(get: { store.overloadWarning != nil }, set: { if !$0 { store.overloadWarning = nil } })) {
            Button("OK") { store.overloadWarning = nil }
        } message: { Text(store.overloadWarning ?? "") }
        .sheet(isPresented: Binding(get: { plan != nil }, set: { if !$0 { plan = nil } })) { planSheet }
        .animation(.easeInOut(duration: 0.2), value: showTray)
    }

    // MARK: Header

    /// One row when there is room. Two or three rows when the task list and the inspector are both open.
    private var header: some View {
        let blocks = store.blocks(for: store.selectedDay...store.selectedDay)
        let totals = store.dayTotals(store.selectedDay, blocks: blocks, workStart: workStart, workEnd: workEnd)
        let over = totals.planned > store.dailyLimitMinutes
        let stats = mode == .month ? monthStats
            : "\(over ? "⚠︎ " : "")\(PlannerMath.duration(totals.planned)) planned · \(PlannerMath.duration(totals.free)) free · \(totals.done)/\(totals.total) done"
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                navButtons
                VStack(alignment: .leading, spacing: 0) {
                    titleText
                    statsText(stats, over: over)
                }
                Spacer(minLength: 0)
                planButton(compact: false)
                modePicker(width: 250)
                zoomButtons
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) { navButtons; titleText; Spacer(minLength: 0) }
                HStack(spacing: 10) {
                    statsText(stats, over: over)
                    Spacer(minLength: 0)
                    planButton(compact: false)
                    modePicker(width: 230)
                    zoomButtons
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) { navButtons; titleText; Spacer(minLength: 0) }
                statsText(stats, over: over)
                HStack(spacing: 10) {
                    modePicker(width: 230)
                    Spacer(minLength: 0)
                    planButton(compact: true)
                    zoomButtons
                }
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
    }

    /// The small header of the Day Spread timeline: a title, the day's numbers, Plan my day and the zoom.
    private var columnHeader: some View {
        let blocks = store.blocks(for: store.selectedDay...store.selectedDay)
        let totals = store.dayTotals(store.selectedDay, blocks: blocks, workStart: workStart, workEnd: workEnd)
        let over = totals.planned > store.dailyLimitMinutes
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text("Timeline").themedHeading(theme, 20, weight: .semibold).foregroundStyle(theme.ink)
                Spacer(minLength: 0)
                planButton(compact: true)
                zoomButtons
            }
            .buttonStyle(.bordered).controlSize(.small)
            statsText("\(over ? "⚠︎ " : "")\(PlannerMath.duration(totals.planned)) planned · \(PlannerMath.duration(totals.free)) free · \(totals.done)/\(totals.total) done", over: over)
        }
    }

    @ViewBuilder private var navButtons: some View {
        if !tasksOpen {
            Button { tasksOpen = true } label: { Image(systemName: "checklist") }
                .help("Show the task list")
        }
        Button { trayOpen.toggle() } label: { Image(systemName: "sidebar.left") }
            .disabled(!trayFits || mode == .month)
            .help(trayFits ? "Show or hide the unscheduled tray" : "No room for the tray. Close the task list or the task panel.")
        Button { move(-1) } label: { Image(systemName: "chevron.left") }.help("Previous")
        Button("Today") { store.selectedDay = .today(); scrollRequest += 1 }
            .fixedSize()
        Button { move(1) } label: { Image(systemName: "chevron.right") }.help("Next")
        Button { store.openDailyNote(store.selectedDay) } label: { Image(systemName: "note.text") }
            .help(store.selectedDay == .today() ? "Today's note" : "Note for \(store.selectedDay.date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)))")
    }

    private var titleText: some View {
        Text(title)
            .themedHeading(theme, 22)
            .foregroundStyle(theme.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
    }

    private func statsText(_ text: String, over: Bool) -> some View {
        Text(text)
            .font(.system(size: 11, weight: over ? .bold : .regular, design: .rounded))
            .foregroundStyle(over ? theme.accent2 : theme.muted)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    @ViewBuilder private func planButton(compact: Bool) -> some View {
        if mode == .month {
            Toggle(isOn: $moodTint) { Image(systemName: "face.smiling") }
                .toggleStyle(.button)
                .help("Tint each day by the mood of its note")
        } else if compact {
            Button { showPlan() } label: { Image(systemName: "wand.and.stars") }
                .help("Plan my day: fit today's unscheduled tasks into free working hours")
        } else {
            Button("Plan my day") { showPlan() }
                .fixedSize()
                .help("Fit today's unscheduled tasks into free working hours")
        }
    }

    private func modePicker(width: CGFloat) -> some View {
        Picker("View", selection: $modeRaw) {
            ForEach(PlannerMode.allCases) { Text($0.label).tag($0.rawValue) }
        }
        .pickerStyle(.segmented).frame(width: width).labelsHidden()
    }

    @ViewBuilder private var zoomButtons: some View {
        if mode != .month {
            Button { zoom(1 / 1.2) } label: { Image(systemName: "minus.magnifyingglass") }.help("Zoom out")
            Button { zoom(1.2) } label: { Image(systemName: "plus.magnifyingglass") }.help("Zoom in")
        }
    }

    private var title: String {
        switch mode {
        case .day: return store.selectedDay.date.formatted(.dateTime.weekday(.wide).day().month(.wide))
        case .month: return store.selectedDay.date.formatted(.dateTime.month(.wide).year())
        default:
            let d = days
            return "\(d.first!.date.formatted(.dateTime.day().month(.abbreviated))) – \(d.last!.date.formatted(.dateTime.day().month(.abbreviated).year()))"
        }
    }

    private var monthStats: String {
        let grid = CalendarRules.monthGrid(containing: store.selectedDay, sundayFirst: sundayFirst)
        let info = store.dayInfo(grid[0]...grid[41])
        let inMonth = grid.filter { $0.month == store.selectedDay.month }
        let events = Set(inMonth.flatMap { info[$0]?.events.map(\.id) ?? [] }).count
        let tasks = inMonth.reduce(0) { $0 + (info[$1]?.openTasks ?? 0) }
        return "\(events) event\(events == 1 ? "" : "s") · \(tasks) open task\(tasks == 1 ? "" : "s")"
    }

    private func move(_ direction: Int) {
        if mode == .month { store.selectedDay = CalendarRules.addMonths(store.selectedDay, direction); return }
        store.selectedDay = store.selectedDay.adding(days: direction * (mode == .week ? 7 : mode.rawValue))
    }

    private func zoom(_ factor: CGFloat) {
        geo.hourHeight = min(PlannerGeometry.zoomRange.upperBound, max(PlannerGeometry.zoomRange.lowerBound, geo.hourHeight * factor))
    }

    private var dayHeaders: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: geo.gutterWidth, height: 0)
            ForEach(days, id: \.self) { day in
                VStack(spacing: 0) {
                    Text(day.date.formatted(.dateTime.weekday(.abbreviated))).font(theme.body(11))
                    Text(day.date.formatted(.dateTime.day())).font(theme.body(15, weight: .bold))
                }
                .foregroundStyle(day == .today() ? theme.accent : theme.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
                .onTapGesture { store.selectedDay = day; modeRaw = PlannerMode.day.rawValue }
            }
        }
        .fixedSize(horizontal: false, vertical: true)   // the row is only as tall as its labels
        .overlay(alignment: .bottom) { Rectangle().fill(theme.line).frame(height: 1) }
    }

    @ViewBuilder private var allDayStrip: some View {
        let events = store.allDayEvents(for: days.first!...days.last!)
        if !events.isEmpty {
            HStack(spacing: 6) {
                Text("All day").font(theme.body(11)).foregroundStyle(theme.muted)
                ForEach(events) { e in
                    Text(e.title).font(theme.body(11, weight: .semibold))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .chipBackground(theme.color(named: e.color), fill: 0.2)
                        .foregroundStyle(theme.ink)
                        .contentShape(Capsule())
                        .onTapGesture { store.editEvent(e) }
                        .eventEditor(anchor: e.id)
                }
                Spacer()
            }
        }
    }

    // MARK: Plan my day

    /// The palette asked for "Plan my day". It may ask while this screen is not shown, so the request waits here.
    private func takePlanRequest() {
        guard store.planMyDayHandled != store.planMyDayRequest else { return }
        store.planMyDayHandled = store.planMyDayRequest
        showPlan()
    }

    private func showPlan() {
        let result = store.planMyDayPreview(day: store.selectedDay, workStart: workStart, workEnd: workEnd, step: snapStep)
        if result.isEmpty { store.showToast("Nothing to plan. No unscheduled task fits in working hours.") } else { plan = result }
    }

    private var planSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Plan my day").themedHeading(theme, 22, weight: .semibold)
            Text("Grove will place these tasks in free working hours, highest priority first.")
                .font(theme.body(12)).foregroundStyle(theme.muted)
            ForEach(Array((plan ?? []).enumerated()), id: \.offset) { _, item in
                HStack {
                    Text("\(PlannerMath.clock(item.start))–\(PlannerMath.clock(item.start + max(5, item.task.estimateMin)))")
                        .monospacedDigit().foregroundStyle(theme.accent)
                    Text(item.task.title).lineLimit(1)
                    Spacer()
                }
                .font(theme.body(13))
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { plan = nil }.keyboardShortcut(.cancelAction)
                Button("Apply") {
                    if let p = plan { store.applyPlan(p, day: store.selectedDay) }
                    plan = nil
                }
                .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
        }
        .padding(20).frame(width: 420)
    }
}
