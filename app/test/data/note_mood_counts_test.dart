import 'package:flutter_test/flutter_test.dart';
import 'package:grove/core/model/day_key.dart';
import 'package:grove/core/model/note.dart';

import 'helpers.dart';

// The count of days per mood, for the Persona screen. Only daily notes with
// a mood count.

Note daily(String day, int? mood) =>
    Note(title: day, kind: NoteKind.daily, date: DayKey(day), mood: mood);

void main() {
  test('counts the daily notes of each mood', () {
    final r = makeRepos();
    r.notes.save(daily('2026-10-01', 3));
    r.notes.save(daily('2026-10-02', 3));
    r.notes.save(daily('2026-10-03', 1));
    r.notes.save(daily('2026-10-04', null));
    expect(r.notes.moodCounts(), {3: 2, 1: 1});
  });

  test('a weekly or plain note does not count', () {
    final r = makeRepos();
    r.notes.save(
      Note(
        title: 'Week',
        kind: NoteKind.weekly,
        date: const DayKey('2026-10-05'),
        mood: 3,
      ),
    );
    r.notes.save(Note(title: 'Plain', mood: 2));
    expect(r.notes.moodCounts(), isEmpty);
  });

  test('from and to keep the days between them, both included', () {
    final r = makeRepos();
    r.notes.save(daily('2026-09-30', 1));
    r.notes.save(daily('2026-10-01', 2));
    r.notes.save(daily('2026-10-31', 3));
    r.notes.save(daily('2026-11-01', 3));
    expect(
      r.notes.moodCounts(
        from: const DayKey('2026-10-01'),
        to: const DayKey('2026-10-31'),
      ),
      {2: 1, 3: 1},
    );
  });
}
