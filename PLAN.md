# Grove — build plan (native macOS To-Do + Day Planner + Calendar + Notes)

> **For the builder (Sonnet 5.5):** read this whole file once before you write code.
> Build in the milestone order of §13. After each milestone, run the verify step and
> commit. Do not skip the tests for the Day Planner math — it is the most important feature.
> Visual reference: `design/layouts.html` (open it in a browser). It contains an
> interactive JS version of the planner drag/resize/overlap behaviour. Match it.

---

## 0. CHOICES (the owner edits this block — read it first)

```
LAYOUTS_TO_BUILD: B          # one or more of A,B,C,D. First one is the default.
                             # A=Garden  B=Day Spread  C=Week Board  D=Journal
DEFAULT_THEME:    grove      # grove | minimal | futuristic | vintage
APP_NAME:         Grove
BUNDLE_ID:        local.grove.app
```

If more than one layout is listed, build all of them and add a layout picker in
Settings and in the View menu (§8). If only one is listed, still keep the `AppLayout`
enum so more can be added later.

---

## 1. What we are building

A native macOS app named **Grove**. One window. It opens from an icon on the Desktop.

Four connected parts:

1. **Day Planner** (most important). A vertical timeline of the day. Drag tasks and
   events onto it. Drag a block to change its time. Drag its top or bottom edge to
   change its duration. Blocks may overlap; overlapping blocks are shown side by side.
   It must feel effortless: smooth 60 fps dragging, snapping, live time labels, undo.
2. **Tasks.** Tasks for a specific day, for a whole week (no day picked yet), or for
   "someday". Lists, tags, priority, subtasks, due dates, estimates, repeating tasks.
3. **Calendar.** Day / 3-day / Week / Month views. Events and task time-blocks are the
   same thing on the calendar. The planner *is* the calendar's day/week view.
4. **Notes.** Free notes, an automatic daily note per day, and a weekly note per week.
   Notes link to tasks, events and other notes, and can create tasks and events.

Look and feel: alive and natural. Soft drifting colour light in the background, a small
plant that grows as you finish the day's tasks, gentle spring animations. Four themes:
**Grove** (natural, default), **Minimal**, **Futuristic**, **Vintage**. Motion can be
turned off and respects macOS "Reduce motion".

Everything is stored locally on this Mac. No accounts, no network, no third-party code.

### 1.1 Acceptance checklist (the app is "done" when every line has proof)

- [ ] `scripts/install.sh` builds the app, installs `~/Applications/Grove.app`, and puts a
      `Grove` icon on the Desktop. Double-clicking it opens the app.
- [ ] The app has its own custom icon (not the generic one) in Finder, Dock and Desktop.
- [ ] Planner: create a block by dragging on empty time; by double-click; by dragging a
      task from the task list onto the timeline.
- [ ] Planner: move a block by dragging (snaps to a fixed 15-min grid).
- [ ] Planner: resize from the top edge and from the bottom edge. Minimum 15 min.
- [ ] Planner: overlapping blocks are allowed and shown side by side in columns.
- [ ] Planner: in 3-day / week mode, drag a block to another day.
- [ ] Planner: live label while dragging shows `11:15 – 12:45 · 1h 30m`.
- [ ] Planner: ⌘Z / ⇧⌘Z undo and redo every planner change.
- [ ] Planner: keyboard moves/resizes the selected block (§5.1.6).
- [ ] Planner: ⇧ while dropping pushes later overlapping blocks down ("ripple").
- [ ] Planner: "Fit" puts a task into the next free gap.
- [ ] Tasks: quick add with natural language (`Call mum tomorrow 6pm for 20m #home !2`).
- [ ] Tasks: day / week / someday buckets; lists; tags; subtasks; repeat rules.
- [ ] Calendar: day, 3-day, week, month views; events with repeat rules.
- [ ] Notes: editor with headings, bold, italics, checklists, `[[links]]`, backlinks.
- [ ] Notes: `- [ ] text` inside a note creates a real task that stays in sync.
- [ ] Notes: `@fri 9am` inside a note offers to create an event/block.
- [ ] Daily note and weekly note exist automatically and show linked items.
- [ ] Every interconnection in §5.5 works.
- [ ] Four themes switch live; Grove and Minimal follow light/dark mode.
- [ ] Motion toggle; Reduce Motion respected.
- [ ] ⌘K command palette searches tasks, events and notes (full-text).
- [ ] Notifications for blocks/events/tasks with a time.
- [ ] Menu bar item shows the next block and a quick-add field.
- [ ] Data survives quit/relaunch. Daily automatic backup. JSON export/import works.
- [ ] `scripts/test.sh` passes.

---

## 2. Tech stack and hard constraints (verified on this Mac on 2026-10-02)

| Fact | Consequence |
|---|---|
| macOS 26.3, Apple Silicon (arm64). | Target `macOS 26`. Liquid Glass APIs (`.glassEffect()`) are available. |
| **No Xcode.** Only Command Line Tools. Swift 6.3. | Use **Swift Package Manager** (`swift build`). No `.xcodeproj`. No asset catalogs. The `.app` bundle is assembled by a shell script (§11). |
| **SwiftData macros are NOT available** (only Observation macros ship with CLT). | Do **not** use SwiftData / `@Model`. Use **SQLite** via the system C library (`import SQLite3`, link `sqlite3`). `@Observable` works. |
| System SQLite 3.51 has FTS5. | Use an FTS5 table for search. |
| XCTest is not available. Swift Testing works **only with extra flags**. | Use `import Testing`. Always run tests through `scripts/test.sh` (§12). |
| SPM resource bundles break inside a hand-made `.app`. | **No SPM resources.** Draw all art in code. The icon is generated by a script. Use only fonts already on macOS. |
| Verified compiling: `glassEffect`, `pointerStyle(.frameResize(position:))`, `DragGesture` in a named coordinate space, `.draggable(String)` + `.dropDestination(for: String.self)`, `MenuBarExtra`, `Settings` scene. | Use these APIs. |

Other rules:

- **Zero third-party dependencies.** Only Apple frameworks: SwiftUI, AppKit, Observation,
  SQLite3, UserNotifications, UniformTypeIdentifiers, Foundation.
- Swift tools version **6.2**, language mode **v5** (`.swiftLanguageMode(.v5)`) to avoid
  strict-concurrency noise. Mark the store and UI types `@MainActor`.
- Dates: store **local wall-clock** strings, no time zones (personal, single-device app):
  dates `YYYY-MM-DD`, date-times `YYYY-MM-DDTHH:MM`. Week starts **Monday** (setting).
- IDs: `UUID().uuidString`.

---

## 3. Repository layout

