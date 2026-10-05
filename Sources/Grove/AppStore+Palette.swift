import Foundation
import GroveCore

/// One row of the ⌘K palette.
struct PaletteItem: Identifiable, Equatable {
    enum Action: Equatable {
        case command(PaletteCommandId)
        case goTo(DayKey)
        case open(ItemRef)
    }
    var action: Action
    var title: String
    var detail = ""
    /// An SF Symbol name.
    var symbol: String
    var shortcut: String?
    var done = false

    var id: String {
        switch action {
        case .command(let c): "command-\(c.rawValue)"
        case .goTo(let d): "day-\(d.description)"
        case .open(let r): "\(r.type.rawValue)-\(r.id)"
        }
    }
}

extension AppStore {
    /// The most item rows the palette shows.
    static let paletteItemLimit = 10

    // MARK: Opening and closing

    func togglePalette() {
        if paletteOpen {
            paletteOpen = false
        } else {
            paletteText = ""
            paletteOpen = true
        }
    }

    // MARK: Rows

    /// The rows for the text in the box: a day, then the commands that match, then items found by search.
    func paletteItems(for raw: String, today: DayKey = .today()) -> [PaletteItem] {
        let query = PaletteRules.parse(raw)
        var rows: [PaletteItem] = []
        let day = query.commandsOnly ? nil : PaletteRules.date(in: query.text, today: today)
        if let day {
            rows.append(PaletteItem(action: .goTo(day), title: PaletteRules.dayTitle(day, today: today),
                                    detail: PaletteRules.dayDetail(day), symbol: "calendar"))
        }
        for c in PaletteRules.commands(matching: query.text) where !(day == today && c.id == .goToday) {
            rows.append(PaletteItem(action: .command(c.id), title: c.title, symbol: c.symbol, shortcut: c.shortcut))
        }
        if !query.commandsOnly, !query.text.isEmpty {
            let hits = (try? repos.search.search(query.text, limit: Self.paletteItemLimit * 3)) ?? []
            rows += hits.compactMap(paletteItem(for:)).prefix(Self.paletteItemLimit)
        }
        return rows
    }

    /// Reads the item behind a hit. Nil when it is gone, or when it is a task block (its task is listed instead).
    private func paletteItem(for hit: SearchHit) -> PaletteItem? {
        let ref = hit.ref
        switch ref.type {
        case .task:
            guard let t = task(ref.id) else { return nil }
            let done = t.status == .done
            var detail = "Task"
            if done { detail += " · done" }
            if let day = t.planDate { detail += " · " + PaletteRules.dayDetail(day) }
            return PaletteItem(action: .open(ref), title: t.title, detail: detail, symbol: done ? "checkmark.circle.fill" : "circle", done: done)
        case .event:
            guard let e = try? repos.events.get(ref.id), e.kind == .event else { return nil }
            let when = e.allDay
                ? AtDatePlanner.whenLabel(day: e.start.day, start: nil, end: nil)
                : AtDatePlanner.whenLabel(day: e.start.day, start: e.start.minute, end: e.end.day == e.start.day ? e.end.minute : nil)
            return PaletteItem(action: .open(ref), title: e.title.isEmpty ? "Untitled" : e.title, detail: "Event · " + when, symbol: "calendar")
        case .note:
            guard let n = note(ref.id) else { return nil }
            let kind = switch n.kind { case .note: "Note"; case .daily: "Daily note"; case .weekly: "Weekly note" }
            return PaletteItem(action: .open(ref), title: n.title.isEmpty ? "Untitled" : n.title, detail: kind, symbol: "note.text")
        }
    }

    // MARK: Running

    func runPalette(_ item: PaletteItem) {
        switch item.action {
        case .command(let id):
            run(id)
        case .goTo(let day):
            paletteOpen = false
            show(day)
        case .open(let ref):
            paletteOpen = false
            open(ref)
        }
    }

    func run(_ id: PaletteCommandId) {
        if id == .goToDate {
            // The palette stays open and waits for a day.
            paletteOpen = true
            paletteText = "go to "
            return
        }
        paletteOpen = false
        switch id {
        case .newTask:
            if screen != .planner { screen = .today }   // both screens have the task list
            requestQuickAdd()
        case .newNote: newNote()
        case .todayNote: openDailyNote(.today())
        case .goToday: show(.today())
        case .goToDate: break
        case .planMyDay:
            show(.today())
            planMyDayRequest += 1
        case .showPlanner: screen = .planner
        case .showCalendar: screen = .calendar
        case .showNotes: screen = .notes
        case .showGarden: screen = .garden
        case .toggleTheme: nextTheme()
        case .toggleMotion: setMotion(!motionSetting)
        }
    }

    /// The Today screen shows `day`: its timeline, its tasks and its note.
    private func show(_ day: DayKey) {
        selectedDay = day
        screen = .today
    }
}
