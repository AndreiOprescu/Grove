// The motion of a task list (PLAN §6.3): the burst of a checked box, and
// the rows that slide and fade when they come and go. Ports the rules of
// Sources/Grove/Tasks/TaskSection.swift and Sources/Grove/Theme/CheckBox.swift.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/ui/tasks/task_inspector.dart';
import 'package:grove/ui/tasks/task_row.dart';
import 'package:grove/ui/tasks/tasks_pane.dart';
import 'package:grove/ui/theme/check_box.dart';

import 'tasks_support.dart';

/// A store with motion on. "Now" is Wednesday at 10:00.
AppStore motionStore() {
  final store = makeStore(
    prefs: MemoryPrefs()..set('appearance.motion', true),
    clock: WallTime(day: wednesday, minute: 10 * 60),
  );
  store.selectedDay = wednesday;
  return store;
}

Widget today(AppStore store) =>
    TasksPane(store: store, mode: TasksPaneMode.today);

/// The device asks for less motion.
void reduceMotion(WidgetTester tester) {
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
}

final burst = find.byType(CheckBurst);

/// The place of a row in its list, with the 6 points over it.
Finder place(String id) => find.byKey(ValueKey('row-$id'));

double height(WidgetTester tester, String id) =>
    tester.getSize(place(id)).height;

/// How much of the row shows through: 1 is all of it.
double shown(WidgetTester tester, String id) => tester
    .widget<FadeTransition>(
      find.descendant(of: place(id), matching: find.byType(FadeTransition)),
    )
    .opacity
    .value;

/// The time of a slide, and half of it.
const quarter = Duration(milliseconds: 250);
const eighth = Duration(milliseconds: 125);

/// One frame. A slide is over on the first frame after its time.
const step = Duration(milliseconds: 16);
const rest = Duration(milliseconds: 125 + 16);