```
To Do/
├─ PLAN.md                     (this file)
├─ CLAUDE.md                   (short rules for the builder)
├─ design/layouts.html         (visual reference; do not ship)
├─ docs/assumptions.md         (decisions log — append to it)
├─ Package.swift
├─ .gitignore                  (.build/, dist/, *.sqlite*, .DS_Store)
├─ scripts/
│  ├─ make_icon.swift          (draws the 1024px icon PNG)
│  ├─ build_app.sh             (swift build + assemble Grove.app + sign)
│  ├─ install.sh               (build, install to ~/Applications, Desktop link, open)
│  └─ test.sh                  (swift test with the required flags)
├─ Sources/
│  ├─ GroveCore/               (pure logic — NO SwiftUI/AppKit imports; fully tested)
│  │  ├─ Model/                Task.swift, Event.swift, Note.swift, ListItem.swift,
│  │  │                        Tag.swift, Link.swift, Recurrence.swift, DayKey.swift
│  │  ├─ Database/             Database.swift (SQLite wrapper), Migrations.swift,
│  │  │                        Repositories.swift (TaskRepo, EventRepo, NoteRepo, …)
│  │  ├─ Planner/              PlannerMath.swift (snap, layout, ripple, free slots)
│  │  ├─ Parsing/              QuickAddParser.swift, NoteParser.swift (links, checkboxes,
│  │  │                        @date tokens), DateWords.swift
│  │  ├─ Recurrence/           RecurrenceEngine.swift
│  │  └─ Services/             SearchIndex.swift, Backup.swift, ExportImport.swift,
│  │                           LinkIndexer.swift, WeeklySummary.swift
│  └─ Grove/                   (the app — SwiftUI)
│     ├─ GroveApp.swift        (@main, scenes, commands, menu bar extra)
│     ├─ AppStore.swift        (@Observable @MainActor state + undo)
│     ├─ Theme/                Theme.swift, Themes.swift, AmbientBackground.swift,
│     │                        GrowingPlant.swift, CheckBurst.swift
│     ├─ Layouts/              RootView.swift, LayoutA_Garden.swift, LayoutB_DaySpread.swift,
│     │                        LayoutC_WeekBoard.swift, LayoutD_Journal.swift
│     ├─ Planner/              PlannerView.swift, PlannerGrid.swift, BlockView.swift,
│     │                        PlannerGeometry.swift, StickyStrip.swift, StickyRules.swift
│     ├─ Tasks/                TaskListView.swift, TaskRow.swift, TaskInspector.swift,
│     │                        QuickAddField.swift
│     ├─ Calendar/             MonthView.swift, WeekStrip.swift, EventEditor.swift
│     ├─ Notes/                NotesHome.swift, NoteEditor.swift (NSTextView wrapper),
│     │                        MarkdownStyler.swift, LinkSuggestions.swift, BacklinksView.swift
│     ├─ Shared/               CommandPalette.swift, Settings.swift, Notifications.swift,
│     │                        DragPayload.swift, Formatters.swift
│     └─ MenuBar/              MenuBarContent.swift
└─ Tests/GroveCoreTests/       PlannerMathTests, QuickAddParserTests, NoteParserTests,
                               RecurrenceTests, DatabaseTests, LinkIndexerTests
```

### 3.1 `Package.swift` (use exactly)

```swift
// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "Grove",
    platforms: [.macOS(.v26)],
    targets: [
        .target(
            name: "GroveCore",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(
            name: "Grove",
            dependencies: ["GroveCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "GroveCoreTests",
            dependencies: ["GroveCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
```

---

## 4. Data model and storage

Database file: `~/Library/Application Support/Grove/grove.sqlite`.
Open with `sqlite3_open_v2`, then run `PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON;`.
Schema version in `PRAGMA user_version`. `Migrations.swift` holds an ordered array of SQL
strings; apply each one whose index ≥ current version inside a transaction.

### 4.1 Schema (migration 1)

```sql
CREATE TABLE lists (
  id TEXT PRIMARY KEY, name TEXT NOT NULL, emoji TEXT NOT NULL DEFAULT '',
  color TEXT NOT NULL DEFAULT 'accent', sort INTEGER NOT NULL DEFAULT 0,
  archived INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE tasks (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  notes TEXT NOT NULL DEFAULT '',            -- short markdown description
  list_id TEXT REFERENCES lists(id) ON DELETE SET NULL,
  parent_id TEXT REFERENCES tasks(id) ON DELETE CASCADE,   -- subtasks
  priority INTEGER NOT NULL DEFAULT 0,       -- 0 none, 1 low, 2 medium, 3 high
  status TEXT NOT NULL DEFAULT 'open',       -- 'open' | 'done' | 'cancelled'
  bucket TEXT NOT NULL DEFAULT 'inbox',      -- 'inbox' | 'day' | 'week' | 'someday'
  plan_date TEXT,                            -- 'YYYY-MM-DD' when bucket='day'
  plan_week TEXT,                            -- Monday 'YYYY-MM-DD' when bucket='week'
  due TEXT,                                  -- deadline 'YYYY-MM-DD' or 'YYYY-MM-DDTHH:MM'
  estimate_min INTEGER NOT NULL DEFAULT 30,  -- default block length when scheduled
  recurrence TEXT,                           -- JSON RecurrenceRule, nullable
  source_note_id TEXT REFERENCES notes(id) ON DELETE SET NULL, -- created from a note checkbox
  sort REAL NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL, updated_at TEXT NOT NULL, completed_at TEXT
);
CREATE INDEX tasks_plan_date ON tasks(plan_date);
CREATE INDEX tasks_plan_week ON tasks(plan_week);
CREATE INDEX tasks_parent ON tasks(parent_id);

-- Events AND task time-blocks. A block is an event with task_id set.
CREATE TABLE events (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,                       -- for blocks: mirrors task title at render time
  start TEXT NOT NULL,                       -- 'YYYY-MM-DDTHH:MM'
  end TEXT NOT NULL,                         -- 'YYYY-MM-DDTHH:MM' (> start)
  all_day INTEGER NOT NULL DEFAULT 0,
  kind TEXT NOT NULL DEFAULT 'event',        -- 'event' | 'block'
  task_id TEXT REFERENCES tasks(id) ON DELETE CASCADE,
  color TEXT NOT NULL DEFAULT 'accent2',     -- theme colour token name
  location TEXT NOT NULL DEFAULT '',
  notes TEXT NOT NULL DEFAULT '',
  recurrence TEXT,                           -- JSON RecurrenceRule (events only)
  series_id TEXT REFERENCES events(id) ON DELETE CASCADE, -- detached occurrence of a series
  original_date TEXT,                        -- which occurrence it replaces
  created_at TEXT NOT NULL, updated_at TEXT NOT NULL
);
CREATE INDEX events_start ON events(start);
CREATE INDEX events_task ON events(task_id);

CREATE TABLE event_exdates (event_id TEXT NOT NULL REFERENCES events(id) ON DELETE CASCADE,
  date TEXT NOT NULL, PRIMARY KEY(event_id, date));

CREATE TABLE notes (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  body TEXT NOT NULL DEFAULT '',             -- markdown-lite text
  kind TEXT NOT NULL DEFAULT 'note',         -- 'note' | 'daily' | 'weekly'
  date TEXT,                                 -- daily: the day; weekly: the Monday
  pinned INTEGER NOT NULL DEFAULT 0,
  mood INTEGER,                              -- daily only, 1..3, nullable
  created_at TEXT NOT NULL, updated_at TEXT NOT NULL
);
CREATE UNIQUE INDEX notes_daily ON notes(kind, date) WHERE kind IN ('daily','weekly');

-- Typed links between any two items. Rebuilt for a note each time the note is saved
-- (origin='parsed'); manual links made in the UI use origin='manual'.
CREATE TABLE links (
  src_type TEXT NOT NULL, src_id TEXT NOT NULL,   -- 'note' | 'task' | 'event'
  dst_type TEXT NOT NULL, dst_id TEXT NOT NULL,
  origin TEXT NOT NULL DEFAULT 'manual',
  PRIMARY KEY (src_type, src_id, dst_type, dst_id)
);
CREATE INDEX links_dst ON links(dst_type, dst_id);

CREATE TABLE tags (id TEXT PRIMARY KEY, name TEXT NOT NULL UNIQUE COLLATE NOCASE);
CREATE TABLE task_tags (task_id TEXT REFERENCES tasks(id) ON DELETE CASCADE,
  tag_id TEXT REFERENCES tags(id) ON DELETE CASCADE, PRIMARY KEY(task_id, tag_id));
CREATE TABLE note_tags (note_id TEXT REFERENCES notes(id) ON DELETE CASCADE,
  tag_id TEXT REFERENCES tags(id) ON DELETE CASCADE, PRIMARY KEY(note_id, tag_id));

CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL);

CREATE VIRTUAL TABLE search USING fts5(item_type UNINDEXED, item_id UNINDEXED, title, body,
  tokenize='unicode61 remove_diacritics 2');
```

Note: `tasks.source_note_id` references `notes` which is created later in the same
migration. That is fine in SQLite (references are checked at write time). Keep the
statements in one migration string executed with `sqlite3_exec`.

