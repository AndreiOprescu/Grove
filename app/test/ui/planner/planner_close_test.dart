// The last paths of the planner that no test went through the screen for
// (PLAN §5.1.1 to §5.1.4, §5.1.7, §5.5, §5.9 and §10).
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/ui/planner/planner_grid.dart';
import 'package:grove/ui/store_app.dart';
import 'package:grove/ui/tasks/task_inspector.dart';
import 'package:grove/ui/theme/check_box.dart';
import 'package:grove/ui/theme/grove_theme.dart';
import 'package:grove/ui/theme/named_colors.dart';
import 'package:grove/ui/theme/panel.dart';

import 'planner_support.dart';

/// A line of the open menu.
Finder menuLine(String label) =>
    find.widgetWithText(PopupMenuItem<VoidCallback>, label);

/// Clicks a line of the open menu.
Future<void> pick(WidgetTester tester, String label) async {
  await tester.tap(menuLine(label));
  await tester.pumpAndSettle();
}

/// A block on Wednesday. Gives the block.
PlannerBlock addBlock(
  AppStore store,
  String title, {
  bool asEvent = true,
  int start = 11 * 60,
  int length = 60,
}) {
  store.createFromDraft(
    title: title,
    day: wednesday,
    start: start,
    end: start + length,
    asEvent: asEvent,
  );
  return blockNamed(store, title);
}

List<PlannerBlock> blocksOfWednesday(AppStore store) =>
    store.blocks(DayRange.single(wednesday));

/// Shows the planner with motion on. The now line moves all the time, so the
/// screen never comes to rest: this pumps for a fixed time.
Future<void> pumpMoving(WidgetTester tester, AppStore store) async {
  tester.view.physicalSize = desktopSize;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(StoreApp(key: UniqueKey(), store: store));
  addTearDown(() => tester.pumpWidget(const SizedBox()));
  await tester.pump(const Duration(milliseconds: 500));
}

/// Scrolls the grid of the planner to `pixels`, with no animation.
Future<void> scrollGridTo(WidgetTester tester, double pixels) async {
  tester
      .state<ScrollableState>(
        find
            .descendant(
              of: find.byType(PlannerGrid),
              matching: find.byType(Scrollable),
            )
            .first,
      )
      .position
      .jumpTo(pixels);
  await tester.pump();
}

/// The place of the working-hours tint in the column of `day`.
Rect workTint(WidgetTester tester, DayKey day) {
  final accent = GroveTheme.of(tester.element(columnFinder(day))).accent;
  return tester.getRect(
    find.descendant(
      of: columnFinder(day),
      matching: find.byWidgetPredicate(
        (w) => w is ColoredBox && w.color == accent.withValues(alpha: 0.045),
      ),
    ),
  );
}

/// How strong the face of a block is drawn: 1 is full.
double faceOpacity(WidgetTester tester, String blockId) => tester
    .widget<Opacity>(
      find
          .descendant(of: blockFinder(blockId), matching: find.byType(Opacity))
          .first,
    )
    .opacity;

/// The style of the title of a block.
TextStyle titleStyle(WidgetTester tester, String blockId, String title) =>
    tester
        .widget<Text>(
          find.descendant(of: blockFinder(blockId), matching: find.text(title)),
        )
        .style!;

/// The words of the label next to a dragged block.
String liveLabel(WidgetTester tester) => tester
    .widget<Text>(
      find.descendant(
        of: find.byKey(const ValueKey('live-label')),
        matching: find.byType(Text),
      ),
    )
    .data!;

/// The pointer the mouse of the test shows now.
MouseCursor? mouseCursor() =>
    RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1);

/// Counts the haptic ticks the app asks the device for.
List<String> listenForHaptics(WidgetTester tester) {
  final ticks = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'HapticFeedback.vibrate') {
        ticks.add(call.arguments as String);
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return ticks;
}

