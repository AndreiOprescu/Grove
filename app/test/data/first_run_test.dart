// Port of Tests/GroveCoreTests/FirstRunTests.swift.
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/core/model/day_key.dart';
import 'package:grove/core/model/event.dart';
import 'package:grove/core/model/note.dart';
import 'package:grove/core/model/task.dart';
import 'package:grove/data/data.dart';

import 'helpers.dart';

void main() {
  const today = DayKey('2026-10-05');

  test('a new database gets three lists and three sample tasks', () {
    final r = makeRepos();
    expect(FirstRun.seedIfNew(r, today: today), isTrue);
    final lists = r.lists.all();
    expect(lists.map((l) => l.name), ['Home', 'Work', 'Personal']);
    expect(lists.map((l) => l.emoji), ['🌿', '💼', '✨']);
    final tasks = r.tasks.forDay(today);
    expect(tasks.length, 3);
    expect(
      tasks.every(
        (t) => t.status == TaskStatus.open && t.bucket == TaskBucket.day,
      ),
      isTrue,
    );
    expect(FirstRun.welcomeVisible(r), isTrue);
  });

  test('the sample tasks explain drag to plan, links and the palette', () {
    final r = makeRepos();
    FirstRun.seedIfNew(r, today: today);
    final titles = r.tasks.forDay(today).map((t) => t.title).toList();
    expect(
      titles.any((t) {
        final low = t.toLowerCase();
        return low.contains('drag') && low.contains('planner');
      }),
      isTrue,
    );
    expect(titles.any((t) => t.contains('[[')), isTrue);
    expect(titles.any((t) => t.contains('⌘K')), isTrue);
  });

  test('the sample task ids are kept so they can be removed', () {
    final r = makeRepos();
    FirstRun.seedIfNew(r, today: today);
    final ids = FirstRun.sampleTaskIds(r);
    expect(ids.toSet(), r.tasks.all().map((t) => t.id).toSet());
    expect(ids.length, 3);
  });

  test('seeding twice does nothing the second time', () {
    final r = makeRepos();
    expect(FirstRun.seedIfNew(r, today: today), isTrue);
    expect(FirstRun.seedIfNew(r, today: today), isFalse);
    expect(r.lists.all().length, 3);
    expect(r.tasks.all().length, 3);
  });

  test('a database with data is left alone', () {
    final r = makeRepos();
    r.tasks.save(TaskItem(title: 'My own task'));
    expect(FirstRun.seedIfNew(r, today: today), isFalse);
    expect(r.lists.all(), isEmpty);
    expect(r.tasks.all().map((t) => t.title), ['My own task']);
    expect(FirstRun.welcomeVisible(r), isFalse);
  });

  test('a note or an event or a list alone counts as data', () {
    final fills = <void Function(Repos)>[
      (r) => r.notes.save(Note(title: 'A note')),
      (r) => r.events.save(
        EventItem(
          title: 'Dentist',
          start: const WallTime(day: today, minute: 540),
          end: const WallTime(day: today, minute: 600),
        ),
      ),
      (r) => r.lists.save(ListItem(name: 'Mine')),
    ];
    for (final fill in fills) {
      final r = makeRepos();
      fill(r);
      expect(FirstRun.seedIfNew(r, today: today), isFalse);
    }
  });

  test('a seeded database that was emptied is not seeded again', () {
    final r = makeRepos();
    FirstRun.seedIfNew(r, today: today);
    for (final t in r.tasks.all()) {
      r.tasks.delete(t.id);
    }
    for (final l in r.lists.all(includeArchived: true)) {
      r.lists.delete(l.id);
    }
    expect(FirstRun.seedIfNew(r, today: today), isFalse);
    expect(r.lists.all(), isEmpty);
  });

  test('dismissing the card keeps the tasks', () {
    final r = makeRepos();
    FirstRun.seedIfNew(r, today: today);
    FirstRun.dismissWelcome(r);
    expect(FirstRun.welcomeVisible(r), isFalse);
    expect(r.tasks.all().length, 3);
    // "Remove samples" still knows them.
    expect(FirstRun.sampleTaskIds(r).length, 3);
  });

  test('forgetting the samples clears the list', () {
    final r = makeRepos();
    FirstRun.seedIfNew(r, today: today);
    FirstRun.forgetSamples(r);
    expect(FirstRun.sampleTaskIds(r), isEmpty);
    expect(FirstRun.welcomeVisible(r), isFalse);
  });
}
