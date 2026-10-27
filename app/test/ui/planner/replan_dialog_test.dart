// "Reorganise rest of day": the button next to Timeline and its window. A
// bar and a number per task say how much of it is done; the window shows
// where each one goes before Apply.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/ui/planner/planner_kind.dart';
import 'package:grove/ui/planner/planner_view.dart';
import 'package:grove/ui/planner/replan_dialog.dart';

import '../tasks/tasks_support.dart' show addTask, pumpPane;
import 'planner_support.dart';

final replanButton = find.byKey(const ValueKey('replan-day'));

Finder slider(String id) => find.byKey(ValueKey('replan-slider-$id'));

Finder field(String id) => find.descendant(
  of: find.byKey(ValueKey('replan-field-$id')),
  matching: find.byType(EditableText),
);

Finder outcome(String id) => find.byKey(ValueKey('replan-outcome-$id'));

final footer = find.byKey(const ValueKey('replan-footer'));

String fieldText(WidgetTester tester, String id) =>
    tester.widget<EditableText>(field(id)).controller.text;

double sliderValue(WidgetTester tester, String id) =>
    tester.widget<Slider>(slider(id)).value;

String textOf(WidgetTester tester, Finder f) => tester.widget<Text>(f).data!;

/// Now is 10:00 and the sleep line is at 12:00. "Alpha" (60 minutes) fits,
/// "Beta" (90 minutes) does not, until Beta is 40% done.
final twoTasks = ReplanInput(
  day: wednesday,
  items: const [
    ReplanItem(id: 'a', title: 'Alpha', group: ReplanGroup.task, base: 60),
    ReplanItem(id: 'b', title: 'Beta', group: ReplanGroup.task, base: 90),
  ],
  fixed: const [],
  now: 600,
  until: 720,
);

/// A button that opens the window, and what the window gave back.
class SheetOpener {
  Map<String, int>? result;
  bool closed = false;
}

