// Port of SpreadRulesTests in Tests/GroveTests/SpreadTests.swift: the numbers
// and the words of the Day Spread (PLAN §8, layout B).
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/state/state.dart';
import 'package:grove/ui/spread/spread_rules.dart';

void main() {
  test('the task list stays between 300 and 420', () {
    expect(SpreadRules.clampTasks(100), 300);
    expect(SpreadRules.clampTasks(340), 340);
    expect(SpreadRules.clampTasks(900), 420);
  });

  test('the task list starts inside its range', () {
    expect(
      SpreadRules.tasksDefault,
      greaterThanOrEqualTo(SpreadRules.tasksMin),
    );
    expect(SpreadRules.tasksDefault, lessThanOrEqualTo(SpreadRules.tasksMax));
  });

  test('three columns fit the smallest window', () {
    expect(SpreadRules.minimumWindowWidth, lessThanOrEqualTo(1100));
  });

  test('the timeline is the wide column in the first window (1280)', () {
    final timeline =
        1280 -
        2 * SpreadRules.side -
        2 * SpreadRules.gap -
        SpreadRules.tasksDefault -
        SpreadRules.noteWidth;
    expect(timeline, greaterThan(SpreadRules.tasksDefault));
    expect(timeline, greaterThan(SpreadRules.noteWidth));
    expect(timeline, greaterThanOrEqualTo(SpreadRules.timelineMinimum));
  });

  test('today gets a greeting and the growth', () {
    expect(
      SpreadRules.subtitle(
        isToday: true,
        greeting: 'Good morning',
        progress: const PlantProgress(done: 1, total: 2),
      ),
      'Good morning · 50% of today grown',
    );
  });

  test('another day gets no greeting', () {
    expect(
      SpreadRules.subtitle(
        isToday: false,
        greeting: 'Good morning',
        progress: const PlantProgress(done: 1, total: 4),
      ),
      '25% of the day grown',
    );
  });

  test('a day with no tasks says so', () {
    const none = PlantProgress(done: 0, total: 0);
    expect(
      SpreadRules.subtitle(
        isToday: true,
        greeting: 'Good evening',
        progress: none,
      ),
      'Good evening · Nothing planned today',
    );
    expect(
      SpreadRules.subtitle(
        isToday: false,
        greeting: 'Good evening',
        progress: none,
      ),
      'Nothing planned',
    );
  });

  test('the columns of a window: the timeline takes what is left', () {
    final c = SpreadRules.columns(width: 1280, tasks: 340);
    expect(c.tasks, 340);
    expect(c.note, 340);
    expect(c.timeline, 1280 - 32 - 24 - 340 - 340);
  });

  test('a small window gives the task list less, the timeline its minimum', () {
    final c = SpreadRules.columns(width: 1100, tasks: 420);
    expect(c.timeline, greaterThanOrEqualTo(SpreadRules.timelineMinimum));
    expect(c.tasks + c.timeline + c.note + 32 + 24, lessThanOrEqualTo(1100));
  });

  test('a window too narrow for three columns loses the note column', () {
    final c = SpreadRules.columns(width: 760, tasks: 340);
    expect(c.note, 0);
    expect(c.tasks, greaterThanOrEqualTo(SpreadRules.tasksMin));
    expect(c.tasks + c.timeline + 32 + 12, lessThanOrEqualTo(760));
  });

  test('beside an open left panel: the timeline and the note', () {
    final wide = SpreadRules.columnsBesidePane(width: 764);
    expect(wide.note, 340);
    expect(wide.timeline, 764 - 32 - 12 - 340);
    final narrow = SpreadRules.columnsBesidePane(width: 500);
    expect(narrow.note, 0);
    expect(narrow.timeline, 500 - 32);
  });
}