**Migration 2 — attachments** (added 2026-10-02 at the owner's request: images in task bodies and notes):

```sql
CREATE TABLE attachments (
  id TEXT PRIMARY KEY, mime TEXT NOT NULL, data BLOB NOT NULL,
  width INTEGER NOT NULL DEFAULT 0, height INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL
);
```

Images live in the database (not loose files) so the daily `VACUUM INTO` backup and the
export both include them. Images are downscaled to at most 1600 px on the long side
before they are stored. An image is referenced from text as `![alt](grove-image:ID)`.
When a task or note is saved, any attachment that no text references any more is deleted.

### 4.2 Swift model structs (in GroveCore)

Plain `struct`s, `Codable, Identifiable, Hashable, Sendable`. Fields mirror the columns.
Add helpers:

- `DayKey` — a `struct` wrapping `"YYYY-MM-DD"` with `init(Date)`, `date`, `adding(days:)`,
  `weekStart(mondayFirst:)`, `Comparable`. Use a fixed `Calendar(identifier: .gregorian)`
  with `TimeZone.current` and a cached `DateFormatter` (`en_US_POSIX`).
- `WallTime` — `struct { day: DayKey; minute: Int }` (minute 0…1440) with parse/format
  of `YYYY-MM-DDTHH:MM`. All planner maths uses **minutes since midnight**.
- `RecurrenceRule` — `Codable` `{ freq: daily|weekly|monthly|yearly, interval: Int,
  weekdays: [Int]? (1=Mon…7=Sun), until: DayKey?, count: Int? }`.

### 4.3 Database wrapper

`final class Database` (not an actor; used only from the main actor — the data is small).
API:

```swift
func execute(_ sql: String, _ args: [SQLValue] = []) throws
func query<T>(_ sql: String, _ args: [SQLValue] = [], map: (Row) throws -> T) throws -> [T]
func transaction(_ body: () throws -> Void) throws
enum SQLValue { case text(String), int(Int), real(Double), null }
```

Use `sqlite3_prepare_v2`, bind by index, `SQLITE_TRANSIENT` =
`unsafeBitCast(-1, to: sqlite3_destructor_type.self)`. Cache prepared statements in a
dictionary keyed by SQL. Throw `DatabaseError(message: String(cString: sqlite3_errmsg(db)))`.
`Database(path:)` and `Database.inMemory()` (for tests).

Repositories (`TaskRepo`, `EventRepo`, `NoteRepo`, `ListRepo`, `TagRepo`, `LinkRepo`,
`SettingsRepo`) take the `Database`. Every write also updates the `search` table for
that item (delete + insert row).

### 4.4 Backups and export

- On launch, if no backup for today exists: `VACUUM INTO
  '~/Library/Application Support/Grove/Backups/grove-YYYY-MM-DD.sqlite'`. Keep newest 14.
- Settings → Data: "Export JSON…" (NSSavePanel; all tables), "Import JSON…" (replaces all
  data after a confirm dialog that says it replaces everything), "Show data folder".

---

## 5. Features

### 5.1 Day Planner — THE MOST IMPORTANT FEATURE

The planner is a vertical time grid. It appears:
- as the left column of Layout B (day mode),
- as the main view of the **Planner** screen in every layout (sidebar item / ⌘1),
- as the fixed week view of the **Planner** screen (7 days) and as the one-day timeline of the
  **Today** screen (today only). Owner request, 2026-10-09: there is no Day / 3-Day mode and no
  mode picker. Each top tab has one view: Today = today, Planner = week, Calendar = month.

Reference behaviour: `design/layouts.html`, Layout B timeline (drag, resize, overlap).

#### 5.1.1 Geometry

```swift
struct PlannerGeometry {
    var hourHeight: CGFloat          // default 64, zoom range 36...160 (⌘+ / ⌘- / pinch)
    var dayStartMinute = 0           // grid always covers 00:00–24:00
    var gutterWidth: CGFloat = 52    // hour labels column
    func y(forMinute m: Int) -> CGFloat { CGFloat(m) / 60 * hourHeight }
    func minute(forY y: CGFloat) -> Int { Int((y / hourHeight * 60).rounded()) }
}
```

The grid is inside a vertical `ScrollView`. On appear and on "Today" it scrolls so that
*now − 1h* is at the top (use `ScrollViewReader` with invisible anchors every hour, or
`.scrollPosition`). Visible default range is about 07:00–22:00 at hourHeight 64.

Drawn layers (bottom → top): hour lines + half-hour faint lines, hour labels in the
gutter, "working hours" tint (setting, default 09–18, very faint), blocks, the dragged
block ghost, the **now line** (accent2, 2pt, dot at left, pulses gently when motion is on).
Past time of today is drawn slightly faded.

#### 5.1.2 Items on the grid

`PlannerBlock` (view model): `id` (event id, or `"\(seriesId)@\(date)"` for a recurring
occurrence), `title`, `startMinute`, `endMinute`, `day: DayKey`, `kind` (event/block),
`taskId?`, `isDone` (block's task status), `color`, `hasNote`, `isRecurring`.

Blocks show: time range (small, bold), title, duration, a round checkbox if it is a task
block (clicking it completes the task with the check-burst animation), a small ✎ icon if
linked notes exist. Text truncates with "…". Blocks shorter than 25 min show a single line.
Done blocks are faded with strike-through. Events are filled with their colour at 14%
opacity and a 3pt left border; task blocks use a dashed 1pt border + 3pt solid left
border (exactly as in `design/layouts.html`).

A task block with subtasks lists them under the title and short description, in panel
order, without cancelled ones. Each row has a small mark and the title; done rows are
struck through and dimmed. The marks only show; the task panel changes subtasks. The
title keeps one line and the short description comes next. Subtasks get the lines left
(`PlannerLayoutRules.blockRows`). When not all fit, the last line says "+3 more"; with
one line only it says "1/4 subtasks". With no line left (and in single-line blocks) a
small "1/4" (done/total) sits in the title row. Lines the subtasks do not need go back to
the title and description. Subtask rows do not make the block "tight": a block on top
may cover them, but never the title and description rows.

All-day events show in a strip above the grid.

#### 5.1.3 Overlap layout (pure function in `PlannerMath`)

Overlaps are always allowed. Lay out side by side:

```swift
public struct Span: Equatable, Sendable { public var id: String; public var start: Int; public var end: Int }
public struct Placement: Equatable, Sendable { public var column: Int; public var columns: Int }

public static func layoutColumns(_ spans: [Span]) -> [String: Placement] {
    let sorted = spans.sorted { $0.start != $1.start ? $0.start < $1.start : ($0.end - $0.start) > ($1.end - $1.start) }
    var result: [String: Placement] = [:]
    var cluster: [Span] = []; var clusterEnd = Int.min
    func flush() {
        var colEnds: [Int] = []
        var cols: [String: Int] = [:]
        for s in cluster {
            if let c = colEnds.firstIndex(where: { $0 <= s.start }) { colEnds[c] = s.end; cols[s.id] = c }
            else { colEnds.append(s.end); cols[s.id] = colEnds.count - 1 }
        }
        for s in cluster { result[s.id] = Placement(column: cols[s.id]!, columns: colEnds.count) }
        cluster.removeAll()
    }
    for s in sorted {
        if !cluster.isEmpty && s.start >= clusterEnd { flush(); clusterEnd = Int.min }
        cluster.append(s); clusterEnd = max(clusterEnd, s.end)
    }
    if !cluster.isEmpty { flush() }
    return result
}
```

Block frame: `x = gutter + col * colWidth`, `width = colWidth - 3`, where
`colWidth = (dayColumnWidth - gutter - 6) / columns`. Animate layout changes with
`.spring(response: 0.28, dampingFraction: 0.86)` (instant when motion is off).

#### 5.1.4 Interactions (all must work)

| Action | Result |
|---|---|
| Drag on empty grid space | Draws a selection from press point to current point (snapped). On release: creates a new block and opens an inline title field in it. Esc cancels → nothing saved. Typing a title that matches an existing open task offers "Schedule existing task" (top suggestion). Otherwise creates a new task (bucket `day`) + block. Hold ⌘ while releasing to create a plain **event** instead of a task. |
| Double-click empty space | New 30-min block (or task estimate) at the snapped minute, title field open. |
| Drag a task from any task list / a sticky note onto the grid | Ghost preview follows the pointer showing the time; on drop: creates a block at the snapped minute with length `estimate_min` rounded up to 15 min (at least 15); sets task `bucket='day'`, `plan_date` = that day. |
| Drag a block body | Moves it. Live label `11:15 – 12:45 · 1h 30m` floats next to the block. In multi-day mode, horizontal movement changes the day column. |
| Drag top edge (6pt hit zone) | Changes start; end stays. Cursor `.pointerStyle(.frameResize(position: .top))`. |
| Drag bottom edge (6pt hit zone) | Changes end; start stays. Cursor `.frameResize(position: .bottom)`. |
| Snap | Fixed 15 min (:00, :15, :30, :45). No setting and no ⌥ fine mode. Snap is applied to the *edge being moved*; when moving, snap the start. |
| Min / clamp | Minimum length 15 min. Clamp inside 00:00–24:00. A block cannot cross midnight (clamp). |
| ⇧ held on release (move or resize) | **Ripple**: blocks that start after the moved block's start and now overlap it are pushed down so they start at its end; cascade further (see `ripple`). Show a small "pushed 2 blocks" toast. |
| Release over the sticky strip | Removes the block (task stays, planned for that day with no time, so it shows as a sticky note). |
| Drag a block onto a day in the Week strip / Month view | Moves it to that day, same time. |
| Edge auto-scroll | While dragging within 40pt of the scroll view's top/bottom, auto-scroll (use a `Timer` at 60 Hz, speed proportional to distance). |
| Click a block | Selects it (accent outline). Shows it in the inspector (Layout A) or a popover (others). |
| ⌘-click | Multi-select. Dragging any selected block moves all selected by the same delta. |
| Right-click | Context menu: Duration ▸ 15m, 30m, 45m, 1h, 1h30, 2h, 3h · Colour ▸ (theme tokens) · Duplicate · Split in two · Open / create linked note · Mark done · Unschedule · Delete event. |
| Recurring event occurrence moved or resized | Ask "This event only / All events" (confirmationDialog). "Only this": insert an exdate for the series and a detached copy (`series_id`, `original_date`). "All": change the series time. |

Implementation notes (SwiftUI):
- Put the whole day column in a `ZStack(alignment: .topLeading)` inside
  `.coordinateSpace(.named("plannerGrid"))`. Position blocks with `.offset`/`.position`,
  not layout stacks.
- One `@State var live: LiveEdit?` in `PlannerGrid`:
  `struct LiveEdit { ids: [String]; mode: .move/.resizeTop/.resizeBottom/.create; deltaMinutes: Int; deltaDays: Int; anchorMinute: Int; currentMinute: Int }`.
  Render blocks using the live values when they are in `live.ids`. **Write to the database
  only on gesture end**, as one undoable action. This keeps dragging smooth.
- Gestures: `DragGesture(minimumDistance: 2, coordinateSpace: .named("plannerGrid"))` on the
  block body; separate gestures on the top and bottom handle overlays (place handles
  *above* the body in the ZStack so they win hit-testing). Use `.highPriorityGesture` for
  handles.
- Modifier keys during drag: read `NSEvent.modifierFlags` inside `onChanged`/`onEnded`.
- Task → planner drag uses `DragPayload` strings: `.draggable("grove-task:\(task.id)")`
  and `.dropDestination(for: String.self) { items, location in … }` on the day column.
  Plain `String` avoids having to declare a custom UTType in Info.plist. Use
  `.onDropSessionUpdated`/`dropDestination`'s `isTargeted` + a hover location to draw the
  ghost; if live location is not available, show the ghost only on drop (acceptable).
- Haptic-like feedback: `NSHapticFeedbackManager.defaultPerformer.perform(.alignment, …)`
  each time the snapped value changes (trackpads feel it).

#### 5.1.5 Pure maths (in `GroveCore/Planner/PlannerMath.swift`, all unit-tested)

```swift
public enum PlannerMath {
    public static func snap(_ minute: Int, step: Int) -> Int          // round to nearest step
    public static func clampMove(start: Int, length: Int) -> Int      // keep 0...1440-length
    public static func resizeTop(start: Int, end: Int, newStart: Int, step: Int, minLen: Int = 5) -> (Int, Int)
    public static func resizeBottom(start: Int, end: Int, newEnd: Int, step: Int, minLen: Int = 5) -> (Int, Int)
    public static func layoutColumns(_ spans: [Span]) -> [String: Placement]   // §5.1.3
    /// Push spans that overlap `moved` and start at/after moved.start down, cascading.
    /// Returns only the spans whose start changed. Never moves past 1440 (clamp; may overlap at the end of day).
    public static func ripple(moved: Span, others: [Span]) -> [Span]
    /// First gap of at least `length` minutes, starting search at `from`, ending at `until`.
    public static func firstFreeSlot(length: Int, busy: [Span], from: Int, until: Int, step: Int) -> Int?
    public static func label(start: Int, end: Int) -> String           // "11:15 – 12:45 · 1h 30m"
}
```

Tests must cover: snapping both ways, 15-min minimum on both edges, clamping at 00:00
and 24:00, layout of (a) no overlap → 1 column each, (b) two overlapping → 2 columns,
(c) A overlaps B, B overlaps C, A not C → 2 columns with C reusing column 0, (d) touching
blocks (end == start) do **not** overlap, ripple cascade of three blocks, free-slot when
the day is full returns nil, label formatting (`45m`, `1h`, `1h 30m`).

#### 5.1.6 Keyboard (when a block is selected and the grid has focus)

| Key | Action |
|---|---|
| ↑ / ↓ | Move to the next 15-min grid line up / down |
| ⇧↑ / ⇧↓ | Make shorter / longer: the end edge moves to the next 15-min grid line |
| ← / → | Move to previous / next day |
| Return | Rename |
| Space | Toggle task done |
| ⌘D | Duplicate right after |
| Delete | Unschedule (task block) or delete (event), with undo |
| ⌘T | Jump to today / now |
| ⌘+ / ⌘- | Zoom |
| N | New block at the next free slot after now (uses `firstFreeSlot`) |

Use `.focusable()` + `.onKeyPress`.

#### 5.1.7 Planner extras

- **Sticky-note strip** (right under the day numbers in the week view, and on the
  Today screen timeline; can fold): each day's open tasks that are planned for that day
  but have no block, drawn as sticky notes (priority, then order). Each note shows its
  length. Drag a note onto the grid to give it a time. Drag a block up onto the strip to
  take its time away. Drop a task from a list on a day to plan it for that day with no
  time. Click a note to open the task.
- **Fit** button on each sticky note: places the task in the first free slot from now
  (today) or from the working-hours start (other days). Animate the block growing in.
- **Plan my day** button: fits all of today's unscheduled tasks in priority order into free
  working-hours slots, as one undo step. Shows a preview sheet with Apply / Cancel.
- **Day totals** in the header: "4h 30m planned · 2h 10m free · 3/6 done".
- **End of day roll-over**: on first launch of a new day, if yesterday has open task
  blocks, show a gentle card "3 things from yesterday — Move to today / Leave". Move
  sets `plan_date` = today and removes the old blocks (tasks go to the sticky strip).
- **Focus mode**: right-click a block → "Start focus" → a floating mini timer counts down
  to the block's end; when it ends: "Mark done?" notification.

### 5.2 Tasks

- **Buckets**: Inbox (no date) · Day (`plan_date`) · Week (`plan_week`, any day that week)
  · Someday. A day's task list shows: overdue (open, plan_date < today, dimmed warm
  colour) → today's → "This week (no day yet)" collapsible section.
- **Planner screen task list** (owner request, 2026-10-04): no tabs. It shows every open
  task: "No day yet" first (inbox → week tasks, earliest week first → someday), then
  "By day" (one flat list, earliest day first, late ones on top, no day headings). Quick
  add there goes to the Inbox. The Today page keeps its tabs (Today / Week / Inbox / Someday).
  **Superseded 2026-10-09:** the lists live in three separate left panels (Notes, Tasks,
  Goals), opened from a dock of three buttons at the top left of the Today and Planner
  screens. One panel is open at a time. The **Tasks** panel shows only unscheduled tasks
  (no day yet: inbox, week, someday) and overdue ones; a task with a day today or later is
  not listed. Dropping a task on the planner moves it: it keeps one block, at the new time,
  and the old date and time are removed. The **Today** page shows only today's tasks (no
  tabs). A new task is kept when the user clicks away without pressing Enter.