void main() {
  group('the burst in a list', () {
    testWidgets('a tap on the box of a task plays the burst, and the row '
        'waits for it', (tester) async {
      final store = motionStore();
      addTask(store, 'A');
      await pumpPane(tester, today(store));

      await tester.tap(checkFinder('a'));
      await tester.pump();
      await tester.pump();
      expect(store.task('a')!.isDone, isTrue);
      expect(
        find.descendant(of: rowFinder('a'), matching: burst),
        findsOneWidget,
      );

      // The burst is over after half a second. The row is still there.
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      expect(burst, findsNothing);
      expect(rowFinder('a'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(rowFinder('a'), findsNothing);
    });

    testWidgets('with Motion off a tap plays no burst', (tester) async {
      final store = paneStore();
      addTask(store, 'A');
      await pumpPane(tester, today(store));
      await tester.tap(checkFinder('a'));
      await tester.pump();
      await tester.pump();
      expect(store.task('a')!.isDone, isTrue);
      expect(burst, findsNothing);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('with "Reduce motion" on the device a tap plays no burst', (
      tester,
    ) async {
      reduceMotion(tester);
      final store = motionStore();
      addTask(store, 'A');
      await pumpPane(tester, today(store));
      await tester.tap(checkFinder('a'));
      await tester.pump();
      await tester.pump();
      expect(store.task('a')!.isDone, isTrue);
      expect(burst, findsNothing);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('the box of the right panel plays the burst too', (
      tester,
    ) async {
      final store = motionStore();
      addTask(store, 'A');
      await pumpPane(tester, TaskInspector(store: store, taskId: 'a'));
      await tester.tap(find.byKey(const ValueKey('inspector-check')));
      await tester.pump();
      await tester.pump();
      expect(store.task('a')!.isDone, isTrue);
      expect(burst, findsOneWidget);
      await tester.pumpAndSettle();
      expect(burst, findsNothing);
    });
  });

  group('rows come and go', () {
    testWidgets('a new row slides in and fades in, in a quarter of a second', (
      tester,
    ) async {
      final store = motionStore();
      addTask(store, 'A');
      await pumpPane(tester, today(store));
      final full = height(tester, 'a');
      expect(full, greaterThan(20));

      final b = store.quickAdd('B', placement: TaskPlacement.day(wednesday))!;
      await tester.pump();
      // At the start the row takes no room and is not seen.
      expect(place(b.id), findsOneWidget);
      expect(height(tester, b.id), lessThan(1));
      expect(shown(tester, b.id), lessThan(0.05));

      await tester.pump(eighth);
      expect(height(tester, b.id), inExclusiveRange(1, full - 1));
      expect(shown(tester, b.id), inExclusiveRange(0.05, 0.95));
      // The row comes from under the row over it: its lower edge is the
      // lower edge of its place.
      expect(
        tester.getRect(rowFinder(b.id)).bottom,
        moreOrLessEquals(tester.getRect(place(b.id)).bottom),
      );

      await tester.pump(rest);
      await tester.pump();
      expect(height(tester, b.id), full);
      expect(shown(tester, b.id), 1);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('a row that goes away slides out and fades, and the rows '
        'under it move up', (tester) async {
      final store = motionStore();
      addTask(store, 'A', sort: 1);
      addTask(store, 'B', sort: 2);
      await pumpPane(tester, today(store));
      final full = height(tester, 'a');
      final topOfA = tester.getTopLeft(place('a')).dy;
      final topOfB = tester.getTopLeft(place('b')).dy;
      expect(topOfB, topOfA + full);

      store.deleteTask('a');
      await tester.pump();
      // The row is still there, whole.
      expect(rowFinder('a'), findsOneWidget);
      expect(height(tester, 'a'), moreOrLessEquals(full, epsilon: 1));
      expect(tester.getTopLeft(place('b')).dy, greaterThan(topOfB - 1));

      await tester.pump(eighth);
      expect(height(tester, 'a'), inExclusiveRange(1, full - 1));
      expect(shown(tester, 'a'), inExclusiveRange(0.05, 0.95));
      expect(
        tester.getTopLeft(place('b')).dy,
        inExclusiveRange(topOfA + 1, topOfB - 1),
      );

      await tester.pump(rest);
      await tester.pump();
      expect(rowFinder('a'), findsNothing);
      expect(place('a'), findsNothing);
      expect(tester.getTopLeft(place('b')).dy, topOfA);
      expect(tester.hasRunningAnimations, isFalse);
      await endToast(tester);
    });

    testWidgets('a finished task waits for its burst, then slides out', (
      tester,
    ) async {
      final store = motionStore();
      addTask(store, 'A', sort: 1);
      addTask(store, 'B', sort: 2);
      await pumpPane(tester, today(store));
      final full = height(tester, 'a');

      await tester.tap(checkFinder('a'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 690));
      expect(height(tester, 'a'), full);

      // The 0.7 s are over: the row goes.
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pump();
      expect(rowFinder('a'), findsOneWidget);
      await tester.pump(eighth);
      expect(height(tester, 'a'), inExclusiveRange(1, full - 1));

      // A row on its way out takes no click.
      await tester.tap(checkFinder('a'), warnIfMissed: false);
      await tester.pump();
      expect(store.task('a')!.isDone, isTrue);

      await tester.pumpAndSettle();
      expect(rowFinder('a'), findsNothing);
      expect(rowFinder('b'), findsOneWidget);
    });

    testWidgets('the last row of a list slides out, and the first row of an '
        'empty list slides in', (tester) async {
      final store = motionStore();
      addTask(store, 'A');
      await pumpPane(tester, today(store));
      final full = height(tester, 'a');

      store.deleteTask('a');
      await tester.pump();
      await tester.pump(eighth);
      expect(rowFinder('a'), findsOneWidget);
      expect(height(tester, 'a'), inExclusiveRange(1, full - 1));
      await tester.pumpAndSettle();
      expect(rowFinder('a'), findsNothing);
      expect(find.byType(TaskRow), findsNothing);
      await endToast(tester);

      final b = store.quickAdd('B', placement: TaskPlacement.day(wednesday))!;
      await tester.pump();
      await tester.pump(eighth);
      expect(height(tester, b.id), inExclusiveRange(1, full - 1));
      await tester.pumpAndSettle();
      expect(height(tester, b.id), full);
    });

    testWidgets('a second change while rows move ends the first', (
      tester,
    ) async {
      final store = motionStore();
      addTask(store, 'A', sort: 1);
      addTask(store, 'B', sort: 2);
      addTask(store, 'C', sort: 3);
      await pumpPane(tester, today(store));
      final full = height(tester, 'a');

      store.deleteTask('a');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      store.deleteTask('b');
      await tester.pump();
      expect(rowFinder('a'), findsNothing);
      expect(rowFinder('b'), findsOneWidget);
      expect(height(tester, 'b'), moreOrLessEquals(full, epsilon: 1));

      await tester.pump(quarter + step);
      await tester.pump();
      expect(rowFinder('b'), findsNothing);
      expect(rowFinder('c'), findsOneWidget);
      expect(tester.hasRunningAnimations, isFalse);
      await endToast(tester);
    });

    testWidgets('with Motion off rows come and go at once', (tester) async {
      final store = paneStore();
      addTask(store, 'A', sort: 1);
      addTask(store, 'B', sort: 2);
      await pumpPane(tester, today(store));
      final full = height(tester, 'a');
      final topOfA = tester.getTopLeft(place('a')).dy;

      store.deleteTask('a');
      await tester.pump();
      expect(rowFinder('a'), findsNothing);
      expect(tester.getTopLeft(place('b')).dy, topOfA);
      expect(tester.hasRunningAnimations, isFalse);

      final c = store.quickAdd('C', placement: TaskPlacement.day(wednesday))!;
      await tester.pump();
      expect(height(tester, c.id), full);
      expect(shown(tester, c.id), 1);
      expect(tester.hasRunningAnimations, isFalse);
      await endToast(tester);
    });

    testWidgets('with "Reduce motion" on the device rows come and go at once', (
      tester,
    ) async {
      reduceMotion(tester);
      final store = motionStore();
      addTask(store, 'A', sort: 1);
      addTask(store, 'B', sort: 2);
      await pumpPane(tester, today(store));
      final full = height(tester, 'a');

      store.deleteTask('a');
      await tester.pump();
      expect(rowFinder('a'), findsNothing);
      expect(tester.hasRunningAnimations, isFalse);

      final c = store.quickAdd('C', placement: TaskPlacement.day(wednesday))!;
      await tester.pump();
      expect(height(tester, c.id), full);
      expect(tester.hasRunningAnimations, isFalse);
      await endToast(tester);
    });

    testWidgets('a list that opens shows its rows at once', (tester) async {
      final store = motionStore();
      addTask(store, 'A');
      addTask(store, 'B');
      store.toggleDone(taskId: 'b');
      await pumpPane(tester, today(store));
      expect(rowFinder('b'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('done-toggle')));
      await tester.pump();
      expect(rowFinder('b'), findsOneWidget);
      expect(height(tester, 'b'), height(tester, 'a'));
      expect(shown(tester, 'b'), 1);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('a row that moves in its list does not slide', (tester) async {
      final store = motionStore();
      addTask(store, 'A', sort: 1);
      addTask(store, 'B', sort: 2);
      await pumpPane(tester, today(store));
      final topOfA = tester.getTopLeft(place('a')).dy;

      store.moveTask('b', to: TaskPlacement.day(wednesday), before: 'a');
      await tester.pump();
      expect(tester.getTopLeft(place('b')).dy, topOfA);
      expect(tester.hasRunningAnimations, isFalse);
      await endToast(tester);
    });

    testWidgets('many rows that come in one step come at once', (tester) async {
      final store = motionStore();
      addTask(store, 'A');
      await pumpPane(tester, today(store));
      final full = height(tester, 'a');

      final added = [
        for (var i = 0; i < 40; i++)
          store.quickAdd('New $i', placement: TaskPlacement.day(wednesday))!,
      ];
      await tester.pump();
      expect(height(tester, added.first.id), full);
      expect(tester.hasRunningAnimations, isFalse);
      // The list still builds only the rows near the view.
      expect(find.byType(TaskRow).evaluate().length, lessThan(41));
    });
  });
}
