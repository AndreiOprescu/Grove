// Focus mode on the screen (PLAN §5.1.7): the small timer at the bottom
// right, the count down, and the question at the end of the block.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/ui/planner/focus_card.dart';
import 'package:grove/ui/planner/planner_view.dart';
import 'package:grove/ui/tasks/task_widgets.dart' show ProgressBar;

import '../tasks/tasks_support.dart' show pumpPane;
import 'planner_support.dart';

final card = find.byType(FocusCard);

Finder inCard(Finder what) => find.descendant(of: card, matching: what);

/// "Start Focus" in the menu of the block at 10:30.
Future<void> startFromMenu(WidgetTester tester) async {
  await rightClick(tester, pointAt(tester, focusDay, 10 * 60 + 30));
  await tester.tap(find.text('Start Focus'));
  await tester.pumpAndSettle();
}

void main() {
  group('the focus timer', () {
    testWidgets('no session, no card', (tester) async {
      final store = focusStore();
      hourBlock(store, 'Write report');
      await pumpPlanner(tester, store);

      expect(card, findsNothing);
    });

    testWidgets('"Start Focus" in the menu of a block shows the timer', (
      tester,
    ) async {
      final store = focusStore();
      final id = hourBlock(store, 'Write report');
      setFocusClock(tester, 10, 35);
      await pumpPlanner(tester, store);

      await startFromMenu(tester);
      expect(store.focus?.blockId, id);
      expect(card, findsOneWidget);
      expect(inCard(find.text('Write report')), findsOneWidget);
      // 25 minutes are left to the end of the block.
      expect(inCard(find.text('25:00')), findsOneWidget);
      expect(inCard(find.byType(ProgressBar)), findsOneWidget);
      expect(inCard(find.textContaining('Time is up')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the timer counts down each second', (tester) async {
      final store = focusStore();
      hourBlock(store, 'Write report');
      setFocusClock(tester, 10, 35);
      await pumpPlanner(tester, store);
      await startFromMenu(tester);

      await tester.pump(const Duration(seconds: 1));
      expect(inCard(find.text('24:59')), findsOneWidget);
      await tester.pump(const Duration(seconds: 59));
      expect(inCard(find.text('24:00')), findsOneWidget);
    });

    testWidgets('a session of more than one hour shows the hours', (
      tester,
    ) async {
      final store = focusStore();
      hourBlock(store, 'Write report');
      setFocusClock(tester, 9, 57, 55);
      await pumpPlanner(tester, store);
      await startFromMenu(tester);

      expect(inCard(find.text('1:02:05')), findsOneWidget);
    });

    testWidgets('the cross stops the session; the task stays open', (
      tester,
    ) async {
      final store = focusStore();
      final id = hourBlock(store, 'Write report');
      setFocusClock(tester, 10, 35);
      await pumpPlanner(tester, store);
      await startFromMenu(tester);

      await tester.tap(inCard(find.bySemanticsLabel('Stop focus')));
      await tester.pumpAndSettle();
      expect(store.focus, isNull);
      expect(card, findsNothing);
      expect(store.task(store.event(id)!.taskId!)!.isDone, isFalse);
    });

    testWidgets('the menu says "Stop Focus" while the session runs', (
      tester,
    ) async {
      final store = focusStore();
      hourBlock(store, 'Write report');
      setFocusClock(tester, 10, 35);
      await pumpPlanner(tester, store);
      await startFromMenu(tester);

      await rightClick(tester, pointAt(tester, focusDay, 10 * 60 + 30));
      expect(find.text('Start Focus'), findsNothing);
      await tester.tap(find.text('Stop Focus'));
      await tester.pumpAndSettle();
      expect(store.focus, isNull);
      expect(card, findsNothing);
    });

    testWidgets('at the end of the block the card asks "Mark done?"', (
      tester,
    ) async {
      final store = focusStore();
      hourBlock(store, 'Write report');
      setFocusClock(tester, 10, 59, 58);
      await pumpPlanner(tester, store);
      await startFromMenu(tester);
      expect(inCard(find.text('0:02')), findsOneWidget);

      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(store.focus?.finished, isTrue);
      expect(inCard(find.text('Time is up. Mark done?')), findsOneWidget);
      expect(inCard(find.text('Mark done')), findsOneWidget);
      expect(inCard(find.text('Not yet')), findsOneWidget);
      // The count down is gone.
      expect(inCard(find.text('0:00')), findsNothing);
      expect(inCard(find.byType(ProgressBar)), findsNothing);
      // The card stays until the user answers.
      await tester.pump(const Duration(minutes: 5));
      expect(inCard(find.text('Time is up. Mark done?')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('"Mark done" checks the task off and closes the card', (
      tester,
    ) async {
      final store = focusStore();
      final id = hourBlock(store, 'Write report');
      setFocusClock(tester, 10, 59, 59);
      await pumpPlanner(tester, store);
      await startFromMenu(tester);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();

      await tester.tap(inCard(find.bySemanticsLabel('Mark done')));
      await tester.pumpAndSettle();
      expect(store.task(store.event(id)!.taskId!)!.isDone, isTrue);
      expect(store.focus, isNull);
      expect(card, findsNothing);
    });

    testWidgets('"Not yet" closes the card and the task stays open', (
      tester,
    ) async {
      final store = focusStore();
      final id = hourBlock(store, 'Write report');
      setFocusClock(tester, 10, 59, 59);
      await pumpPlanner(tester, store);
      await startFromMenu(tester);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();

      await tester.tap(inCard(find.bySemanticsLabel('Not yet')));
      await tester.pumpAndSettle();
      expect(store.task(store.event(id)!.taskId!)!.isDone, isFalse);
      expect(store.focus, isNull);
      expect(card, findsNothing);
    });

    testWidgets('a block with no task says "Time is up." with "OK"', (
      tester,
    ) async {
      final store = focusStore();
      final id = hourBlock(store, 'Lunch', asEvent: true);
      setFocusClock(tester, 10, 59, 59);
      await pumpPlanner(tester, store);
      store.startFocus(store.event(id)!);
      await tester.pumpAndSettle();
      expect(inCard(find.text('Lunch')), findsOneWidget);
      expect(inCard(find.text('0:01')), findsOneWidget);

      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(inCard(find.text('Time is up.')), findsOneWidget);
      expect(inCard(find.text('Mark done')), findsNothing);
      await tester.tap(inCard(find.bySemanticsLabel('OK')));
      await tester.pumpAndSettle();
      expect(store.focus, isNull);
      expect(card, findsNothing);
    });

    testWidgets('a session that ended on another screen asks at once', (
      tester,
    ) async {
      final store = focusStore();
      final id = hourBlock(store, 'Write report');
      store.screen = Screen.notes;
      await pumpPlanner(tester, store);
      store.startFocus(store.event(id)!);
      await tester.pumpAndSettle();

      // The block ended five minutes ago.
      setFocusClock(tester, 11, 5);
      store.screen = Screen.planner;
      await tester.pumpAndSettle();
      expect(inCard(find.text('Time is up. Mark done?')), findsOneWidget);
      expect(store.focus?.finished, isTrue);
    });

    testWidgets('a new session on another block takes the place of the old '
        'one', (tester) async {
      final store = focusStore();
      hourBlock(store, 'Write report');
      store.createFromDraft(
        title: 'Call the bank',
        day: focusDay,
        start: 12 * 60,
        end: 12 * 60 + 30,
        asEvent: false,
      );
      setFocusClock(tester, 10, 59, 58);
      await pumpPlanner(tester, store);
      await startFromMenu(tester);

      await rightClick(tester, pointAt(tester, focusDay, 12 * 60 + 15));
      await tester.tap(find.text('Start Focus'));
      await tester.pumpAndSettle();
      expect(card, findsOneWidget);
      expect(inCard(find.text('Call the bank')), findsOneWidget);
      // The clicks took time. The clock starts again, two seconds before
      // the end of the first block.
      setFocusClock(tester, 10, 59, 58);
      await tester.pump(const Duration(seconds: 1));
      expect(inCard(find.text('1:30:02')), findsOneWidget);
      // The end of the first block does not end this session.
      await tester.pump(const Duration(seconds: 3));
      expect(store.focus?.finished, isFalse);
      expect(inCard(find.text('1:29:59')), findsOneWidget);
    });

    testWidgets('the card is 230 wide, 16 from the bottom right corner', (
      tester,
    ) async {
      final store = focusStore();
      final id = hourBlock(store, 'Write report');
      setFocusClock(tester, 10, 35);
      await pumpPlanner(tester, store);
      store.startFocus(store.event(id)!);
      await tester.pumpAndSettle();

      final view = tester.getRect(find.byType(PlannerView));
      final rect = tester.getRect(card);
      expect(rect.width, 230);
      expect(rect.right, moreOrLessEquals(view.right - 16, epsilon: 1));
      expect(rect.bottom, moreOrLessEquals(view.bottom - 16, epsilon: 1));
      // On whole points, so the text is sharp.
      expect(rect.left, rect.left.roundToDouble());
      expect(rect.top, rect.top.roundToDouble());
    });

    testWidgets('the grid under the rest of the screen still takes clicks', (
      tester,
    ) async {
      final store = focusStore();
      final id = hourBlock(store, 'Write report');
      setFocusClock(tester, 10, 35);
      await pumpPlanner(tester, store);
      store.startFocus(store.event(id)!);
      await tester.pumpAndSettle();

      await mouseTap(tester, pointAt(tester, focusDay, 10 * 60 + 30));
      await endTapWindow(tester);
      expect(store.selection, {id});
    });

    testWidgets('the card shows on Today and on Calendar too', (tester) async {
      final store = focusStore();
      final id = hourBlock(store, 'Write report');
      setFocusClock(tester, 10, 35);
      await pumpPlanner(tester, store);
      store.startFocus(store.event(id)!);
      await tester.pumpAndSettle();

      store.screen = Screen.today;
      await tester.pumpAndSettle();
      expect(card, findsOneWidget);
      expect(inCard(find.text('25:00')), findsOneWidget);

      store.screen = Screen.calendar;
      await tester.pumpAndSettle();
      expect(card, findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the card fits on a phone', (tester) async {
      final store = focusStore();
      final id = hourBlock(store, 'A long title of a task that does not fit');
      setFocusClock(tester, 10, 59, 59);
      await pumpPlanner(tester, store, size: phoneSize);
      store.startFocus(store.event(id)!);
      await tester.pumpAndSettle();

      var rect = tester.getRect(card);
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(phoneSize.width));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      rect = tester.getRect(card);
      expect(rect.width, 230);
      expect(rect.bottom, lessThanOrEqualTo(phoneSize.height));
      // A finger has room on the buttons.
      for (final label in ['Stop focus', 'Mark done', 'Not yet']) {
        final size = tester.getSize(inCard(find.bySemanticsLabel(label)));
        expect(size.height, greaterThanOrEqualTo(28), reason: label);
        expect(size.width, greaterThanOrEqualTo(28), reason: label);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('with motion on, the card comes in from the right', (
      tester,
    ) async {
      final store = focusStore(motion: true);
      final id = hourBlock(store, 'Write report');
      setFocusClock(tester, 10, 35);
      await pumpPane(
        tester,
        FocusLayer(store: store, child: const SizedBox.expand()),
        size: const Size(600, 400),
      );
      store.startFocus(store.event(id)!);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      final early = tester.getRect(card);
      expect(early.left, greaterThan(600 - 16 - 230));

      await tester.pump(const Duration(milliseconds: 300));
      final rest = tester.getRect(card);
      expect(rest.right, 600 - 16);
      expect(rest.bottom, 400 - 16);

      // And it goes out the same way.
      store.stopFocus();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      expect(card, findsOneWidget);
      await tester.pump(const Duration(milliseconds: 300));
      expect(card, findsNothing);
    });
  });

  group('the focus card alone', () {
    FocusSession session({String? taskId = 't1', bool finished = false}) =>
        FocusSession(
          blockId: 'b1',
          taskId: taskId,
          title: 'Write report',
          day: focusDay,
          start: DateTime(2099, 3, 4, 10),
          end: DateTime(2099, 3, 4, 11),
          finished: finished,
        );

    Future<void> pumpCard(WidgetTester tester, FocusSession s) => pumpPane(
      tester,
      Align(
        alignment: Alignment.topLeft,
        child: FocusCard(store: focusStore(), session: s),
      ),
      size: const Size(300, 200),
    );

    testWidgets('the bar shows how far the session is', (tester) async {
      setFocusClock(tester, 10, 15);
      await pumpCard(tester, session());

      expect(find.text('45:00'), findsOneWidget);
      expect(
        tester.widget<ProgressBar>(find.byType(ProgressBar)).fraction,
        moreOrLessEquals(0.25, epsilon: 0.001),
      );
      await tester.pump(const Duration(minutes: 15));
      expect(find.text('30:00'), findsOneWidget);
      expect(
        tester.widget<ProgressBar>(find.byType(ProgressBar)).fraction,
        moreOrLessEquals(0.5, epsilon: 0.001),
      );
    });

    testWidgets('a screen reader hears the timer and the time left', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      setFocusClock(tester, 10, 35);
      await pumpCard(tester, session());

      expect(find.bySemanticsLabel('Focus timer'), findsOneWidget);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Time left')),
        matchesSemantics(label: 'Time left', value: '25:00'),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('Stop focus')),
        matchesSemantics(
          label: 'Stop focus',
          isButton: true,
          hasTapAction: true,
        ),
      );
      handle.dispose();
    });

    testWidgets('a finished session shows the question, not the clock', (
      tester,
    ) async {
      setFocusClock(tester, 10, 35);
      await pumpCard(tester, session(finished: true));

      expect(find.text('Time is up. Mark done?'), findsOneWidget);
      expect(find.text('25:00'), findsNothing);
    });

    testWidgets('a finished session with no task has only "OK"', (
      tester,
    ) async {
      setFocusClock(tester, 11, 30);
      await pumpCard(tester, session(taskId: null));
      await tester.pump();

      expect(find.text('Time is up.'), findsOneWidget);
      expect(find.bySemanticsLabel('OK'), findsOneWidget);
      expect(find.bySemanticsLabel('Mark done'), findsNothing);
    });
  });
}