- **Week view of tasks** (used by Layout C and the "This Week" sidebar item): 7 day columns
  + "Anytime this week" column. Drag tasks between columns (changes `plan_date`; to the
  "anytime" column sets bucket `week`).
- **Row**: checkbox (spring + check-burst), title, chips: list, time block (if any),
  due, estimate, repeat icon, note icon, tags. Priority = coloured 3pt bar on the left.
- **Inspector / detail popover**: title, body (rich, see below), list, tags, priority,
  bucket/date, due, estimate, repeat rule, subtasks (inline add; each has a name, a description, a duration and its own done box),
  "Linked here" (backlinks), "Created from note X" link.
- **Rich task body** (owner request, 2026-10-02). `tasks.notes` holds the body as plain
  Markdown text. The inspector edits it with the same `RichTextEditor` that notes use (M5
  reuses it). It supports: `-` bullets and `1.` numbered lists (Return continues the list,
  Tab / ⇧Tab indents), `- [ ]` checklists, `#`/`##` headings, **bold**, *italic*,
  `inline code`, `[[mentions]]` with autocomplete, and images (paste, drop or "Add image";
  stored per §4.1 migration 2). The row shows a small note icon when the body has text.
- **Referenceable tasks** (owner request). Any task can be mentioned from a note, another
  task's body, an event's notes or the command palette. Mention text is `[[Task title]]`,
  stored as `[[Task title|ID]]` once resolved. The `|ID` part is hidden by the styler (same
  way as the `⟦t:ID⟧` markers). A mention resolves by ID first, then by exact title
  (case-insensitive). Mentions render as chips; click opens the task. If the target is
  deleted, the chip shows struck-through. Renaming a task rewrites `[[Old|ID]]` in every body that links to it.
  Dragging a task from any list into a note or body inserts a mention.
