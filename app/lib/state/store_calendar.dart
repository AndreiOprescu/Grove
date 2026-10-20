part of 'app_store.dart';

/// The event the editor shows. [anchor] says which view the editor hangs on.
class EditingEvent {
  const EditingEvent({
    required this.item,
    required this.isNew,
    required this.anchor,
  });

  final EventItem item;
  final bool isNew;
  final String anchor;

  @override
  bool operator ==(Object other) =>
      other is EditingEvent &&
      other.item == item &&
      other.isNew == isNew &&
      other.anchor == anchor;

  @override
  int get hashCode => Object.hash(item, isNew, anchor);
}

/// The month view, the week strip and the event editor (PLAN §5.2).
extension AppStoreCalendar on AppStore {
  // Reading

  /// One entry for every day in the range.
  Map<DayKey, DayInfo> dayInfo(DayRange days) {
    final events = <DayKey, List<EventItem>>{
      for (final day in days.days) day: [],
    };
    for (final e in eventItems(days)) {
      if (e.kind != EventKind.event) continue;
      final from = e.start.day > days.first ? e.start.day : days.first;
      final to = e.end.day < days.last ? e.end.day : days.last;
      for (var day = from; day <= to; day = day.adding(days: 1)) {
        if (CalendarRules.covers(e, day)) events[day]?.add(e);
      }
    }
    final open =
        _try(() => repos.tasks.openCounts(from: days.first, to: days.last)) ??
        const <DayKey, int>{};
    final noted =
        _try(
          () => repos.notes.daysWithNotes(from: days.first, to: days.last),
        ) ??
        const <DayKey>{};
    final moods =
        _try(() => repos.notes.moods(from: days.first, to: days.last)) ??
        const <DayKey, int>{};
    return {
      for (final entry in events.entries)
        entry.key: DayInfo(
          events: CalendarRules.sorted(entry.value),
          openTasks: open[entry.key] ?? 0,
          hasNote: noted.contains(entry.key),
          mood: moods[entry.key],
        ),
    };
  }

  // The editor

  /// A new all-day event on [day]. Nothing is stored until the user saves.
  void newEvent({required DayKey on}) {
    final at = WallTime(day: on, minute: 0);
    editingEvent = EditingEvent(
      item: EventItem(title: '', start: at, end: at, allDay: true),
      isNew: true,
      anchor: 'new:${on.string}',
    );
  }

  /// Opens the editor. A multi-day event shows in several month cells, so a
  /// cell passes its own [anchor].
  void editEvent(EventItem event, {String? anchor}) {
    editingEvent = EditingEvent(
      item: draft(event),
      isNew: false,
      anchor: anchor ?? event.id,
    );
  }

  void closeEditor() => editingEvent = null;

  // Writing

  /// Saves the editor's copy. [from] is the event before the edit, or null for
  /// a new event. A day of a repeating event asks "This event only / All
  /// events" first.
  void saveEvent(EventItem edited, {required EventItem? from}) {
    final original = from;
    var item = EventDraft.normalize(edited);
    item = item.copyWith(title: item.title.trim());
    if (original == null) {
      if (item.title.isEmpty) item = item.copyWith(title: 'New Event');
      final m = Mutation('New Event')..events.add((before: null, after: item));
      if (commit(m)) selection = {item.id};
      closeEditor();
      return;
    }
    if (item.title.isEmpty) item = item.copyWith(title: original.title);
    // Cancel in the question opens the editor again with these edits.
    final open = _editingEvent;
    final editor = open == null
        ? null
        : EditingEvent(item: item, isNew: open.isNew, anchor: open.anchor);
    if (OccurrenceId.parse(original.id) != null) {
      final same = item == draft(original);
      closeEditor();
      if (same) return;
      changeOccurrences(
        [(old: original, changed: item)],
        verb: 'Change',
        name: 'Edit Event',
        onCancel: () => editingEvent = editor,
      );
      return;
    }
    final done = change(
      original,
      to: item,
      scope: RecurringScope.only,
      name: 'Edit Event',
    );
    if (done != null) commit(done.mutation);
    closeEditor();
  }

  void deleteEvent(EventItem event) {
    closeEditor();
    if (OccurrenceId.parse(event.id) == null) {
      commit(deletion(event, scope: RecurringScope.only, name: 'Delete Event'));
      return;
    }
    askScope(
      'Delete',
      (scope) => commit(deletion(event, scope: scope, name: 'Delete Event')),
    );
  }

  // Dropping a task

  /// A task dropped on a day (the sticky strip, the week strip or the month
  /// view): planned for that day with no time. Its old time blocks are
  /// removed, so it is in one place only.
  void dropTask(String id, {required DayKey on}) {
    moveTask(id, to: TaskPlacement.day(on), keepingBlocks: false);
    showToast('Planned for ${NotesRules.shortDay(on)}');
  }
}
