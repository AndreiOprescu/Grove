part of 'app_store.dart';

/// What an edit of a repeating event applies to.
enum RecurringScope { only, all }

/// The question "This event only / All events", waiting for an answer. [verb]
/// is Move, Resize, Delete, Change or Rename.
class RecurringPrompt {
  RecurringPrompt({required this.verb, required this.run, this.onCancel});

  final String id = newId();
  final String verb;
  final void Function(RecurringScope scope) run;

  /// Runs when the user cancels. The event editor uses it to open again with
  /// the same edits.
  final void Function()? onCancel;
}

/// Events, and the days of repeating events.
extension AppStoreEvents on AppStore {
  // Reading

  /// Every event that touches the days: stored events, one-off copies and the
  /// days of repeating events.
  List<EventItem> eventItems(DayRange days) {
    final out = [...?_try(() => repos.events.inRange(days.first, days.last))];
    for (final series
        in _try(repos.events.recurringSeries) ?? const <EventItem>[]) {
      if (series.start.day > days.last) continue;
      final gone = {...?_try(() => repos.events.exdates(series.id))};
      out.addAll(
        RecurrenceEngine.expand(
          series,
          exdates: gone,
          from: days.first,
          to: days.last,
        ),
      );
    }
    return out..sort((a, b) {
      final start = a.start.compareTo(b.start);
      return start != 0 ? start : a.id.compareTo(b.id);
    });
  }

  /// A copy of an event to edit. A day of a repeating event carries the repeat
  /// rule of its series, so a change can say "keep repeating" (the rule stays)
  /// or "stop" (the rule is removed).
  EventItem draft(EventItem item) {
    final p = OccurrenceId.parse(item.id);
    final series = p == null ? null : event(p.series);
    return series == null ? item : item.copyWith(recurrence: series.recurrence);
  }

  // The question

  void askScope(
    String verb,
    void Function(RecurringScope scope) run, {
    void Function()? onCancel,
  }) {
    recurringPrompt = RecurringPrompt(verb: verb, run: run, onCancel: onCancel);
  }

  /// The answer to the open question. With [prompt], the answer still works
  /// when the question was already taken away.
  void answerRecurring(RecurringScope scope, {RecurringPrompt? prompt}) {
    final open = _recurringPrompt;
    if (prompt != null) {
      if (open?.id == prompt.id) recurringPrompt = null;
      prompt.run(scope);
      return;
    }
    if (open == null) return;
    recurringPrompt = null;
    open.run(scope);
  }

  void cancelRecurring() {
    final prompt = _recurringPrompt;
    recurringPrompt = null;
    prompt?.onCancel?.call();
  }

  /// Asks "This event only / All events", then commits the changes as one undo step.
  void changeOccurrences(
    List<OccurrenceEdit> pairs, {
    required String verb,
    required String name,
    void Function()? onCancel,
  }) {
    if (pairs.isEmpty) return;
    askScope(verb, onCancel: onCancel, (scope) {
      final all = Mutation(name);
      final ids = <String>{};
      final seenSeries = <String>{};
      for (final pair in pairs) {
        final p = OccurrenceId.parse(pair.old.id);
        if (scope == RecurringScope.all &&
            p != null &&
            !seenSeries.add(p.series)) {
          continue;
        }
        final done = change(
          pair.old,
          to: pair.changed,
          scope: scope,
          name: name,
        );
        if (done == null) continue;
        all.append(done.mutation);
        ids.add(done.id);
      }
      if (commit(all) && ids.isNotEmpty) selection = ids;
    });
  }

  // Building the changes