void main() {
  group('the scroll to now', () {
    testWidgets('on open the grid starts one hour above now', (tester) async {
      final store = plannerStore();
      await pumpPlanner(tester, store);

      // Now is 10:00, so 09:00 is at the top.
      expect(gridScroll(tester), 9 * hour);
      final grid = tester.getRect(find.byType(PlannerGrid));
      final nowLine = tester.getRect(find.byKey(const ValueKey('now-line')));
      expect(nowLine.center.dy - grid.top, closeTo(hour, 2));
    });

    testWidgets('a later hour starts lower', (tester) async {
      final store = plannerStore(now: 14 * 60 + 30);
      await pumpPlanner(tester, store);

      expect(gridScroll(tester), 13.5 * hour);
    });

    testWidgets('"Today" scrolls back to one hour above now', (tester) async {
      final store = plannerStore();
      await pumpPlanner(tester, store);

      await scrollGridTo(tester, 0);
      expect(gridScroll(tester), 0);
      await tester.tap(find.byKey(const ValueKey('planner-today')));
      await tester.pumpAndSettle();
      expect(gridScroll(tester), 9 * hour);

      // From another week too.
      await tester.tap(find.bySemanticsLabel('Next'));
      await tester.pumpAndSettle();
      await scrollGridTo(tester, 2 * hour);
      await tester.tap(find.byKey(const ValueKey('planner-today')));
      await tester.pumpAndSettle();
      expect(store.selectedDay, wednesday);
      expect(gridScroll(tester), 9 * hour);
    });
  });

  group('the working hours', () {
    testWidgets('the tint covers 09:00 to 18:00 when nothing is set', (
      tester,
    ) async {
      final store = plannerStore();
      await pumpPlanner(tester, store);

      for (var i = 0; i < 7; i++) {
        final day = wednesday.adding(days: i - 2);
        final column = tester.getRect(columnFinder(day));
        final tint = workTint(tester, day);
        expect(tint.top, column.top + 9 * hour, reason: day.string);
        expect(tint.height, 9 * hour, reason: day.string);
        expect(tint.left, column.left, reason: day.string);
        expect(tint.width, column.width, reason: day.string);
      }
    });

    testWidgets('the tint covers the hours of the settings', (tester) async {
      final store = plannerStore();
      store.prefs
        ..set('planner.workStart', 7 * 60 + 30)
        ..set('planner.workEnd', 15 * 60);
      await pumpPlanner(tester, store);

      final column = tester.getRect(columnFinder(wednesday));
      final tint = workTint(tester, wednesday);
      expect(tint.top, column.top + 7.5 * hour);
      expect(tint.bottom, column.top + 15 * hour);
    });
  });

  group('a done block', () {
    testWidgets('is faded and its title is struck', (tester) async {
      final store = plannerStore();
      final done = addBlock(store, 'Write report', asEvent: false);
      final open = addBlock(store, 'Call the bank', asEvent: false, start: 840);
      store.toggleDone(taskId: done.taskId!);
      await pumpPlanner(tester, store);

      expect(blockNamed(store, 'Write report').isDone, isTrue);
      expect(faceOpacity(tester, done.id), 0.55);
      expect(
        titleStyle(tester, done.id, 'Write report').decoration,
        TextDecoration.lineThrough,
      );

      // An open block next to it is not.
      expect(faceOpacity(tester, open.id), 1);
      expect(titleStyle(tester, open.id, 'Call the bank').decoration, isNull);
    });

    testWidgets('a block fades when its check box is ticked', (tester) async {
      final store = plannerStore();
      final block = addBlock(store, 'Write report', asEvent: false);
      await pumpPlanner(tester, store);
      expect(faceOpacity(tester, block.id), 1);

      await tester.tap(find.byKey(ValueKey('check-${block.id}')));
      await tester.pumpAndSettle();

      expect(faceOpacity(tester, block.id), 0.55);
      expect(
        titleStyle(tester, block.id, 'Write report').decoration,
        TextDecoration.lineThrough,
      );
    });

    testWidgets('a tick plays the burst of the theme in the block', (
      tester,
    ) async {
      final store = plannerStore(motion: true);
      final block = addBlock(store, 'Write report', asEvent: false);
      await pumpPlanner(tester, store);
      final box = find.byKey(ValueKey('check-${block.id}'));
      final burst = find.descendant(of: box, matching: find.byType(CheckBurst));
      expect(burst, findsNothing);

      await tester.tap(box);
      await tester.pump();
      await tester.pump();
      expect(blocksOfWednesday(store).single.isDone, isTrue);
      expect(burst, findsOneWidget);

      // The burst is over after half a second.
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(burst, findsNothing);
    });

    testWidgets('with Motion off a tick plays no burst', (tester) async {
      final store = plannerStore();
      final block = addBlock(store, 'Write report', asEvent: false);
      await pumpPlanner(tester, store);

      await tester.tap(find.byKey(ValueKey('check-${block.id}')));
      await tester.pump();
      await tester.pump();
      expect(blocksOfWednesday(store).single.isDone, isTrue);
      expect(find.byType(CheckBurst), findsNothing);
      await tester.pumpAndSettle();
    });
  });

  group('the border of a block', () {
    Finder dashes(String blockId) => find.descendant(
      of: blockFinder(blockId),
      matching: find.byType(DashedBorder),
    );
    // The full border in the colour of the priority, if the block has one.
    Finder outline(String blockId, Color color) => find.descendant(
      of: blockFinder(blockId),
      matching: find.byWidgetPredicate(
        (w) =>
            w is DecoratedBox &&
            w.position == DecorationPosition.foreground &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).border ==
                Border.all(color: color, width: PriorityColors.borderWidth),
      ),
    );

    testWidgets('a task block has dashes, an event has none', (tester) async {
      final store = plannerStore();
      final task = addBlock(store, 'Write report', asEvent: false);
      final event = addBlock(store, 'Lunch', start: 840);
      await pumpPlanner(tester, store);

      expect(dashes(task.id), findsOneWidget);
      expect(dashes(event.id), findsNothing);
    });

    testWidgets('a task block with a priority has a full border in the '
        'colour of the priority, and no dashes', (tester) async {
      final store = plannerStore();
      final block = addBlock(store, 'Write report', asEvent: false);
      store.editTask(
        block.taskId!,
        (t) => t.copyWith(priority: 3),
        name: 'Priority',
      );
      await pumpPlanner(tester, store);

      expect(outline(block.id, PriorityColors.high), findsOneWidget);
      expect(dashes(block.id), findsNothing);
    });

    testWidgets('a done block with a priority has the dashes again', (
      tester,
    ) async {
      final store = plannerStore();
      final block = addBlock(store, 'Write report', asEvent: false);
      store.editTask(
        block.taskId!,
        (t) => t.copyWith(priority: 3),
        name: 'Priority',
      );
      store.toggleDone(taskId: block.taskId!);
      await pumpPlanner(tester, store);

      expect(outline(block.id, PriorityColors.high), findsNothing);
      expect(dashes(block.id), findsOneWidget);
    });
  });

  group('a change of layout', () {
    /// "Late" stands alone. Then a block that starts before it comes under
    /// it, and "Late" moves to the right.
    PlannerBlock late(AppStore store) =>
        addBlock(store, 'Late', start: 11 * 60 + 30);
    void putBlockUnder(AppStore store) =>
        addBlock(store, 'Early', start: 11 * 60, length: 120);

    testWidgets('moves a block with an animation of 220 ms', (tester) async {
      final store = plannerStore(motion: true);
      final block = late(store);
      await pumpMoving(tester, store);
      final before = tester.getRect(blockFinder(block.id));

      putBlockUnder(store);
      await tester.pump();
      final moving = tester.widget<AnimatedPositioned>(blockFinder(block.id));
      expect(moving.duration, const Duration(milliseconds: 220));
      expect(moving.curve, Curves.easeOutCubic);
      // The first frame: the block is still at its old place.
      expect(tester.getRect(blockFinder(block.id)), before);

      // On the way.
      await tester.pump(const Duration(milliseconds: 60));
      final early = tester.getRect(blockFinder(block.id));
      await tester.pump(const Duration(milliseconds: 60));
      final later = tester.getRect(blockFinder(block.id));
      expect(early.left, greaterThan(before.left));
      expect(later.left, greaterThan(early.left));
      // Ease-out: the first half of the time goes more than half the way.
      expect(early.left - before.left, greaterThan(later.left - early.left));

      // At 220 ms it is there, and it stays.
      await tester.pump(const Duration(milliseconds: 100));
      final end = tester.getRect(blockFinder(block.id));
      expect(end.left, greaterThan(later.left));
      expect(end.top, before.top);
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.getRect(blockFinder(block.id)), end);
      expect(tester.takeException(), isNull);
    });

    testWidgets('with motion off the block is at its new place at once', (
      tester,
    ) async {
      final store = plannerStore();
      final block = late(store);
      await pumpPlanner(tester, store);
      final before = tester.getRect(blockFinder(block.id));

      putBlockUnder(store);
      await tester.pump();
      expect(
        tester.widget<AnimatedPositioned>(blockFinder(block.id)).duration,
        Duration.zero,
      );
      final after = tester.getRect(blockFinder(block.id));
      expect(after.left, greaterThan(before.left));

      // Nothing moves after the first frame.
      await tester.pump(const Duration(milliseconds: 110));
      expect(tester.getRect(blockFinder(block.id)), after);
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.getRect(blockFinder(block.id)), after);
    });

    testWidgets('both end at the same place', (tester) async {
      final still = plannerStore();
      final a = late(still);
      await pumpPlanner(tester, still);
      putBlockUnder(still);
      await tester.pump();
      final atOnce = tester.getRect(blockFinder(a.id));

      final moving = plannerStore(motion: true);
      final b = late(moving);
      await pumpMoving(tester, moving);
      putBlockUnder(moving);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 220));
      expect(tester.getRect(blockFinder(b.id)), atOnce);
    });
  });

  group('the live label', () {
    testWidgets('shows the new times and the length during a move', (
      tester,
    ) async {
      final store = plannerStore();
      addBlock(store, 'Lunch', start: 10 * 60, length: 90);
      await pumpPlanner(tester, store);

      final from = pointAt(tester, wednesday, 10 * 60 + 30);
      final gesture = await tester.startGesture(
        from,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      // 30 minutes down.
      await gesture.moveTo(from + const Offset(0, hour / 2));
      await tester.pump();
      expect(liveLabel(tester), '10:30 – 12:00 · 1h 30m');
      // 75 minutes down: the words of PLAN §4.
      await gesture.moveTo(from + const Offset(0, hour * 1.25));
      await tester.pump();
      expect(liveLabel(tester), '11:15 – 12:45 · 1h 30m');
      expect(
        liveLabel(tester),
        PlannerMath.label(start: 11 * 60 + 15, end: 12 * 60 + 45),
      );
      // Between two steps the label shows the step, not the pointer.
      await gesture.moveTo(from + const Offset(0, hour * 1.25 + 5));
      await tester.pump();
      expect(liveLabel(tester), '11:15 – 12:45 · 1h 30m');

      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('live-label')), findsNothing);
      expect(blockNamed(store, 'Lunch').startMinute, 11 * 60 + 15);
    });

    testWidgets('shows the new end and the new length during a resize', (
      tester,
    ) async {
      final store = plannerStore();
      final block = addBlock(store, 'Lunch', start: 10 * 60, length: 90);
      await pumpPlanner(tester, store);

      final from = tester.getCenter(
        find.byKey(ValueKey('resizeBottom-${block.id}')),
      );
      final gesture = await tester.startGesture(
        from,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await gesture.moveTo(from + const Offset(0, hour / 4));
      await tester.pump();
      await gesture.moveTo(from + const Offset(0, hour / 2));
      await tester.pump();
      expect(liveLabel(tester), '10:00 – 12:00 · 2h');

      await gesture.up();
      await tester.pumpAndSettle();
      expect(blockNamed(store, 'Lunch').endMinute, 12 * 60);
    });
  });

  group('the pointer', () {
    testWidgets('is the resize pointer over the top and the bottom edge of '
        'a block', (tester) async {
      final store = plannerStore();
      final block = addBlock(store, 'Lunch');
      await pumpPlanner(tester, store);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(5, 5));
      addTearDown(mouse.removePointer);
      final rect = tester.getRect(blockFinder(block.id));

      await mouse.moveTo(rect.topCenter + const Offset(0, 2));
      await tester.pump();
      expect(mouseCursor(), SystemMouseCursors.resizeUpDown);

      // The middle of the block is the hand that moves it.
      await mouse.moveTo(rect.center);
      await tester.pump();
      expect(mouseCursor(), SystemMouseCursors.grab);

      await mouse.moveTo(rect.bottomCenter - const Offset(0, 2));
      await tester.pump();
      expect(mouseCursor(), SystemMouseCursors.resizeUpDown);

      // Off the block it is not the resize pointer.
      await mouse.moveTo(pointAt(tester, wednesday, 14 * 60));
      await tester.pump();
      expect(mouseCursor(), isNot(SystemMouseCursors.resizeUpDown));
      await tester.pump(const Duration(seconds: 1));
    });
  });

  group('the haptic tick', () {
    testWidgets('a phone ticks once at each snap of a move', (tester) async {
      final store = plannerStore();
      addBlock(store, 'Lunch');
      final ticks = listenForHaptics(tester);
      await pumpPlanner(tester, store, size: phoneSize);

      final from = pointAt(tester, wednesday, 11 * 60 + 30);
      final finger = await tester.startGesture(from);
      await tester.pump(const Duration(milliseconds: 600));
      ticks.clear();

      // Less than half a step: no snap, no tick.
      await finger.moveTo(from + const Offset(0, 5));
      await tester.pump();
      expect(ticks, isEmpty);

      // One step of 15 minutes is 16 points.
      await finger.moveTo(from + const Offset(0, 16));
      await tester.pump();
      expect(ticks, ['HapticFeedbackType.selectionClick']);

      // More of the same step: no new tick.
      await finger.moveTo(from + const Offset(0, 20));
      await tester.pump();
      expect(ticks, hasLength(1));

      await finger.moveTo(from + const Offset(0, 32));
      await tester.pump();
      await finger.moveTo(from + const Offset(0, 48));
      await tester.pump();
      expect(ticks, hasLength(3));
      expect(ticks.toSet(), {'HapticFeedbackType.selectionClick'});

      await finger.up();
      await tester.pumpAndSettle();
      expect(blockNamed(store, 'Lunch').startMinute, 11 * 60 + 45);
      expect(ticks, hasLength(3));
    });

    testWidgets('a phone ticks at each snap of a resize', (tester) async {
      final store = plannerStore();
      final block = addBlock(store, 'Lunch');
      final ticks = listenForHaptics(tester);
      await pumpPlanner(tester, store, size: phoneSize);

      final from = tester.getCenter(
        find.byKey(ValueKey('resizeBottom-${block.id}')),
      );
      final finger = await tester.startGesture(from);
      await tester.pump();
      ticks.clear();
      await finger.moveTo(from + const Offset(0, 16));
      await tester.pump();
      await finger.moveTo(from + const Offset(0, 32));
      await tester.pump();
      expect(ticks, hasLength(2));

      await finger.up();
      await tester.pumpAndSettle();
      expect(blockNamed(store, 'Lunch').endMinute, 12 * 60 + 30);
    });
  });

  group('the strip of tasks with no time', () {
    Finder cell(DayKey day) =>
        find.byKey(ValueKey('sticky-cell-${day.string}'));
    Finder sticky(String taskId) => find.byKey(ValueKey('sticky-$taskId'));

    testWidgets('a task dropped on the strip of a day gets that day and no '
        'time', (tester) async {
      final store = plannerStore();
      final task = store.quickAdd(
        'Call the bank',
        placement: TaskPlacement.day(wednesday),
      )!;
      final friday = wednesday.adding(days: 2);
      await pumpPlanner(tester, store);
      expect(
        find.descendant(of: cell(wednesday), matching: sticky(task.id)),
        findsOneWidget,
      );

      final from = tester.getCenter(sticky(task.id));
      final to = tester.getCenter(cell(friday));
      await mouseDrag(tester, from, to - from);

      expect(store.task(task.id)!.planDate, friday);
      expect(store.task(task.id)!.bucket, TaskBucket.day);
      // No block: the task has a day and no time.
      expect(
        store.blocks(
          DayRange(wednesday.adding(days: -7), wednesday.adding(days: 7)),
        ),
        isEmpty,
      );
      expect(
        find.descendant(of: cell(friday), matching: sticky(task.id)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: cell(wednesday), matching: sticky(task.id)),
        findsNothing,
      );
      expect(store.toast, 'Planned for Fri 9 Oct');
      await endToast(tester);
    });

    testWidgets('a task from the list at the side can be dropped there too', (
      tester,
    ) async {
      final store = plannerStore()..leftPane = LeftPane.tasks;
      // A task of the inbox: it has no day yet.
      final task = store.quickAdd('Buy bread')!;
      final thursday = wednesday.adding(days: 1);
      await pumpPlanner(tester, store);
      expect(store.task(task.id)!.planDate, isNull);

      final row = find.byKey(ValueKey('task-${task.id}'));
      expect(row, findsOneWidget);
      final from = tester.getCenter(row);
      final to = tester.getCenter(cell(thursday));
      await mouseDrag(tester, from, to - from);

      expect(store.task(task.id)!.planDate, thursday);
      expect(store.blocks(DayRange.single(thursday)), isEmpty);
      expect(
        find.descendant(of: cell(thursday), matching: sticky(task.id)),
        findsOneWidget,
      );
      await endToast(tester);
    });

    testWidgets('a task held over a day tints that day and no other, and the '
        'drop makes the block', (tester) async {
      final store = plannerStore();
      final task = store.quickAdd(
        'Call the bank',
        placement: TaskPlacement.day(wednesday),
      )!;
      final thursday = wednesday.adding(days: 1);
      final friday = wednesday.adding(days: 2);
      await pumpPlanner(tester, store);
      final accent = GroveTheme.of(tester.element(columnFinder(wednesday)))
          .accent;
      Finder dropTint(DayKey day) => find.descendant(
        of: columnFinder(day),
        matching: find.byWidgetPredicate(
          (w) => w is ColoredBox && w.color == accent.withValues(alpha: 0.10),
        ),
      );
      expect(dropTint(wednesday), findsNothing);
      expect(dropTint(friday), findsNothing);

      final from = tester.getCenter(sticky(task.id));
      final mouse = await tester.startGesture(
        from,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      final over = pointAt(tester, friday, 10 * 60);
      for (var i = 1; i <= 8; i++) {
        await mouse.moveTo(from + (over - from) * (i / 8));
        await tester.pump(const Duration(milliseconds: 16));
      }
      // The whole column of the day has the tint, and it is the only one.
      expect(dropTint(friday), findsOneWidget);
      expect(
        tester.getRect(dropTint(friday)),
        tester.getRect(columnFinder(friday)),
      );
      expect(dropTint(wednesday), findsNothing);
      expect(dropTint(thursday), findsNothing);
      // The task has no block before the drop.
      expect(store.blocks(DayRange.single(friday)), isEmpty);

      // The pointer goes to the day before: the tint goes with it.
      await mouse.moveTo(pointAt(tester, thursday, 10 * 60));
      await tester.pump(const Duration(milliseconds: 16));
      expect(dropTint(thursday), findsOneWidget);
      expect(dropTint(friday), findsNothing);

      await mouse.up();
      await tester.pumpAndSettle();
      expect(dropTint(thursday), findsNothing);
      final made = store.blocks(DayRange.single(thursday));
      expect(made, hasLength(1));
      expect(made.single.taskId, task.id);
      await endToast(tester);
    });

    testWidgets('a click on a sticky note opens the task', (tester) async {
      final store = plannerStore();
      final task = store.quickAdd(
        'Call the bank',
        placement: TaskPlacement.day(wednesday),
      )!;
      await pumpPlanner(tester, store);
      expect(find.byType(TaskInspector), findsNothing);

      await mouseTap(
        tester,
        tester.getCenter(
          find.descendant(
            of: sticky(task.id),
            matching: find.text('Call the bank'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(store.selectedTaskId, task.id);
      expect(find.byType(TaskInspector), findsOneWidget);
      // The click gave the task no time.
      expect(blocksOfWednesday(store), isEmpty);
      expect(sticky(task.id), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('goal blocks', () {
    testWidgets('a tap on the check box marks the goal block done', (
      tester,
    ) async {
      final store = plannerStore();
      final id = goalBlock(store);
      await pumpPlanner(tester, store);
      expect(blocksOfWednesday(store).single.isDone, isFalse);

      await tester.tap(find.byKey(ValueKey('check-$id')));
      await tester.pumpAndSettle();

      final block = blocksOfWednesday(store).single;
      expect(block.id, id);
      expect(block.isGoalBlock, isTrue);
      expect(block.isDone, isTrue);
      expect(store.undoName, 'Complete Goal Block');
      // The time of the block did not change.
      expect(block.startMinute, 11 * 60);
      expect(block.length, 90);
      // The done time counts for the goal.
      expect(
        store.goalProgress(store.goals().single.id, weekOf: wednesday).done,
        90,
      );
      expect(faceOpacity(tester, id), 0.55);

      // One more tap opens it again.
      await tester.tap(find.byKey(ValueKey('check-$id')));
      await tester.pumpAndSettle();
      expect(blocksOfWednesday(store).single.isDone, isFalse);
      expect(store.undoName, 'Reopen Goal Block');
    });

    testWidgets('"Duration" in the menu gives a goal block a new length', (
      tester,
    ) async {
      final store = plannerStore();
      final id = goalBlock(store);
      await pumpPlanner(tester, store);
      final before = tester.getSize(blockFinder(id)).height;

      await rightClick(tester, pointAt(tester, wednesday, 11 * 60 + 45));
      expect(menuLine('Delete Goal Block'), findsOneWidget);
      await pick(tester, 'Duration');
      await pick(tester, '45m');

      final block = blocksOfWednesday(store).single;
      expect(block.id, id);
      expect(block.isGoalBlock, isTrue);
      expect(block.startMinute, 11 * 60);
      expect(block.endMinute, 11 * 60 + 45);
      expect(store.undoName, 'Change Duration');
      expect(tester.getSize(blockFinder(id)).height, before - hour * 0.75);

      // Undo gives the 90 minutes back.
      store.undo();
      await tester.pumpAndSettle();
      expect(blocksOfWednesday(store).single.length, 90);
      await endToast(tester);
    });
  });

  group('the header', () {
    testWidgets('"Previous" moves one week back', (tester) async {
      final store = plannerStore();
      await pumpPlanner(tester, store);

      await tester.tap(find.bySemanticsLabel('Previous'));
      await tester.pumpAndSettle();
      expect(store.selectedDay, wednesday.adding(days: -7));
      expect(find.text('28 Sep – 4 Oct 2026'), findsOneWidget);
      expect(columnFinder(d('2026-09-28')), findsOneWidget);
      expect(columnFinder(wednesday), findsNothing);

      await tester.tap(find.bySemanticsLabel('Previous'));
      await tester.pumpAndSettle();
      expect(store.selectedDay, wednesday.adding(days: -14));
      expect(find.text('21 Sep – 27 Sep 2026'), findsOneWidget);
    });

    testWidgets('"Previous" moves one day back on a phone', (tester) async {
      final store = plannerStore();
      await pumpPlanner(tester, store, size: phoneSize);

      await tester.tap(find.bySemanticsLabel('Previous'));
      await tester.pumpAndSettle();
      expect(store.selectedDay, wednesday.adding(days: -1));
      expect(columnFinder(wednesday.adding(days: -1)), findsOneWidget);
      expect(columnFinder(wednesday), findsNothing);
    });

    testWidgets('"Note for the day" opens the daily note of the day', (
      tester,
    ) async {
      final store = plannerStore();
      await pumpPlanner(tester, store);
      expect(store.existingDailyNote(wednesday), isNull);
      expect(find.byTooltip("Today's note"), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Note for the day'));
      await tester.pumpAndSettle();

      final note = store.existingDailyNote(wednesday);
      expect(note, isNotNull);
      expect(note!.kind, NoteKind.daily);
      expect(note.date, wednesday);
      expect(store.screen, Screen.notes);
      expect(store.selectedNoteId, note.id);
      expect(tester.takeException(), isNull);
    });

    testWidgets('"Note for the day" opens the note of the day in view, not '
        'of today', (tester) async {
      final store = plannerStore();
      final friday = wednesday.adding(days: 2);
      store.selectedDay = friday;
      await pumpPlanner(tester, store);
      expect(find.byTooltip('Note for Friday 9 Oct'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Note for the day'));
      await tester.pumpAndSettle();

      final note = store.existingDailyNote(friday);
      expect(note, isNotNull);
      expect(store.existingDailyNote(wednesday), isNull);
      expect(store.screen, Screen.notes);
      expect(store.selectedNoteId, note!.id);
    });
  });

  group('plan my day', () {
    testWidgets('Cancel closes the list and changes nothing', (tester) async {
      final store = plannerStore();
      final bank = store.quickAdd(
        'Call the bank',
        placement: TaskPlacement.day(wednesday),
      )!;
      final bread = store.quickAdd(
        'Buy bread',
        placement: TaskPlacement.day(wednesday),
      )!;
      final undoBefore = store.undoName;
      await pumpPlanner(tester, store);

      await tester.tap(find.byKey(const ValueKey('plan-my-day')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Grove will place these tasks'),
        findsOneWidget,
      );

      await tester.tap(find.bySemanticsLabel('Cancel'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Grove will place these tasks'), findsNothing);
      expect(find.byKey(const ValueKey('plan-apply')), findsNothing);
      expect(blocksOfWednesday(store), isEmpty);
      expect(store.undoName, undoBefore);
      expect(store.undoName, isNot('Plan My Day'));
      // The two tasks still wait in the strip.
      expect(find.byKey(ValueKey('sticky-${bank.id}')), findsOneWidget);
      expect(find.byKey(ValueKey('sticky-${bread.id}')), findsOneWidget);
      expect(store.task(bank.id)!.planDate, wednesday);
    });
  });

  group('what a screen reader hears', () {
    testWidgets('a block says its title and its times', (tester) async {
      final handle = tester.ensureSemantics();
      final store = plannerStore();
      final block = addBlock(store, 'Lunch', start: 11 * 60 + 15, length: 90);
      await pumpPlanner(tester, store);

      final node = tester.getSemantics(blockFinder(block.id));
      expect(node.label, 'Lunch · 11:15 – 12:45 · 1h 30m');
      expect(node.flagsCollection.isButton, isTrue);
      expect(find.bySemanticsLabel(node.label), findsOneWidget);
      handle.dispose();
    });

    testWidgets('a goal block says that it is one', (tester) async {
      final handle = tester.ensureSemantics();
      final store = plannerStore();
      final id = goalBlock(store);
      await pumpPlanner(tester, store);

      final node = tester.getSemantics(blockFinder(id));
      expect(node.label, 'Goal block · Read · 11:00 – 12:30 · 1h 30m');
      handle.dispose();
    });
  });
}
