# Cross-platform port — two parallel tracks

The milestones F5–F12 in `docs/cross-platform-plan.md` are split into two
tracks. Two agents work at the same time, one per track. Each agent reads this
file, the plan, and `docs/assumptions.md` before it starts.

## The two tracks

| | Track A — engine | Track B — screens |
|---|---|---|
| Branch | `feat/xp-engine` | `feat/xp-screens` |
| Folder | `/Users/andrei/Desktop/Grove` (main checkout) | `.claude/worktrees/screens` (git worktree, made by `claude --worktree screens`) |
| Milestones, in order | F5 → F11-core → F10-services → F8 | F6 → F7 → F9 → F10-screens |
| Owns (only this track edits) | `app/lib/state/`, `app/lib/sync/`, `app/lib/services/`, `app/lib/data/`, `app/lib/ui/tasks/`, `app/lib/ui/goals/`, `supabase/`, matching folders under `app/test/` | everything else in `app/lib/ui/`, `app/integration_test/`, goldens, matching folders under `app/test/` |

### What each milestone means here

- **F5 App state + undo** (A): as in the plan. The `AppStore` API is the
  contract for Track B. Push it as soon as it is green.
- **F6 Theme system + app shell** (B): as in the plan. It needs no store. Use
  fake data until F5 is pushed.
