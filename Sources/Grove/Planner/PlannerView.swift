import SwiftUI
import GroveCore

/// What a top tab shows. Each tab has one fixed view: Today is one day, the Planner is one week, the Calendar is one month.
enum PlannerKind: Equatable {
    case today, week, month

    /// The days of the view. Today is today only. The week holds `selected` and starts on Monday (Sunday with `sundayFirst`).
    /// The month is its six-week grid.
    func days(selected: DayKey, today: DayKey, sundayFirst: Bool) -> [DayKey] {
        switch self {
        case .today:
            return [today]
        case .week:
            let start = CalendarRules.weekStart(of: selected, sundayFirst: sundayFirst)
            return (0..<7).map { start.adding(days: $0) }
        case .month:
            return CalendarRules.monthGrid(containing: selected, sundayFirst: sundayFirst)
        }
    }

    /// The day after a click on Previous (-1) or Next (+1): a week back or forward, or a month. Today does not move.
    func moved(_ day: DayKey, by direction: Int) -> DayKey {
        switch self {
        case .today: day
        case .week: day.adding(days: direction * 7)
        case .month: CalendarRules.addMonths(day, direction)
        }
    }
}

/// The time grid with its header. It fills the Planner and the Calendar screens.
/// With `.today` it is the timeline of the Day Spread: one day, a small header and no day headers.
struct PlannerView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.theme) private var theme

    private let kind: PlannerKind

    init(kind: PlannerKind) {
        self.kind = kind
    }

    @AppStorage("planner.hourHeight") private var hourHeight = 64.0
    @AppStorage("planner.workStart") private var workStart = 9 * 60
    @AppStorage("planner.workEnd") private var workEnd = 18 * 60
    @AppStorage("calendar.moodTint") private var moodTint = false
    /// Read so the workload bar redraws when the limit changes in Settings.
    @AppStorage("planner.dailyLimitMin") private var dailyLimit = SettingsRules.defaultDailyLimit
    @AppStorage("calendar.weekStartsSunday") private var sundayFirst = false

    @State private var geo = PlannerGeometry()
    @State private var dropToStrip = false
    @State private var scrollRequest = 0
    @State private var plan: [(task: TaskItem, start: Int)]?

    private var days: [DayKey] { kind.days(selected: store.selectedDay, today: .today(), sundayFirst: sundayFirst) }

    var body: some View {
        let _ = store.revision   // re-run this view after every saved change
        VStack(spacing: 10) {
            if kind == .today { columnHeader } else { header }
            if kind == .month {
                MonthView { day in store.selectedDay = day; store.screen = .planner }   // opens the Planner on that week
                    .panel()
                    .clipShape(RoundedRectangle(cornerRadius: theme.radius, style: .continuous))
            } else {
                allDayStrip
                VStack(spacing: 0) {
                    if kind == .week { dayHeaders }
                    StickyStrip(days: days, gutterWidth: geo.gutterWidth, isDropTarget: dropToStrip,
                                workStart: workStart, workEnd: workEnd)
                    PlannerGrid(days: days, geo: $geo, dropToStrip: $dropToStrip, scrollRequest: scrollRequest,
                                workStart: workStart, workEnd: workEnd)
                }
                .panel()
                .clipShape(RoundedRectangle(cornerRadius: theme.radius, style: .continuous))
            }
        }
        .padding(.horizontal, kind == .today ? 0 : 16).padding(.bottom, kind == .today ? 0 : 16)
        .padding(.top, kind == .today ? 0 : 34)   // the window buttons sit in this space (title bar is hidden)
        .onAppear { geo.hourHeight = CGFloat(hourHeight); takePlanRequest() }
        .onChange(of: store.planMyDayRequest) { takePlanRequest() }
        .onChange(of: store.todayRequest) { scrollRequest += 1 }
        .onChange(of: geo.hourHeight) { _, new in hourHeight = Double(new) }
        .onChange(of: hourHeight) { _, new in if CGFloat(new) != geo.hourHeight { geo.hourHeight = CGFloat(new) } }   // the View ▸ Zoom menu writes here
        .alert("Busy day", isPresented: Binding(get: { store.overloadWarning != nil }, set: { if !$0 { store.overloadWarning = nil } })) {
            Button("OK") { store.overloadWarning = nil }
        } message: { Text(store.overloadWarning ?? "") }
        .sheet(isPresented: Binding(get: { plan != nil }, set: { if !$0 { plan = nil } })) { planSheet }
    }

    // MARK: Header

    /// One row when there is room. Two or three rows when the task list and the inspector are both open.
    private var header: some View {
        let blocks = store.blocks(for: store.selectedDay...store.selectedDay)
        let totals = store.dayTotals(store.selectedDay, blocks: blocks, workStart: workStart, workEnd: workEnd)
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                navButtons
                VStack(alignment: .leading, spacing: 0) {
                    titleText
                    statsView(totals, width: 220)
                }
                Spacer(minLength: 0)
                planButton(compact: false)
                zoomButtons
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) { navButtons; titleText; Spacer(minLength: 0) }
                HStack(spacing: 10) {
                    statsView(totals, width: 220)
                    Spacer(minLength: 0)
                    planButton(compact: false)
                    zoomButtons
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) { navButtons; titleText; Spacer(minLength: 0) }
                statsView(totals, width: 220)
                HStack(spacing: 10) {
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
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("Timeline").themedHeading(theme, 20, weight: .semibold).foregroundStyle(theme.ink)
                Spacer(minLength: 0)
                planButton(compact: true)
                zoomButtons
            }
            .buttonStyle(.bordered).controlSize(.small)
            statsView(totals, width: nil)
        }
    }

    /// Under the title: the workload bar for a day, the numbers of the month for the month.
    /// The tooltip keeps the old numbers: free time and tasks done.
    @ViewBuilder private func statsView(_ totals: (planned: Int, free: Int, done: Int, total: Int), width: CGFloat?) -> some View {
        if kind == .month {
            statsText(monthStats, over: false)
        } else {
            let _ = dailyLimit
            WorkloadBar(planned: totals.planned, limit: store.dailyLimitMinutes,
                        detail: "\(PlannerMath.duration(totals.planned)) planned · \(PlannerMath.duration(totals.free)) free in working hours · \(totals.done)/\(totals.total) done")
                .frame(width: width)
        }
    }

    @ViewBuilder private var navButtons: some View {
        Button { move(-1) } label: { Image(systemName: "chevron.left") }.help("Previous").accessibilityLabel("Previous")
        Button("Today") { store.selectedDay = .today(); scrollRequest += 1 }
            .fixedSize()
        Button { move(1) } label: { Image(systemName: "chevron.right") }.help("Next").accessibilityLabel("Next")
        Button { store.openDailyNote(store.selectedDay) } label: { Image(systemName: "note.text") }
            .accessibilityLabel("Note for the day")
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
        if kind == .month {
            Toggle(isOn: $moodTint) { Image(systemName: "face.smiling") }
                .toggleStyle(.button)
                .help("Tint each day by the mood of its note").accessibilityLabel("Tint days by mood")
        } else if compact {
            Button { showPlan() } label: { Image(systemName: "wand.and.stars") }
                .accessibilityLabel("Plan my day")
                .help("Plan my day: fit today's unscheduled tasks into free working hours")
        } else {
            Button("Plan my day") { showPlan() }
                .fixedSize()
                .help("Fit today's unscheduled tasks into free working hours")
        }
    }

    @ViewBuilder private var zoomButtons: some View {
        if kind != .month {
            Button { zoom(1 / 1.2) } label: { Image(systemName: "minus.magnifyingglass") }.help("Zoom out")
            Button { zoom(1.2) } label: { Image(systemName: "plus.magnifyingglass") }.help("Zoom in")
        }
    }

    private var title: String {
        switch kind {
        case .today: return store.selectedDay.date.formatted(.dateTime.weekday(.wide).day().month(.wide))
        case .month: return store.selectedDay.date.formatted(.dateTime.month(.wide).year())
        case .week:
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
        store.selectedDay = kind.moved(store.selectedDay, by: direction)
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
                .onTapGesture { store.selectedDay = day }
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
        let result = store.planMyDayPreview(day: store.selectedDay, workStart: workStart, workEnd: workEnd, step: PlannerMath.step)
        if result.isEmpty { store.showToast("Nothing to plan. No unscheduled task fits in working hours.") } else { plan = result }
    }

    private var planSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Plan my day").themedHeading(theme, 22, weight: .semibold)
            Text("Grove will place these tasks in free working hours, highest priority first.")
                .font(theme.body(12)).foregroundStyle(theme.muted)
            ForEach(Array((plan ?? []).enumerated()), id: \.offset) { _, item in
                HStack {
                    Text("\(PlannerMath.clock(item.start))–\(PlannerMath.clock(item.start + PlannerMath.blockLength(item.task.estimateMin)))")
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
