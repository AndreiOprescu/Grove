part of 'app_store.dart';

/// The wake-up line and the sleep line of a day in the planner. Each day
/// has its own two lines. They are marks only: they move no block and they
/// block no time.
///
/// The times are rows of the `settings` table (see [DayMarkerRules]).
extension AppStoreDayMarkers on AppStore {
  /// The lines of the days in [range]: by day, wake-up before sleep.
  List<DayMarker> dayMarkers(DayRange range) {
    final out = <DayMarker>[];
    for (final kind in DayMarkerKind.values) {
      final rows = _try(
        () => repos.db.query(
          'SELECT key, value FROM settings WHERE key >= ? AND key <= ?',
          [
            DayMarkerRules.key(kind, range.first),
            DayMarkerRules.key(kind, range.last),
          ],
          (r) => DayMarkerRules.parse(kind, r.text(0), r.text(1)),
        ),
      );
      out.addAll((rows ?? const <DayMarker?>[]).nonNulls);
    }
    return out..sort((a, b) {
      final byDay = a.day.compareTo(b.day);
      return byDay != 0 ? byDay : a.kind.index.compareTo(b.kind.index);
    });
  }

  /// The minute of one line, or null when the day has no such line.
  int? dayMarker(DayMarkerKind kind, DayKey day) {
    final key = DayMarkerRules.key(kind, day);
    final value = _try(() => repos.settings.get(key));
    return value == null
        ? null
        : DayMarkerRules.parse(kind, key, value)?.minute;
  }

  /// Where a new line of [day] starts: the time of the last day before it
  /// that has one, else of the next day that has one, else 07:00 for the
  /// wake-up line and 23:00 for the sleep line.
  int newDayMarkerMinute(DayMarkerKind kind, DayKey day) {
    final key = DayMarkerRules.key(kind, day);
    DayMarker? near(String sql, List<Object?> values) => _try(
      () => repos.db
          .query(
            sql,
            values,
            (r) => DayMarkerRules.parse(kind, r.text(0), r.text(1)),
          )
          .nonNulls
          .firstOrNull,
    );
    final before = near(
      'SELECT key, value FROM settings WHERE key >= ? AND key < ? '
      'ORDER BY key DESC LIMIT 8',
      [DayMarkerRules.prefix(kind), key],
    );
    final found =
        before ??
        near(
          'SELECT key, value FROM settings WHERE key > ? AND key < ? '
          'ORDER BY key LIMIT 8',
          [key, DayMarkerRules.prefixEnd(kind)],
        );
    return found?.minute ?? DayMarkerRules.firstMinute(kind);
  }

  /// Adds the line to [day]. Gives its minute. A line that is there stays
  /// where it is. With [at], the new line starts at that minute, on the grid
  /// of 15 minutes (a right click on the time of the planner).
  int? addDayMarker(DayMarkerKind kind, DayKey day, {int? at}) {
    final has = dayMarker(kind, day);
    if (has != null) return has;
    final key = DayMarkerRules.key(kind, day);
    final minute = at == null
        ? newDayMarkerMinute(kind, day)
        : DayMarkerRules.snapped(at);
    final m = Mutation('Add ${kind.undoName}')
      ..settings.add((
        key: key,
        // A value that is no time may be there. Undo brings it back.
        before: _try(() => repos.settings.get(key)),
        after: '$minute',
      ));
    return commit(m) ? minute : null;
  }

  /// Puts the line of [day] at [minute], on the grid of the planner. One
  /// undo step. Does nothing when the day has no such line.
  void moveDayMarker(DayMarkerKind kind, DayKey day, int minute) {
    final old = dayMarker(kind, day);
    final next = DayMarkerRules.snapped(minute);
    if (old == null || old == next) return;
    final key = DayMarkerRules.key(kind, day);
    commit(
      Mutation('Move ${kind.undoName}')
        ..settings.add((
          key: key,
          before: _try(() => repos.settings.get(key)),
          after: '$next',
        )),
    );
  }

  /// Takes the line away from [day].
  void removeDayMarker(DayMarkerKind kind, DayKey day) {
    final key = DayMarkerRules.key(kind, day);
    final old = _try(() => repos.settings.get(key));
    if (old == null) return;
    commit(
      Mutation('Remove ${kind.undoName}')
        ..settings.add((key: key, before: old, after: null)),
    );
  }

  /// Saves the settings of a change, or puts the old ones back.
  void _applySettings(Mutation m, {required bool forward}) {
    for (final s in forward ? m.settings : m.settings.reversed) {
      final value = forward ? s.after : s.before;
      if (value == null) {
        repos.settings.remove(s.key);
      } else {
        repos.settings.set(s.key, value);
      }
    }
  }
}
