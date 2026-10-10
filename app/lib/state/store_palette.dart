part of 'app_store.dart';

/// What a palette row does.
sealed class PaletteAction {
  const PaletteAction();
}

class PaletteRun extends PaletteAction {
  const PaletteRun(this.command);
  final PaletteCommandId command;

  @override
  bool operator ==(Object other) =>
      other is PaletteRun && other.command == command;

  @override
  int get hashCode => command.hashCode;
}

class PaletteGoTo extends PaletteAction {
  const PaletteGoTo(this.day);
  final DayKey day;

  @override
  bool operator ==(Object other) => other is PaletteGoTo && other.day == day;

  @override
  int get hashCode => day.hashCode;
}

class PaletteOpen extends PaletteAction {
  const PaletteOpen(this.ref);
  final ItemRef ref;

  @override
  bool operator ==(Object other) => other is PaletteOpen && other.ref == ref;

  @override
  int get hashCode => ref.hashCode;
}

/// One row of the palette.
class PaletteItem {
  const PaletteItem({
    required this.action,
    required this.title,
    this.detail = '',
    required this.symbol,
    this.shortcut,
    this.done = false,
  });

  final PaletteAction action;
  final String title;
  final String detail;

  /// The name of the picture (an SF Symbol name on the Mac).
  final String symbol;
  final String? shortcut;
  final bool done;

  String get id => switch (action) {
    PaletteRun(:final command) => 'command-${command.name}',
    PaletteGoTo(:final day) => 'day-${day.string}',
    PaletteOpen(:final ref) => '${ref.type.name}-${ref.id}',
  };

  @override
  bool operator ==(Object other) =>
      other is PaletteItem &&
      other.action == action &&
      other.title == title &&
      other.detail == detail &&
      other.symbol == symbol &&
      other.shortcut == shortcut &&
      other.done == done;

  @override
  int get hashCode =>
      Object.hash(action, title, detail, symbol, shortcut, done);

  @override
  String toString() => 'PaletteItem($id, $title)';
}

extension AppStorePalette on AppStore {
  // Opening and closing

  void togglePalette() {
    if (_paletteOpen) {
      paletteOpen = false;
    } else {
      _paletteText = '';
      paletteOpen = true;
    }
  }

  // Rows

  /// The rows for the text in the box: a day, then the commands that match,
  /// then items found by search.
  List<PaletteItem> paletteItems(String raw, {DayKey? today}) {
    final now = today ?? DayKey.today();
    final query = PaletteRules.parse(raw);
    final rows = <PaletteItem>[];
    final day = query.commandsOnly
        ? null
        : PaletteRules.date(query.text, today: now);
    if (day != null) {
      rows.add(
        PaletteItem(
          action: PaletteGoTo(day),
          title: PaletteRules.dayTitle(day, today: now),
          detail: PaletteRules.dayDetail(day),
          symbol: 'calendar',
        ),
      );
    }
    for (final c in PaletteRules.commandsMatching(query.text)) {
      if (day == now && c.id == PaletteCommandId.goToday) continue;
      rows.add(
        PaletteItem(
          action: PaletteRun(c.id),
          title: c.title,
          symbol: c.symbol,
          shortcut: c.shortcut,
        ),
      );
    }
    if (!query.commandsOnly && query.text.isNotEmpty) {
      final hits =
          _try(
            () => repos.search.search(
              query.text,
              limit: AppStore.paletteItemLimit * 3,
            ),
          ) ??
          const <SearchHit>[];
      rows.addAll(
        hits
            .map(_paletteItem)
            .whereType<PaletteItem>()
            .take(AppStore.paletteItemLimit),
      );
    }
    return rows;
  }

  /// Reads the item behind a hit. Null when it is gone, or when it is a task
  /// block (its task is listed instead).
  PaletteItem? _paletteItem(SearchHit hit) {
    final ref = hit.ref;
    switch (ref.type) {
      case ItemType.task:
        final t = task(ref.id);
        if (t == null) return null;
        final done = t.status == TaskStatus.done;
        var detail = 'Task';
        if (done) detail += ' · done';
        final day = t.planDate;
        if (day != null) detail += ' · ${PaletteRules.dayDetail(day)}';
        return PaletteItem(
          action: PaletteOpen(ref),
          title: t.title,
          detail: detail,
          symbol: done ? 'checkmark.circle.fill' : 'circle',
          done: done,
        );
      case ItemType.event:
        final e = _try(() => repos.events.get(ref.id));
        if (e == null || e.kind != EventKind.event) return null;
        final when = e.allDay
            ? AtDatePlanner.whenLabel(e.start.day)
            : AtDatePlanner.whenLabel(
                e.start.day,
                start: e.start.minute,
                end: e.end.day == e.start.day ? e.end.minute : null,
              );
        return PaletteItem(
          action: PaletteOpen(ref),
          title: e.title.isEmpty ? 'Untitled' : e.title,
          detail: 'Event · $when',
          symbol: 'calendar',
        );
      case ItemType.note:
        final n = note(ref.id);
        if (n == null) return null;
        return PaletteItem(
          action: PaletteOpen(ref),
          title: n.title.isEmpty ? 'Untitled' : n.title,
          detail: switch (n.kind) {
            NoteKind.note => 'Note',
            NoteKind.daily => 'Daily note',
            NoteKind.weekly => 'Weekly note',
          },
          symbol: 'note.text',
        );
    }
  }

  // Running

  void runPalette(PaletteItem item) {
    switch (item.action) {
      case PaletteRun(:final command):
        run(command);
      case PaletteGoTo(:final day):
        paletteOpen = false;
        showDay(day);
      case PaletteOpen(:final ref):
        paletteOpen = false;
        open(ref);
    }
  }

  void run(PaletteCommandId id) {
    if (id == PaletteCommandId.goToDate) {
      // The palette stays open and waits for a day.
      _paletteText = 'go to ';
      paletteOpen = true;
      return;
    }
    paletteOpen = false;
    switch (id) {
      case PaletteCommandId.newTask:
        // Both screens have the task list.
        if (_screen != Screen.planner) screen = Screen.today;
        requestQuickAdd();
      case PaletteCommandId.newNote:
        newNote();
      case PaletteCommandId.todayNote:
        openDailyNote(DayKey.today());
      case PaletteCommandId.goToday:
        showDay(DayKey.today());
      case PaletteCommandId.goToDate:
        break;
      case PaletteCommandId.planMyDay:
        showDay(DayKey.today());
        planMyDayRequest += 1;
      case PaletteCommandId.showPlanner:
        screen = Screen.planner;
      case PaletteCommandId.showCalendar:
        screen = Screen.calendar;
      case PaletteCommandId.showNotes:
        screen = Screen.notes;
      case PaletteCommandId.showGarden:
        screen = Screen.garden;
      case PaletteCommandId.toggleTheme:
        nextTheme();
      case PaletteCommandId.toggleMotion:
        setMotion(!_motionSetting);
    }
  }
}