- **F7 Day Planner** (B): as in the plan. Merge `origin/feat/xp-engine` first,
  to get the F5 store. Also show subtasks in blocks with a "+N more" row (Swift
  PR #3) and subtasks on goal blocks (Swift PR #4).
- **F11-core Sync engine** (A): outbox, push/pull, last-write-wins, soft
  deletes, tested against a fake remote in pure Dart. The Supabase schema, Row
  Level Security, magic-link login and image upload come when the user gives
  the Supabase URL and anon key (git-ignored file, never committed). The login
  screen is built by Track A in `app/lib/ui/auth/` with Track B's theme.
- **F10-services** (A): reminders on all 4 OS (`flutter_local_notifications`),
  system tray on Mac and Windows (`tray_manager`), backup schedule. No screens.
- **F8 Tasks + Goals** (A): as in the plan. Starts after F6 is pushed. Merge
  `origin/feat/xp-screens` first, to get the theme and shell.
- **F9 Calendar + Notes** (B): as in the plan.
- **F10-screens** (B): Garden + growing plant, settings screen.
- **F12 Parity + release builds**: after both tracks are done. Whoever is free
  first starts it.
- **Swift migration 7** (A): when Swift PR #4 merges, add migration 7
  `block_subtasks` to the Flutter data layer. See `docs/assumptions.md`.

## Rules for working side by side

- Each track works only on its own branch and in its own folder. Never check out
  the other track's branch in your folder.
- To get the other track's work: `git fetch origin` then
  `git merge origin/<other branch>`. Never rebase. Never force-push.
- Edit only the folders your track owns. If you need a change in the other
  track's folder, do not make it. Write it under "Requests" in your track's
  section below, and work around it (for example, a small widget in your own
  folder).
- Shared files. Change them only when you must, in small edits:
  `app/pubspec.yaml`, `app/pubspec.lock`, `app/lib/main.dart`,
  `app/lib/ui/app.dart`, `scripts/`, `.github/workflows/`,
  `docs/cross-platform-plan.md`.
  - New packages: only the ones in the plan's "New dependencies" list. Ask the
    user about any other.
  - If `app/pubspec.lock` conflicts in a merge, keep either side, then run
    `cd app && flutter pub get` and commit the new lock file.
- `docs/assumptions.md`: Track A adds lines at the end of the
  "Cross-platform Track A" section. Track B adds lines at the end of the file
  (the "Cross-platform Track B" section). This keeps merges clean.
- Every milestone still needs: `./scripts/flutter_test.sh` green, CI green on
  all 4 OS, and a proof file `docs/acceptance/F<n>.md` (for a split milestone:
  `F10-services.md`, `F10-screens.md`, `F11-core.md`).
- Stop and report to the user after each milestone.
- Each track has one draft PR into `feat/cross-platform-flutter`. Keep it
  updated. The user merges.

## Status

### Track A — engine

- F5: done, waits for the user (proof: `docs/acceptance/F5.md`)
- F11-core: done, waits for the user (proof: `docs/acceptance/F11-core.md`)
- F10-services: done, waits for the user (proof:
  `docs/acceptance/F10-services.md`)
- Sync for Track B (nothing to do now):
  - The engine is `SyncEngine(repos: ..., remote: ...)` in
    `package:grove/sync/sync.dart`. `await engine.sync()` pushes and pulls.
  - The store does not call it yet. No screen needs a change. The login
    screen and the wiring come with the login step of F11 (needs the owner's
    Supabase keys and the answer to Q-4 in `docs/questions.md`).
  - A pull writes the database with SQL. When the store is wired, it will
    call `notifyListeners()` after a pull, so the screens build again.
- Either track may add new files under `app/lib/core/` (pure Dart, ports of
  Swift `GroveCore`). Track A added `app/lib/core/services/`.
- Answers to Track B's requests:
  - The store is `AppStore` (`import 'package:grove/state/state.dart';`). It is
    a `ChangeNotifier`. It has every member of `ShellModel` with the same
    name: `screen`, `leftPane`, `themeId`, `appearance`, `motionSetting`,
    `intensity`, `toast`, `showToday`, `showTasks`, `toggleLeftPane`,
    `showLeftPane`, `setTheme`, `nextTheme`, `setAppearance`, `setMotion`,
    `showToast`. `intensity` is 0 to 1.5, as in the Mac app.
  - It saves the theme, light/dark, motion, intensity and the open left panel
    in `Prefs` (`FilePrefs(path)` for the real app, `MemoryPrefs()` for tests).
  - Make it with `AppStore(repos: Repos(Database.open(path)), prefs: ...)`.
- Requests to Track B:
  - Start the services where you open the real store (you planned this for the
    start of F7). In `app/lib/main.dart`, after
    `WidgetsFlutterBinding.ensureInitialized()`:

    ```dart
    import 'package:grove/services/services.dart';

    final prefs = FilePrefs('$dir${Platform.pathSeparator}prefs.json');
    final notifier = AppServices.notifier(prefs);
    final store = AppStore.open(dataDir: dir, notifier: notifier, prefs: prefs);
    AppServices.forThisDevice(store).start();
    ```

    That gives reminders on the 4 systems, the tray icon on the Mac and on
    Windows, and the daily backup. `AppStore.open` makes `Backups/` and
    `prefs.json` in `dir`. `app/tool/services_check.dart` is a working example.
  - The permission question: call `store.askForNotifications()` from your
    welcome card and from the Settings screen, as the Mac app does. Nothing
    asks today. `store.notifyStatus` has the three states.
  - The state layer cannot import `app/lib/ui/`. So keep one set of enums, the
    one in `app/lib/state/`: `Screen` (`screen.dart`), `LeftPane`
    (`rules/left_pane.dart`), `ThemeId` and `AppearanceMode` (`theme_id.dart`).
    They have the same values and members as yours. In
    `app/lib/ui/shell/shell_model.dart` and `app/lib/ui/theme/theme_spec.dart`:
    delete your four enums and `export` the state ones. Keep
    `AppearanceMode.brightness` as an `extension` in your theme file.
  - Then write the adapter in `app/lib/ui/shell/`: a class that `implements
    ShellModel` and passes every call to an `AppStore`. (Most store methods
    are Dart extension methods, so `AppStore implements ShellModel` is not
    possible.)
  - `LeftPane.icon` and the palette rows give SF Symbol names as text (for
    example `checklist`, `note.text`). Map them to your icons.
  - Port the Swift tests of view code with your screens. The list is in
    `docs/acceptance/F5.md` ("Left for Track B").

### Track B — screens

- F6: done and merged (proof: `docs/acceptance/F6.md`)
- F7: done, waits for the user (proof: `docs/acceptance/F7.md`)
- F9: not started
- Answers to Track A's requests (all done on 2026-10-10):
  - One set of enums. My four are deleted. `shell_model.dart` and
    `theme_spec.dart` `export` the state ones. `AppearanceMode.brightness` is
    the extension `AppearanceBrightness` in `theme_spec.dart`.
  - The adapter is `StoreShellModel(store)` in
    `app/lib/ui/shell/store_shell_model.dart`. Use it as
    `GroveApp(model: StoreShellModel(store))`. It keeps nothing; the one who
    made the store closes it.
  - SF Symbol names: `symbolIcon(name)` in `app/lib/ui/theme/symbols.dart`
    gives the icon. It has every name of `LeftPane.icon`, `Mood.symbol`,
    `PaletteRules.commands` and the palette rows. A new name shows a "?" icon
    until it is added there; `symbols_test.dart` fails for a name it finds in
    those lists.
  - The Swift view tests: the theme ones are ported (`ThemeSpecTests`, the 5
    `ThemeMotionTests` singles, the `AmbientMath` one; see
    `docs/acceptance/F6.md`). The planner ones are ported with F7
    (`PlannerKindTests`, `PlannerRulesTests`, `PlannerLayoutRules`,
    `InlineTitleRulesTests`, the Workload tests; see `docs/acceptance/F7.md`).
    The others come with their screens: F9 (Spread), F10-screens (editor,
    task rows, check box).
  - The services start in `app/lib/main.dart` with your 4 lines (F7). The
    store opens in `getApplicationSupportDirectory()` (`path_provider`).
  - `store.askForNotifications()`: not called yet. It comes with the welcome
    card and the Settings screen (F10-screens).
- For Track A to know (F7):
  - `StoreApp(store: store)` in `app/lib/ui/store_app.dart` is the app on a
    real store. It puts the screens in with `screenBuilder`. When your panels
    are ready (F8), tell me the widget and I add it to `paneBuilder` there, or
    add it yourself in a small edit.
  - Drags: wrap a row that can be dragged in `PayloadDrag(payload: ..., label:
    ..., child: ...)` from `app/lib/ui/planner/payload_drag.dart`. The payload
    is the text of `DragPayload`. The planner grid and the strip of tasks with
    no time take `DragTarget<String>` drops of that text. Use the same in the
    Tasks panel, so a task can be dragged onto the planner.
  - `CheckBox` (`app/lib/ui/theme/check_box.dart`) and the colours of tasks
    and priorities (`TaskPalette`, `PriorityColors`, `theme.color(name)` in
    `app/lib/ui/theme/named_colors.dart`) are there for your task rows.
  - The device test: `./scripts/flutter_integration.sh <target>`. The CI runs
    it in each job after the build. It adds some minutes to each job.
- Fonts (owner's answer to Q-1 and Q-2): 7 font families are in `app/fonts/`
  and in `app/pubspec.yaml`. Use `GroveTheme.of(context).heading()`, `.body()`
  and `.number()`; do not name a font family in a screen.
- Requests to Track A:
  - F8: give the Tasks and Goals panels to the shell with
    `GroveApp(paneBuilder: ...)`. Use `GroveTheme.of(context)`, `Panel`,
    `ThemedHeading`, `ThemedChip` from `app/lib/ui/theme/`.
  - Subtasks in blocks (Swift PR #3): put the subtasks in `PlannerBlock`
    (a `subtasks` list from `blocks()`), and port `SubtaskRules.moreLabel` and
    `SubtaskRules.badge` to `app/lib/state/rules/`. Today the grid calls
    `store.subtasks(taskId)` for each task block, and the labels are in
    `app/lib/ui/planner/planner_geometry.dart`. I change over when yours are
    there.
  - Subtasks on goal blocks (Swift PR #4): when that PR is merged, port its
    table (`block_subtasks`) and its store calls. The grid cannot show them
    before that.
  - The clock: `nowMinute()`, `showToday()`, `showDay()` and the
    `DayKey.today()` calls in `app/lib/state/` do not use `clockOverride`.
    Please make them use it. Then a screen test can fix the day for the whole
    store. Today the planner has its own small helper
    (`app/lib/ui/planner/planner_clock.dart`); I delete it after.
  - The event editor: `store.editEvent(e)` sets `editingEvent`, and no screen
    shows it. Who builds the editor window? If it is yours (it sits with
    tasks and goals), put it in `app/lib/ui/tasks/` or a new folder and tell
    me the widget. If you want me to build it, say so here.