- **Quick add** (`QuickAddField`, ⌘N anywhere, also in the menu bar) with live preview
  chips under the field showing what was parsed. Parser rules (`QuickAddParser`, tested):
  - dates: `today`, `tod`, `tomorrow`, `tmr`, `mon`…`sun` and full names (next
    occurrence, today if same day), `next week` (bucket week, next Monday), `this week`,
    `someday`, `3 oct`, `oct 3`, `3/10` (day/month — European order, setting later), `in 3 days`
  - times: `6pm`, `6:30pm`, `18:00`, `at 9` → creates a **block** at that time (length = duration or 30)
  - duration: `for 45m`, `for 1h`, `for 1h30`, `90m` → estimate
  - `#tag` (multiple), `!1`/`!2`/`!3` priority, `/listname` (fuzzy match existing list)
  - repeat: `every day`, `every weekday`, `every week`, `every mon`, `every 2 weeks`, `every month`
  - `due fri` → deadline, not plan date
  - Matched tokens are removed from the title. Unknown words stay.
- **Repeating tasks**: when completed, create the next instance (copy, new id, new
  `plan_date` from `RecurrenceEngine.next(after:)`; copy subtasks unchecked; copy block
  times if the task had one block).
- **Reorder** by drag inside a list (`sort` REAL; insert between neighbours' values).
- **Completion**: set `completed_at`; check-burst; the growing plant updates.

### 5.3 Calendar

- **Month view**: 6×7 grid. Each cell: day number, up to 3 event pills, "+n", small dots
  for open tasks (count), a leaf glyph if the day has a daily note with text. Click → that
  week in the Planner. Double-click → new all-day event. Drag tasks/blocks/notes onto a day.
- **Week strip** (top of Layout B and the planner header): Mon–Sun with dots = number of
  items (max 3 dots). Click switches day. ‹ › buttons. Today highlighted with accent.
- The Calendar screen shows the month view only. The week view is the Planner screen (§5.1).
- **Event editor** (popover): title, all-day toggle, start, end, colour, location, notes,
  repeat, linked notes, "Create meeting note" button.
- **RecurrenceEngine.occurrences(rule, seriesStart, in range) -> [DayKey]** minus exdates,
  plus detached copies. Tested for daily/weekly(weekdays)/monthly(31st → skip short months)/
  yearly, interval, until, count.

### 5.4 Notes

- **Notes home**: left column list (pinned first, then by updated date), search field,
  filter chips: All · Daily · Weekly · Pinned · tags. Right: editor.
- **Editor**: `NSViewRepresentable` around `NSTextView` (SwiftUI `TextEditor` cannot style
  inline). Plain text storage (markdown-lite). `MarkdownStyler` restyles the visible
  paragraph(s) on each edit via `NSTextStorageDelegate`:
  - `# `, `## `, `### ` headings (theme head font, larger)
  - `**bold**`, `*italic*`, `` `code` ``, `> quote`, `- ` bullets
  - `- [ ] ` / `- [x] ` checkboxes rendered with a clickable ☐/☑ (click toggles text)
  - `[[Title]]` links in accent colour, clickable (`.link` attribute with URL
    `grove://note/<id>` or `grove://task/<id>` / `grove://event/<id>`; handle in
    `textView(_:clickedOnLink:at:)`). Unresolved links are dotted-underlined; clicking one
    creates the note.
  - `@tomorrow 3pm`, `@fri`, `@3 oct 14:00` date tokens tinted accent2.
  - `#tag` tinted muted.
  Save 500 ms after typing stops (debounce) and on window resign.
- **`[[` autocomplete**: when the text before the caret matches `\[\[([^\]]*)$`, show a
  small floating list (child `NSPanel` or SwiftUI overlay positioned at the caret rect
  from `firstRect(forCharacterRange:)`) of matching notes, tasks and events (FTS prefix
  search). ↑↓ Return inserts `[[Exact Title]]`. Esc closes.
- **Daily note**: one per day (`kind='daily'`), created on first open of that day, title
  "Friday, 2 October 2026". Template body: `## Plan\n\n## Notes\n\n## Reflection\n`
  (setting: editable template).
- **Weekly note**: one per week, title "Week 40 · 28 Sep – 4 Oct". Template with
  `## Goals`, `## Notes`, `## Review`.
- Pin, duplicate, delete (with undo), tags from `#tag` in the body.

### 5.5 Interconnections (implement all)

1. **Checkbox → task.** On note save, `NoteParser` finds `- [ ] text` lines. For each line
   without a hidden id marker, create a task (bucket `day` = the daily note's date, or
   inbox for normal notes; quick-add parsing applied to the text) and append an invisible
   marker ` ⟦t:ID⟧` to the line. The styler hides markers (font size 0.01 + clear colour).
   Two-way sync: checking the box completes the task; completing the task elsewhere
   rewrites `[ ]`→`[x]` in the note. Deleting the line does **not** delete the task.
2. **@date → event/block.** When a line contains an `@date time` token, show a small inline
   "＋ Add to planner" button at the line end (or a context-menu item). Creates an event
   (or a task block if the line is a checkbox) and replaces the token with a link chip.
3. **Wiki links + backlinks.** `[[Title]]` or `[[Title|ID]]` to notes/tasks/events (the
   `|ID` form is what gets stored; see §5.2 "Referenceable tasks"). Every note, task and
   event shows a **"Linked here"** section listing backlinks (from `links` table, by ID).
   Task bodies, note bodies and event notes are all link sources.
4. **Daily note ⇄ day.** The daily note's sidebar shows that day's events, blocks and tasks
   (live). The planner header has a "Today's note" button. Month cells show a leaf for days
   with notes.
5. **"Done today" log.** The daily note view shows an auto section (rendered *below* the
   editor, not stored in text) listing tasks completed that day with times.
6. **Meeting notes.** Event popover → "Create meeting note" → note titled
   "<Event> — 2 Oct", body template `## Agenda\n\n## Notes\n\n## Action items\n- [ ] `,
   linked to the event. Action-item checkboxes become tasks (rule 1).
7. **Selection → task.** In the editor, select text → ⇧⌘T (and context menu "Make task")
   → creates a task with that text (quick-add parsed), linked to the note, and turns the
   line into a `- [ ]` checkbox with marker.
8. **Drag between parts.** Drag a note from the notes list onto a day/time in the planner →
   creates a 30-min block "📝 <note title>" linked to the note. Drag a task into a note →
   inserts `[[Task title]]`.
9. **Task/event notes field** supports `[[links]]`, bullets, formatting and images too (same `RichTextEditor`, compact).
10. **Weekly review.** The weekly note shows an auto panel: tasks done this week, tasks
    still open, hours planned vs. hours of done blocks, busiest day, and a button
    "Insert summary" that writes it as text into `## Review`.
11. **Command palette (⌘K)** lists tasks, events, notes, and commands ("New task", "Go to
    date…", "Toggle theme…", "Plan my day"). Typing `>` filters to commands; date text like
    `fri` offers "Go to Friday".
12. **Mood + focus.** Daily note header has a 3-icon mood picker (🌧 ⛅ ☀︎) stored in
    `notes.mood`; month view can tint days by mood (toggle).

### 5.6 Notifications (`UserNotifications`)

- Ask permission on first launch (after the welcome card, not at once).
- Schedule for: event/block start (lead time setting: 0/5/10/15 min, default 5), task
  `due` with a time. Title = item title; body = time range.
- Keep at most the next 60 requests (macOS limit is 64). Re-schedule on every data change
  (debounced 1 s) and on launch. Identifier = `"ev-\(id)-\(start)"`.
- Clicking a notification opens the app on that day/item.
- If permission is denied, show a quiet note in Settings; never block.

### 5.7 Menu bar extra

`MenuBarExtra` with a leaf SF Symbol (`leaf`). Content: "Now: <current block>" /
"Next: <next block> in 25 min", today's progress bar, a quick-add field, "Open Grove".

### 5.8 Window, commands, settings

- One main `WindowGroup` (id "main"), min size 960×620, default 1280×800,
  `.windowStyle(.hiddenTitleBar)` so the ambient background reaches the top; draw content
  under the traffic lights with top padding 38.
- Menu commands: File ▸ New Task ⌘N, New Note ⌥⌘N, New Event ⇧⌘N · View ▸ Today ⌘T,
  Planner ⌘1, Tasks ⌘2, Calendar ⌘3, Notes ⌘4, Day/3-Day/Week ⌥⌘1/2/3, Zoom In/Out,
  Theme ▸, Appearance ▸ (System/Light/Dark), Layout ▸ (if several) · Go ▸ Command Palette ⌘K · Edit ▸ Undo/Redo (system).
- A gear button next to the "Search ⌘K" pill (top right) opens the Settings window, like ⌘,.
- `Settings` scene tabs: **Appearance** (theme picker with live previews, light/dark/system,
  layout picker, motion on/off, accent intensity), **Planner** (working hours, busy-day limit,
  default duration, hour height, week starts Monday/Sunday, mood tint), **Notifications**, **Notes**
  (daily/weekly templates), **Data** (export, import, show folder, backups list).
- Settings are stored in the `settings` table (JSON values) and mirrored in `AppStore`.

### 5.9 Goals (owner request, 2026-10-09)

A goal is a recurring item with **no date** and a **weekly target** of one of two kinds:
**Hours** (time per week) or **Sessions** (number of blocks per week).
- Table `goals` (migration 5): `id, title, notes, color, target_min (default 300), sort,
  archived, created_at, updated_at`. Migration 6 adds `kind` (`hours` | `sessions`, default
  `hours`) and `target_count` (default 3). Events get `goal_id` and `done_at` (migration 5).
- The **Goals** panel (left dock) lists goals with "2.5 / 5 h done" or "3 / 5 sessions done",
  a bar (solid = done, lighter = planned) and "4 h planned", for the week of the chosen day.
  A goal is never marked done in the panel: it stays there every week. Add a goal with a name, Hours or Sessions, and a weekly target
  (Hours: 0.5 h steps, 5 h at first; Sessions: steps of 1, 1–99, 3 at first).
- Click a goal to open its editor in place: name, Hours | Sessions, target per week, colour.
  Click again, press Escape or open another goal to close it. Right-click ▸ Edit… does the same.
- Drag a goal onto a day in the Today timeline or the Planner week: it makes a 1 h block.
  Set the length by resizing the block or with its right-click menu (15 min to 4 h).
- Every goal block in the week is **planned**: Hours adds its length, Sessions adds 1.
  Tick a goal block done (check box, right-click ▸ Mark Done, or space) in Today or the Planner:
  it is also **done**. Un-tick takes it back. Planned includes done. Both can go over the
  target ("7 / 5 h done"). Progress is worked out from the blocks of the planner week; it is never stored, so
  a new week starts at zero. The goal stays, so more blocks can be added in the same week.
- Deleting a goal keeps its blocks as plain blocks. Goals are in export, import and backup.

---

## 6. Themes

`struct Theme: Identifiable` with colour tokens, fonts, shape and motion settings.
Inject with a custom `EnvironmentKey` (`@Environment(\.theme)`). Switching is live and
animated (0.35 s crossfade).
Light or dark is a separate setting (`appearance.mode`: System, Light, Dark), never set by the
theme. Every theme has a light and a dark look (owner request, 2026-10-09).

### 6.1 Tokens (match `design/layouts.html`)

| Token | Grove light | Grove dark | Minimal light | Minimal dark | Futuristic dark | Vintage light |
|---|---|---|---|---|---|---|
| bg | #F3EEE3 | #171C16 | #F7F7F5 | #121212 | #070B16 | #E6D8BA |
| surface | #FBF8F1 | #1F261D | #FFFFFF | #1B1B1B | rgba(22,30,58,.55) + glass | #F3E9D2 |
| surface2 | #ECE5D4 | #2A3327 | #F0F0ED | #262626 | rgba(60,80,140,.22) | #E7D8B6 |
| ink | #2F3A2C | #E6E9DF | #1B1B1A | #EDEDEA | #E4F0FF | #3A2A1B |
| muted | #7D8574 | #8E9886 | #8C8C88 | #8A8A86 | #7F8DB4 | #87705A |
| accent | #5E7F4F | #8DB57A | #1B1B1A | #EDEDEA | #46F0D2 | #8C3B2E |
| accent2 | #C77B4E | #E09A6E | #7C9A7E | #93B596 | #A27BFF | #3F5B4A |
| accent3 | #D9B44A | #E3C567 | #B9B9B4 | #6B6B67 | #FF6FB5 | #B8862B |
| line | #DDD3BF | #333D30 | #E6E6E2 | #2C2C2C | rgba(120,160,255,.20) | #C8B38D |
| blobs | #A9C79A #F2C6A0 #E8DC9A | #3F5E35 #6E4A33 #5E5630 | #E9EEE6 #F1EEE8 #EDEDED | #1E241F #242220 #202020 | #1FD1B5 #7B4DFF #FF4FA3 | #F0D9A8 #E2B98A #F5E6C0 |
| radius | 16 | 16 | 10 | 10 | 14 | 3 |

Added later (owner request, 2026-10-09): **Futuristic light** bg #EEF3FB, surface white .6 + glass,
surface2 rgba(60,80,140,.10), ink #0B1530, muted #56628A, accent #0B8F7A, accent2 #6A3FE0,
accent3 #D43C86, line rgba(60,100,200,.22), blobs #7FE8D6 #B9A2FF #FFA3CE.
**Vintage dark** bg #221A12, surface #2E2318, surface2 #3A2C1F, ink #EFE3C8, muted #A8957A,
accent #D9735E, accent2 #8BAF97, accent3 #D9AA4E, line #4E3E2B, blobs #5A4325 #6B4630 #4D3F28.

Fonts (all ship with macOS — no files to bundle):

| Theme | Headings | Body | Numbers/time |
|---|---|---|---|
| Grove | `.system(.title, design: .serif)` (New York), semibold | `.system(design: .rounded)` | rounded, `.monospacedDigit()` |
| Minimal | `.system(design: .default)` semibold, tight | `.system(design: .default)` | `.monospacedDigit()` |
| Futuristic | `.system(design: .default).width(.expanded)`, UPPERCASE, tracking 1.5, accent glow (`.shadow(color: accent.opacity(0.5), radius: 8)`) | `.system(design: .default)` | `.system(design: .monospaced)` |
| Vintage | `Font.custom("Baskerville", …)` italic for titles | `Font.custom("American Typewriter", …)` | American Typewriter |

### 6.2 Theme personality (beyond colours)

- **Grove** — soft shadows (`0 10 30 rgba(60,72,40,.10)`), rounded checkboxes, the
  growing plant in the sidebar/header, leaves in the check-burst, warm "Good morning".
- **Minimal** — no shadows, hairline borders, monochrome; accent appears only on today
  and selection; ambient blobs at 35% and very slow; check-burst = simple fade.
- **Futuristic** — panels use `.glassEffect(.regular.tint(surface), in: .rect(cornerRadius: 14))`;
  faint 32pt grid lines on the background; neon glow on the now line and checkboxes
  (square checkboxes); check-burst = expanding ring + sparks; aurora blobs.
- **Vintage** — paper: background gets a subtle noise texture drawn once into an `Image`
  via `Canvas` (random 1-px dots, 4% opacity) and a vignette (radial gradient to
  rgba(90,60,20,.35) at edges, multiply); ruled lines in note editor (28pt); square
  checkboxes; chips with dashed borders; check-burst = ink stamp "DONE" rotating in.

### 6.3 "Alive" motion (all disabled when Motion = off or Reduce Motion is on)

- **AmbientBackground**: `TimelineView(.animation(minimumInterval: 1/30))` + `Canvas`.
  Three large circles (46% of the window) in the theme's blob colours, positions moving on
  slow Lissajous paths (periods 22 s, 28 s, 34 s), drawn with `.blur(radius: 60)` and
  opacity 0.55 (Minimal/Futuristic 0.35). Pause when the window is not key
  (`controlActiveState`) to save energy.
- **GrowingPlant**: a `Shape` stem with leaves; number of visible leaves = completed /
  total of today (0…6 leaves), stem height animates with a spring; the plant sways ±3°
  over 5 s. Shown in Layout A sidebar bottom, Layout B header, Layout D page corner.
- **CheckBurst**: on completion, 6 small leaf/dot particles fly out 18pt and fade (0.5 s);
  the checkbox fills with a spring (`response 0.3, damping 0.6`).
- **Now line** gently pulses (opacity 1 → 0.45, 3.2 s).
- Lists insert/remove with `.transition(.move(edge: .top).combined(with: .opacity))`.
- Greeting changes by time of day ("Good morning / afternoon / evening").

---

## 7. App state and undo

`@Observable @MainActor final class AppStore`:

- Owns `Database` and repos.
- Published state: `selectedDay: DayKey`, `screen: Screen` (.planner, .tasks, .calendar,
  .notes, .today), `plannerDayCount`, `selection: Set<String>`, `theme`, `layout`, settings.
- Query helpers that read straight from SQLite (data is small; no big caches):
  `blocks(for days: ClosedRange<DayKey>)` (expands recurrence), `tasks(for day:)`,
  `tasks(forWeek:)`, `unscheduled(for day:)`, `note(daily:)`, `backlinks(type,id)`, `search(q)`.
- After each write, bump `@Published`-equivalent `revision: Int` so views recompute.
- **Undo**: every mutating method takes the window's `UndoManager` (from
  `@Environment(\.undoManager)`) and registers the inverse operation
  (`undoManager.registerUndo(withTarget: self) { … }` + `setActionName("Move Block")`).
  Group multi-block moves with `beginUndoGrouping`/`endUndoGrouping`.

---

## 8. Layouts

All layouts share the same component views. `RootView` switches on `store.layout`.
Every layout must give access to: Planner, Tasks (day + week), Calendar (month), Notes,
Command palette, Settings. Use the matching mock in `design/layouts.html` as the visual spec.

- **A · Garden** — `NavigationSplitView`: sidebar (search pill ⌘K, Today, Planner, This
  Week, Calendar, Notes, Inbox, Lists, Tags, growing plant at bottom) · content · inspector
  (`.inspector(isPresented:)`) for the selected task/event/note.
- **B · Day Spread** (recommended) — header: big date, greeting + "% of today grown", week
  strip, search pill. Three columns: **Tasks** on the left, 300–420pt resizable
  (today's tasks only, progress bar, quick add; since 2026-10-09 the left slot can instead
  show the Notes, Tasks or Goals panel) · **Planner (day
  mode)** in the centre, taking the rest of the width · **Today's
  note** (editor + Linked here + mood + focus). A toolbar segmented control switches the
  whole window to Planner (full width, week) · Calendar (month) · Notes (full).
- **C · Week Board** — header "Week 40" with ‹ ›. Grid: Inbox column + 7 day columns,
  each with event pills then tasks (drag between). Bottom drawer (collapsible, 150pt):
  weekly note · weekly goals · pinned notes. Toolbar toggle "Board / Planner" switches
  the 7 columns to the planner week mode (same days).
- **D · Journal** — book spread centred with page shadows (inner shadow on the spine).
  Left page: date, agenda (mini planner, compact), to-dos. Right page: lined daily note.
  Ribbon bookmarks on the right edge: Today, Planner, Week, Month, Notes. Page-turn
  transition (3D rotation around the spine, 0.45 s) when changing day; disabled when motion off.

---

## 9. Empty states and first launch

- First launch: create lists "Home 🌿", "Work 💼", "Personal ✨"; today's daily note; a
  welcome card in the task list with 3 sample tasks explaining drag-to-plan, `[[links]]`
  and ⌘K (user can dismiss; "Remove samples" button).
- Empty planner: faint text in the middle "Drag a task here, or drag on the grid to plan time."
- Empty notes: "Your thoughts grow here. ⌥⌘N for a new note."

---

## 10. Accessibility and quality bar

- All buttons have labels (`.accessibilityLabel`). Blocks expose "Title, 11:15 to 12:45".
- Contrast: ink on surface ≥ 4.5:1 in every theme (tokens above satisfy this).
- Dragging must never stutter: no database calls in `onChanged`.
- No force-unwraps on database results. Errors show a small toast; never crash.
- App launches in < 1 s with 1 000 tasks (add a test that inserts 1 000 tasks and times
  `tasks(for:)` < 50 ms).

---

## 11. Building, packaging, desktop icon

### 11.1 `scripts/make_icon.swift`

Draw a 1024×1024 icon with `NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024,
pixelsHigh: 1024, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)` and
`NSGraphicsContext(bitmapImageRep:)` (do NOT use `NSImage.tiffRepresentation` — it gives
the wrong pixel size on Retina). Design:
- macOS squircle: rounded rect inset 100px, corner radius 185px, soft drop shadow.
- Fill: vertical gradient #F6F1E6 → #E9E0CB.
- A sprout: stem #5E7F4F 26px wide curving up from the bottom centre; two leaves
  (#7FA36B and #A9C79A); the right leaf's outline forms a ✓ check mark.
- A small warm sun dot #D9B44A top-right at 30% opacity.
Write `build/AppIcon-1024.png`. Run with `swift scripts/make_icon.swift <outdir>`.

### 11.2 `scripts/build_app.sh`

```bash
#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
APP_NAME="Grove"; BUNDLE_ID="local.grove.app"; VERSION="1.0.0"
BUILD=build; APP="dist/$APP_NAME.app"
mkdir -p "$BUILD" dist
swift build -c release --product Grove
BIN="$(swift build -c release --show-bin-path)/Grove"

# Icon
swift scripts/make_icon.swift "$BUILD"
ICONSET="$BUILD/AppIcon.iconset"; rm -rf "$ICONSET"; mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s "$BUILD/AppIcon-1024.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  d=$((s*2)); sips -z $d $d "$BUILD/AppIcon-1024.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$BUILD/AppIcon.icns"

# Bundle
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
cp "$BUILD/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>CFBundleURLTypes</key><array><dict>
    <key>CFBundleURLName</key><string>$BUNDLE_ID</string>
    <key>CFBundleURLSchemes</key><array><string>grove</string></array>
  </dict></array>
</dict></plist>
PLIST
codesign --force --deep --sign - "$APP"
echo "Built $APP"
```

### 11.3 `scripts/install.sh`

```bash
#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build_app.sh
osascript -e 'tell application "Grove" to quit' 2>/dev/null || true
mkdir -p "$HOME/Applications"
rm -rf "$HOME/Applications/Grove.app"
cp -R dist/Grove.app "$HOME/Applications/Grove.app"
# Desktop icon: a symlink shows the app icon and opens the app on double-click.
ln -sfn "$HOME/Applications/Grove.app" "$HOME/Desktop/Grove"
touch "$HOME/Applications/Grove.app"     # refresh Finder icon cache
open "$HOME/Applications/Grove.app"
echo "Installed. Double-click 'Grove' on the Desktop."
```

The app must also handle `grove://` URLs (`.onOpenURL`) for note links.

### 11.4 Rebuild after changes

Run `./scripts/install.sh` again. Data is untouched (it lives in Application Support).

---

## 12. Tests — `scripts/test.sh`

```bash
#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
F=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
L=/Library/Developer/CommandLineTools/Library/Developer/usr/lib
swift test -Xswiftc -F -Xswiftc $F -Xlinker -F -Xlinker $F \
  -Xlinker -rpath -Xlinker $F -Xlinker -rpath -Xlinker $L "$@"
```

(These flags were verified on this Mac. Without them `import Testing` fails.)

Test files use `import Testing`, `@Test`, `#expect`. Required suites:

- **PlannerMathTests** — every case in §5.1.5.
- **QuickAddParserTests** — at least 25 phrases. Use a fixed "today" (inject a clock:
  `QuickAddParser(today: DayKey("2026-10-02"))`, a Friday). Examples:
  `"Call mum tomorrow 6pm for 20m #home !2"` → title "Call mum", day 2026-10-03, block
  18:00–18:20, tag home, priority 2. `"Read ch 5 next week"` → bucket week, plan_week
  2026-10-05. `"Gym every mon 7am"` → weekly Monday, block 07:00–07:30.
  `"Pay rent due 5 oct"` → due 2026-10-05, bucket inbox.
- **NoteParserTests** — finds `[[links]]` (including duplicates, nested brackets
  ignored), checkboxes with/without markers, `@date time` tokens, `#tags`.
- **RecurrenceTests** — §5.3 cases, plus exdates and detached occurrences.
- **DatabaseTests** — migrations on an in-memory DB, CRUD for each repo, cascade deletes
  (deleting a task deletes its blocks), FTS search finds a note by a body word,
  1 000-task performance check.
- **LinkIndexerTests** — saving a note rebuilds parsed links; backlinks query works.

UI is verified by running the app (see §13 verify steps).

---

## 13. Build order (milestones). Commit after each one.

Git setup first: `git init`, then `git checkout -b feat/grove-v1` (never commit on main).
Stage exact paths. No AI attribution in commit messages.

| # | Milestone | Verify (must pass before moving on) |
|---|---|---|
| M0 | Package.swift, folder structure, `.gitignore`, empty SwiftUI window with hidden title bar, the three scripts, icon script. | `./scripts/install.sh` → app opens, custom icon visible on Desktop and Dock. |
| M1 | GroveCore: DayKey/WallTime, models, Database, migrations, repositories, FTS, backup. | `./scripts/test.sh` — DatabaseTests green. |
| M2 | **PlannerMath** + tests. Then **Planner UI** (day mode): grid, now line, blocks, layout columns, create-by-drag, double-click, move, resize both edges, snap, ⌥, live label, undo, keyboard, context menu, auto-scroll. Then 3-day/week mode with cross-day drag, ripple (⇧), Unscheduled tray, Fit, Plan my day. | Tests green. Manual: do every planner line of §1.1 in the running app. |
| M3 | Tasks: list views, row, inspector, buckets, week columns, QuickAddParser (+tests), repeats, subtasks, reorder, drag task → planner. Split: **M3a** QuickAddParser · **M3b** `[[mention]]` parser/indexer/rename, `attachments` table · **M3c** task lists, quick add, buckets, week columns, drag to planner · **M3d** inspector with `RichTextEditor` (bullets, formatting, images, mentions). | Tests green. Manual: quick-add examples from §12 produce the right task + block. Manual: mention a task in another task's body, see it in "Linked here". |
| M4 | Calendar: month view, week strip, event editor, recurrence engine (+tests), recurring edit dialog. | Tests green. Manual: weekly event shows every week; "only this" move works. |
| M5 | Notes: notes home, NSTextView editor + styler, daily/weekly notes, `[[` autocomplete, backlinks, NoteParser + LinkIndexer (+tests). | Tests green. Manual: link two notes, backlink appears. |
| M6 | Interconnections §5.5 items 1–12. | Manual: run through all 12. |
| M7 | Themes (4, + dark variants), AmbientBackground, GrowingPlant, CheckBurst, motion toggle, Reduce Motion. | Manual: switch every theme on every screen; toggle motion; nothing unreadable. |
| M8 | Layout(s) from `LAYOUTS_TO_BUILD`, command palette, menu bar extra, notifications, settings, export/import, first-launch content, roll-over card, focus timer. | Manual: full §1.1 checklist. |
| M9 | Polish: empty states, accessibility labels, perf test, final `./scripts/install.sh`. | All of §1.1 ticked with what you ran. |

If a milestone is too big for one commit, split it, but keep the order.

---

## 14. Pitfalls to avoid (read before coding)

1. **Do not** `import SwiftData` or use `@Model` — the macro plugin is missing; build fails.
2. **Do not** add SPM `resources:` — `Bundle.module` will not be found inside the `.app`.
3. **Do not** call `xcodebuild` — there is no Xcode.
4. `swift test` without the flags in `scripts/test.sh` fails with "no such module 'Testing'".
5. `UNUserNotificationCenter` only works when run as the bundled `.app` (via
   `install.sh`), not via `swift run`. Guard: if `Bundle.main.bundleIdentifier == nil`,
   skip notifications.
6. Running via `swift run` shows no Dock icon/menus properly; always test UI via the `.app`.
   For a quick dev loop: `./scripts/build_app.sh && open dist/Grove.app`.
7. In the planner, never write to SQLite during `onChanged`; only in `onEnded`.
8. Gesture conflicts: resize handles must sit above the body and use
   `highPriorityGesture`; the grid's create-drag must ignore presses that start on a block
   (check hit with the layout frames).
9. `ScrollView` steals vertical drags: put block gestures with `minimumDistance: 2` and
   disable scrolling while `live != nil` (`.scrollDisabled(live != nil)`).
10. `NSTextView` in SwiftUI: keep the `NSTextView` in the Coordinator; update its string
    only when the note id changes (not on every SwiftUI update) or the caret jumps.
11. Use `en_US_POSIX` formatters for stored strings; user-visible dates use the user's locale.
12. Minutes since midnight everywhere in planner code; convert to `WallTime` only at the
    repository edge.
13. Swift Testing: `@Test` functions inside a `struct` suite; use `#expect(a == b)`.

---

## 15. Out of scope for v1 (do not build)

iCloud sync, iPhone app, Apple Calendar / Google Calendar import (possible v2 via
EventKit — needs the owner's OK first), collaboration, file attachments other than
images (images in task bodies and notes ARE in scope since 2026-10-02), global
system-wide hotkey, App Store distribution / notarisation.