  /// The change that turns [original] into [to], and the id the result has
  /// afterwards. For a day of a repeating event, [scope] says: that day only
  /// (it becomes a one-off copy and the day is taken out of the series), or the
  /// whole series. A stored event changes in place.
  ({Mutation mutation, String id})? change(
    EventItem original, {
    required EventItem to,
    required RecurringScope scope,
    required String name,
  }) {
    final edited = to;
    final m = Mutation(name);
    final p = OccurrenceId.parse(original.id);
    if (p == null) {
      final old = event(original.id);
      if (old == null) return null;
      // A save stamps the time, so compare without the stamps.
      final changed = edited.copyWith(
        id: original.id,
        createdAt: old.createdAt,
        updatedAt: old.updatedAt,
      );
      if (changed == old) return null;
      m.events.add((before: old, after: changed));
      return (mutation: m, id: changed.id);
    }
    final series = event(p.series);
    if (series == null) return null;
    switch (scope) {
      case RecurringScope.only:
        final copy = edited.copyWith(
          id: newId(),
          recurrence: null,
          seriesId: series.id,
          originalDate: p.day,
        );
        m.exdates.add((eventId: series.id, day: p.day, add: true));
        m.events.add((before: null, after: copy));
        return (mutation: m, id: copy.id);
      case RecurringScope.all:
        final delta = original.start.day.daysUntil(edited.start.day);
        final start = WallTime(
          day: series.start.day.adding(days: delta),
          minute: edited.start.minute,
        );
        var rule = edited.recurrence;
        final days = rule?.weekdays;
        if (delta != 0 &&
            rule != null &&
            rule == series.recurrence &&
            rule.freq == Freq.weekly &&
            days != null &&
            days.isNotEmpty) {
          // Moving every Wednesday to Thursday moves every other chosen
          // weekday one day too.
          rule = rule.copyWith(
            weekdays: [for (final d in days) ((d - 1 + delta) % 7 + 7) % 7 + 1],
          );
        }
        final changed = series.copyWith(
          title: edited.title,
          allDay: edited.allDay,
          color: edited.color,
          location: edited.location,
          notes: edited.notes,
          start: start,
          end: WallTime(
            day: start.day.adding(
              days: edited.start.day.daysUntil(edited.end.day),
            ),
            minute: edited.end.minute,
          ),
          recurrence: rule,
        );
        if (changed == series) return null;
        // The series first: copies point at it.
        m.events.add((before: series, after: changed));
        if (delta != 0) {
          // Days taken out of the series, and the one-off copies that
          // replaced them, move along.
          final gone = _try(() => repos.events.exdates(series.id)) ?? const [];
          for (final d in gone) {
            m.exdates.add((eventId: series.id, day: d, add: false));
          }
          for (final d in gone) {
            m.exdates.add((
              eventId: series.id,
              day: d.adding(days: delta),
              add: true,
            ));
          }
          for (final copy
              in _try(() => repos.events.detached(series.id)) ??
                  const <EventItem>[]) {
            final moved = copy.copyWith(
              originalDate: copy.originalDate?.adding(days: delta),
            );
            if (moved != copy) m.events.add((before: copy, after: moved));
          }
        }
        final id = changed.recurrence == null
            ? changed.id
            : OccurrenceId.make(series: changed.id, day: edited.start.day);
        return (mutation: m, id: id);
    }
  }

  /// The change that removes a day of a repeating event (`only`), the whole
  /// series (`all`), or a stored event.
  Mutation deletion(
    EventItem original, {
    required RecurringScope scope,
    required String name,
  }) {
    final m = Mutation(name);
    final p = OccurrenceId.parse(original.id);
    if (p == null) {
      final old = event(original.id);
      if (old != null) m.events.add((before: old, after: null));
      return m;
    }
    final series = event(p.series);
    if (series == null) return m;
    switch (scope) {
      case RecurringScope.only:
        m.exdates.add((eventId: series.id, day: p.day, add: true));
      case RecurringScope.all:
        // The series first, as in `change`.
        m.events.add((before: series, after: null));
        for (final copy
            in _try(() => repos.events.detached(series.id)) ??
                const <EventItem>[]) {
          m.events.add((before: copy, after: null));
        }
        for (final d
            in _try(() => repos.events.exdates(series.id)) ??
                const <DayKey>[]) {
          m.exdates.add((eventId: series.id, day: d, add: false));
        }
    }
    return m;
  }
}
