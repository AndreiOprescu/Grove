import SwiftUI
import GroveCore

enum PlannerMode: Int, CaseIterable, Identifiable {
    case day = 1, threeDay = 3, week = 7
    var id: Int { rawValue }
    var label: String {
        switch self { case .day: "Day"; case .threeDay: "3 Days"; case .week: "Week" }
    }
}

struct PlannerView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.theme) private var theme

    @AppStorage("planner.mode") private var modeRaw = PlannerMode.day.rawValue
    @AppStorage("planner.hourHeight") private var hourHeight = 64.0
    @AppStorage("planner.snap") private var snapStep = 5
    @AppStorage("planner.workStart") private var workStart = 9 * 60
    @AppStorage("planner.workEnd") private var workEnd = 18 * 60
    @AppStorage("planner.trayOpen") private var trayOpen = true

    @State private var geo = PlannerGeometry()
    @State private var dropToTray = false
    @State private var scrollRequest = 0
    @State private var plan: [(task: TaskItem, start: Int)]?

    private var mode: PlannerMode { PlannerMode(rawValue: modeRaw) ?? .day }

    private var days: [DayKey] {
        switch mode {
        case .day: [store.selectedDay]
        case .threeDay: (0..<3).map { store.selectedDay.adding(days: $0) }
        case .week: (0..<7).map { store.selectedDay.weekStart().adding(days: $0) }
        }
    }

    var body: some View {
        let _ = store.revision   // re-run this view after every saved change
        VStack(spacing: 10) {
            header
            allDayStrip
            HStack(alignment: .top, spacing: 12) {
                if trayOpen {
                    UnscheduledTray(day: store.selectedDay, isDropTarget: dropToTray,
                                    workStart: workStart, workEnd: workEnd, snapStep: snapStep)
                        .transition(.opacity)
                }
                VStack(spacing: 0) {
                    if days.count > 1 { dayHeaders }
                    PlannerGrid(days: days, geo: $geo, dropToTray: $dropToTray, scrollRequest: scrollRequest,
                                snapStep: snapStep, workStart: workStart, workEnd: workEnd)
                }
                .background(RoundedRectangle(cornerRadius: theme.radius, style: .continuous).fill(theme.surface))
                .overlay(RoundedRectangle(cornerRadius: theme.radius, style: .continuous).strokeBorder(theme.line))
                .clipShape(RoundedRectangle(cornerRadius: theme.radius, style: .continuous))
            }
        }
        .padding(.horizontal, 16).padding(.bottom, 16)
        .padding(.top, 34)   // the window buttons sit in this space (title bar is hidden)
        .overlay(alignment: .bottom) { toast }
        .onAppear { geo.hourHeight = CGFloat(hourHeight) }
        .onChange(of: geo.hourHeight) { _, new in hourHeight = Double(new) }
        .alert("Busy day", isPresented: Binding(get: { store.overloadWarning != nil }, set: { if !$0 { store.overloadWarning = nil } })) {
            Button("OK") { store.overloadWarning = nil }
        } message: { Text(store.overloadWarning ?? "") }
        .sheet(isPresented: Binding(get: { plan != nil }, set: { if !$0 { plan = nil } })) { planSheet }
        .animation(.easeInOut(duration: 0.2), value: trayOpen)
    }

    // MARK: Header

    private var header: some View {
        let blocks = store.blocks(for: store.selectedDay...store.selectedDay)
        let totals = store.dayTotals(store.selectedDay, blocks: blocks, workStart: workStart, workEnd: workEnd)
        return HStack(spacing: 10) {
            Button { trayOpen.toggle() } label: { Image(systemName: "sidebar.left") }
                .help("Show or hide the unscheduled tray")
            Button { move(-1) } label: { Image(systemName: "chevron.left") }.help("Previous")
            Button("Today") { store.selectedDay = .today(); scrollRequest += 1 }
                .keyboardShortcut("t", modifiers: [.command, .shift])
            Button { move(1) } label: { Image(systemName: "chevron.right") }.help("Next")
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.system(.title2, design: .serif, weight: .semibold)).foregroundStyle(theme.ink)
                let over = totals.planned > store.dailyLimitMinutes
                Text("\(over ? "⚠︎ " : "")\(PlannerMath.duration(totals.planned)) planned · \(PlannerMath.duration(totals.free)) free · \(totals.done)/\(totals.total) done")
                    .font(.system(size: 11, weight: over ? .bold : .regular, design: .rounded))
                    .foregroundStyle(over ? theme.accent2 : theme.muted)
            }
            Spacer()
            Button("Plan my day") { showPlan() }.help("Fit today's unscheduled tasks into free working hours")
            Picker("View", selection: $modeRaw) {
                ForEach(PlannerMode.allCases) { Text($0.label).tag($0.rawValue) }
            }
            .pickerStyle(.segmented).frame(width: 200).labelsHidden()
            Button { zoom(1 / 1.2) } label: { Image(systemName: "minus.magnifyingglass") }.help("Zoom out")
            Button { zoom(1.2) } label: { Image(systemName: "plus.magnifyingglass") }.help("Zoom in")
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
    }

    private var title: String {
        switch mode {
        case .day: return store.selectedDay.date.formatted(.dateTime.weekday(.wide).day().month(.wide))
        default:
            let d = days
            return "\(d.first!.date.formatted(.dateTime.day().month(.abbreviated))) – \(d.last!.date.formatted(.dateTime.day().month(.abbreviated).year()))"
        }
    }

    private func move(_ direction: Int) {
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
                    Text(day.date.formatted(.dateTime.weekday(.abbreviated))).font(.system(size: 11, design: .rounded))
                    Text(day.date.formatted(.dateTime.day())).font(.system(size: 15, weight: .bold, design: .rounded))
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
                Text("All day").font(.system(size: 11, design: .rounded)).foregroundStyle(theme.muted)
                ForEach(events) { e in
                    Text(e.title).font(.system(size: 11, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(theme.color(named: e.color).opacity(0.2)))
                        .foregroundStyle(theme.ink)
                }
                Spacer()
            }
        }
    }

    @ViewBuilder private var toast: some View {
        if let text = store.toast {
            Text(text).font(.system(size: 12, weight: .semibold, design: .rounded))
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Capsule().fill(theme.ink)).foregroundStyle(theme.bg)
                .padding(.bottom, 20)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: Plan my day

    private func showPlan() {
        let result = store.planMyDayPreview(day: store.selectedDay, workStart: workStart, workEnd: workEnd, step: snapStep)
        if result.isEmpty { store.showToast("Nothing to plan. No unscheduled task fits in working hours.") } else { plan = result }
    }

    private var planSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Plan my day").font(.system(.title2, design: .serif, weight: .semibold))
            Text("Grove will place these tasks in free working hours, highest priority first.")
                .font(.system(size: 12, design: .rounded)).foregroundStyle(theme.muted)
            ForEach(Array((plan ?? []).enumerated()), id: \.offset) { _, item in
                HStack {
                    Text("\(PlannerMath.clock(item.start))–\(PlannerMath.clock(item.start + max(5, item.task.estimateMin)))")
                        .monospacedDigit().foregroundStyle(theme.accent)
                    Text(item.task.title).lineLimit(1)
                    Spacer()
                }
                .font(.system(size: 13, design: .rounded))
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