Future<SheetOpener> openSheet(
  WidgetTester tester,
  ReplanInput input, {
  Size size = const Size(800, 700),
}) async {
  final opener = SheetOpener();
  await pumpPane(
    tester,
    Builder(
      builder: (context) => Center(
        child: TextButton(
          onPressed: () async {
            opener.result = await showReplanSheet(context, input);
            opener.closed = true;
          },
          child: const Text('Open'),
        ),
      ),
    ),
    size: size,
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
  return opener;
}

Future<void> typeInto(WidgetTester tester, String id, String text) async {
  await tester.tap(field(id));
  await tester.pump();
  await tester.enterText(field(id), text);
  await tester.pump();
}

Future<void> submit(WidgetTester tester) async {
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pumpAndSettle();
}

void main() {
  group('the window', () {
    testWidgets('names the time, starts at 0% and shows where each goes', (
      tester,
    ) async {
      await openSheet(tester, twoTasks);
      expect(find.text('Reorganise rest of day'), findsOneWidget);
      expect(find.text('From 10:00 until 12:00'), findsOneWidget);
      expect(fieldText(tester, 'a'), '0');
      expect(fieldText(tester, 'b'), '0');
      expect(sliderValue(tester, 'a'), 0);
      expect(find.text('0% · 1h left'), findsOneWidget);
      expect(find.text('0% · 1h 30m left'), findsOneWidget);
      expect(textOf(tester, outcome('a')), '→ 10:00');
      expect(textOf(tester, outcome('b')), 'Will not fit');
      expect(
        textOf(tester, footer),
        "1 will not fit and goes back to today's list.",
      );
    });

    testWidgets('a drag of the bar sets the number', (tester) async {
      await openSheet(tester, twoTasks);
      await tester.drag(slider('a'), const Offset(1000, 0));
      await tester.pumpAndSettle();

      expect(sliderValue(tester, 'a'), 100);
      expect(fieldText(tester, 'a'), '100');
      expect(find.text('100% · done'), findsOneWidget);
      expect(textOf(tester, outcome('a')), 'Done');
      // Alpha is done, so Beta fits now
      expect(textOf(tester, outcome('b')), '→ 10:00');
      expect(textOf(tester, footer), 'All fit.');
    });

    testWidgets('a typed number moves the bar and the time left', (
      tester,
    ) async {
      await openSheet(tester, twoTasks);
      await typeInto(tester, 'b', '40');

      expect(sliderValue(tester, 'b'), 40);
      // 90 minutes, 40% done: 54 left, so 1h
      expect(find.text('40% · 1h left'), findsOneWidget);
      expect(textOf(tester, outcome('a')), '→ 10:00');
      expect(textOf(tester, outcome('b')), '→ 11:00');
      expect(textOf(tester, footer), 'All fit.');
    });

    testWidgets('a number over 100 is 100', (tester) async {
      await openSheet(tester, twoTasks);
      await typeInto(tester, 'a', '150');
      expect(sliderValue(tester, 'a'), 100);
      expect(textOf(tester, outcome('a')), 'Done');

      await submit(tester);
      expect(fieldText(tester, 'a'), '100');
      expect(sliderValue(tester, 'a'), 100);
    });

    testWidgets('text that is not a number goes back to the value', (
      tester,
    ) async {
      await openSheet(tester, twoTasks);
      await typeInto(tester, 'a', '30');
      await submit(tester);
      expect(fieldText(tester, 'a'), '30');

      await typeInto(tester, 'a', 'abc');
      expect(sliderValue(tester, 'a'), 30);
      await submit(tester);
      expect(fieldText(tester, 'a'), '30');
      expect(sliderValue(tester, 'a'), 30);
    });

    testWidgets('the foot counts what does not fit as it changes', (
      tester,
    ) async {
      final input = ReplanInput(
        day: wednesday,
        items: const [
          ReplanItem(
            id: 'a',
            title: 'Alpha',
            group: ReplanGroup.task,
            base: 60,
          ),
          ReplanItem(id: 'b', title: 'Beta', group: ReplanGroup.task, base: 60),
          ReplanItem(
            id: 'c',
            title: 'Gamma',
            group: ReplanGroup.task,
            base: 60,
          ),
        ],
        fixed: const [],
        now: 600,
        until: 660,
      );
      await openSheet(tester, input);
      expect(
        textOf(tester, footer),
        "2 will not fit and go back to today's list.",
      );
      await typeInto(tester, 'b', '100');
      expect(
        textOf(tester, footer),
        "1 will not fit and goes back to today's list.",
      );
      await typeInto(tester, 'c', '100');
      expect(textOf(tester, footer), 'All fit.');
    });

    testWidgets('a goal block that does not fit says it is removed', (
      tester,
    ) async {
      final input = ReplanInput(
        day: wednesday,
        items: const [
          ReplanItem(
            id: 'g',
            title: 'Read · 10:30',
            group: ReplanGroup.goal,
            base: 120,
            blocks: [Span(id: 'g', start: 630, end: 750)],
          ),
          ReplanItem(id: 'b', title: 'Beta', group: ReplanGroup.task, base: 90),
        ],
        fixed: const [],
        now: 600,
        until: 660,
      );
      await openSheet(tester, input);
      expect(textOf(tester, outcome('g')), 'Will not fit · removed');
      expect(textOf(tester, outcome('b')), 'Will not fit');
      expect(
        textOf(tester, footer),
        "1 will not fit and goes back to today's list. "
        '1 goal block will not fit and is removed.',
      );
      await typeInto(tester, 'b', '100');
      expect(
        textOf(tester, footer),
        '1 goal block will not fit and is removed.',
      );
      await typeInto(tester, 'g', '25');
      expect(textOf(tester, outcome('g')), 'Will not fit · rest removed');
    });

    testWidgets('Apply gives the numbers back', (tester) async {
      final opener = await openSheet(tester, twoTasks);
      await typeInto(tester, 'b', '40');
      await submit(tester);
      await tester.tap(find.byKey(const ValueKey('replan-apply')));
      await tester.pumpAndSettle();

      expect(opener.closed, isTrue);
      expect(opener.result, {'a': 0, 'b': 40});
    });

    testWidgets('Cancel gives nothing back', (tester) async {
      final opener = await openSheet(tester, twoTasks);
      await typeInto(tester, 'b', '40');
      await tester.tap(find.byKey(const ValueKey('replan-cancel')));
      await tester.pumpAndSettle();

      expect(opener.closed, isTrue);
      expect(opener.result, isNull);
    });

    testWidgets('many tasks scroll, and a phone has room for each row', (
      tester,
    ) async {
      final input = ReplanInput(
        day: wednesday,
        items: [
          for (var i = 0; i < 20; i++)
            ReplanItem(
              id: 't$i',
              title: 'A task with a long name, number $i',
              group: ReplanGroup.task,
              base: 30,
            ),
        ],
        fixed: const [],
        now: 600,
        until: 1380,
      );
      await openSheet(tester, input, size: phoneSize);
      expect(tester.takeException(), isNull);
      final apply = find.byKey(const ValueKey('replan-apply'));
      await tester.scrollUntilVisible(
        apply,
        200,
        scrollable: find
            .descendant(
              of: find.byType(Dialog),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(tester.takeException(), isNull);
      expect(apply.hitTestable(), findsOneWidget);
    });
  });

  group('the button next to Timeline', () {
    AppStore todayStore() => plannerStore()..screen = Screen.today;

    testWidgets('is on today, on a desktop and on a phone', (tester) async {
      for (final size in [desktopSize, phoneSize]) {
        final store = todayStore();
        await pumpPlanner(tester, store, size: size);
        expect(replanButton, findsOneWidget, reason: '$size');
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('is not on tomorrow, nor on the week', (tester) async {
      final store = todayStore()..showsTomorrow = true;
      await pumpPlanner(tester, store);
      expect(store.todayScreenDay, wednesday.adding(days: 1));
      expect(find.byType(PlannerView), findsOneWidget);
      expect(replanButton, findsNothing);

      final week = plannerStore();
      await pumpPlanner(tester, week);
      expect(replanButton, findsNothing);
    });

    testWidgets('with nothing to reorganise, a short message shows', (
      tester,
    ) async {
      final store = todayStore();
      await pumpPlanner(tester, store);
      await tester.tap(replanButton);
      await tester.pump();
      expect(store.toast, 'Nothing to reorganise.');
      expect(find.text('Reorganise rest of day'), findsNothing);
      await endToast(tester);
    });

    testWidgets('late at night there is nothing left of today', (tester) async {
      final store = todayStore()
        ..clockOverride = WallTime(day: wednesday, minute: 1430);
      addTask(store, 'Write', estimateMin: 60);
      await pumpPlanner(tester, store);
      await tester.tap(replanButton);
      await tester.pump();
      expect(store.toast, 'Nothing left of today to plan.');
      expect(find.text('Reorganise rest of day'), findsNothing);
      await endToast(tester);
    });

    testWidgets('Apply plans from the minute the window showed', (
      tester,
    ) async {
      final store = todayStore()
        ..clockOverride = WallTime(day: wednesday, minute: 884);
      addTask(store, 'Write', estimateMin: 60);
      await pumpPlanner(tester, store);
      await tester.tap(replanButton);
      await tester.pumpAndSettle();
      expect(find.text('From 14:45 until midnight'), findsOneWidget);
      // Two minutes go by before Apply.
      store.clockOverride = WallTime(day: wednesday, minute: 886);
      await tester.tap(find.byKey(const ValueKey('replan-apply')));
      await tester.pumpAndSettle();
      final blocks = store.blocks(DayRange.single(wednesday));
      expect(blocks.map((b) => (b.startMinute, b.endMinute)), [(885, 945)]);
      await endToast(tester);
    });

    testWidgets('opens the window, and Apply moves the tasks in one step', (
      tester,
    ) async {
      final store = todayStore();
      addTask(store, 'Write', estimateMin: 60);
      await pumpPlanner(tester, store);
      await tester.tap(replanButton);
      await tester.pumpAndSettle();
      expect(find.text('Reorganise rest of day'), findsOneWidget);
      expect(find.text('Write'), findsWidgets);

      await typeInto(tester, 'write', '50');
      await submit(tester);
      await tester.tap(find.byKey(const ValueKey('replan-apply')));
      await tester.pumpAndSettle();

      expect(find.text('Reorganise rest of day'), findsNothing);
      expect(store.undoName, 'Reorganise Day');
      final blocks = store.blocks(DayRange.single(wednesday));
      expect(blocks.map((b) => (b.startMinute, b.endMinute)), [(600, 630)]);
      await endToast(tester);
    });

    testWidgets('Cancel changes nothing', (tester) async {
      final store = todayStore();
      addTask(store, 'Write', estimateMin: 60);
      await pumpPlanner(tester, store);
      final undo = store.undoName;
      await tester.tap(replanButton);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('replan-cancel')));
      await tester.pumpAndSettle();

      expect(store.undoName, undo);
      expect(store.blocks(DayRange.single(wednesday)), isEmpty);
    });

    testWidgets('the header fits at each width with the button', (
      tester,
    ) async {
      final store = todayStore();
      for (var width = 240.0; width <= 520; width += 10) {
        await pumpPane(
          tester,
          PlannerView(store: store, kind: PlannerKind.today),
          size: Size(width, 620),
        );
        await tester.pumpAndSettle();
        expect(replanButton, findsOneWidget);
        expect(
          tester.takeException(),
          isNull,
          reason: 'the timeline at a width of $width',
        );
      }
    });
  });
}
