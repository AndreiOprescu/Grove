// "Fit" on a sticky note: the new block grows in. With motion off it is
// there at once.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/ui/store_app.dart';

import 'planner_support.dart';

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

Finder growOf(String blockId) => find.byKey(ValueKey('grow-$blockId'));

/// How far the block has grown: (opacity, scale). Both are 1 at the end.
(double, double) grown(WidgetTester tester, String blockId) {
  final fade = tester.widget<FadeTransition>(
    find
        .descendant(of: growOf(blockId), matching: find.byType(FadeTransition))
        .first,
  );
  final scale = tester.widget<ScaleTransition>(
    find
        .descendant(of: growOf(blockId), matching: find.byType(ScaleTransition))
        .first,
  );
  return (fade.opacity.value, scale.scale.value);
}

void main() {
  testWidgets('the block of "Fit" grows in', (tester) async {
    final store = plannerStore(motion: true);
    final task = store.quickAdd(
      'Call the bank',
      placement: TaskPlacement.day(wednesday),
    )!;
    await pumpMoving(tester, store);

    await tester.tap(find.byKey(ValueKey('fit-${task.id}')));
    await tester.pump();
    final block = store.blocks(DayRange.single(wednesday)).single;
    expect(block.taskId, task.id);
    expect(blockFinder(block.id), findsOneWidget);
    expect(growOf(block.id), findsOneWidget);

    // Small and faint at first.
    await tester.pump(const Duration(milliseconds: 16));
    final (fade, scale) = grown(tester, block.id);
    expect(fade, lessThan(0.6));
    expect(scale, lessThan(0.97));
    expect(scale, greaterThanOrEqualTo(0.85));

    // Bigger a moment later.
    await tester.pump(const Duration(milliseconds: 80));
    final (fade2, scale2) = grown(tester, block.id);
    expect(fade2, greaterThan(fade));
    expect(scale2, greaterThan(scale));

    // Then at its full size, at its place on the grid.
    await tester.pump(const Duration(milliseconds: 300));
    expect(grown(tester, block.id), (1.0, 1.0));
    final rect = tester.getRect(blockFinder(block.id));
    expect(
      rect.top,
      closeTo(pointAt(tester, wednesday, block.startMinute).dy, 0.5),
    );
    expect(rect.height, closeTo(block.length / 60 * hour - 1, 0.5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('"Fit in Next Gap" in the menu of a note grows the block in '
      'too', (tester) async {
    final store = plannerStore(motion: true);
    final task = store.quickAdd(
      'Call the bank',
      placement: TaskPlacement.day(wednesday),
    )!;
    await pumpMoving(tester, store);

    await tester.tapAt(
      tester.getCenter(find.byKey(ValueKey('sticky-${task.id}'))),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Fit in Next Gap'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    final block = store.blocks(DayRange.single(wednesday)).single;
    expect(growOf(block.id), findsOneWidget);
    expect(grown(tester, block.id).$1, lessThan(1));
    await tester.pump(const Duration(milliseconds: 600));
    expect(grown(tester, block.id), (1.0, 1.0));
  });

  testWidgets('with motion off the block is there at once', (tester) async {
    final store = plannerStore();
    final task = store.quickAdd(
      'Call the bank',
      placement: TaskPlacement.day(wednesday),
    )!;
    await pumpPlanner(tester, store);

    await tester.tap(find.byKey(ValueKey('fit-${task.id}')));
    await tester.pump();

    final block = store.blocks(DayRange.single(wednesday)).single;
    expect(blockFinder(block.id), findsOneWidget);
    expect(growOf(block.id), findsNothing);
    expect(
      tester.getSize(blockFinder(block.id)).height,
      closeTo(block.length / 60 * hour - 1, 0.5),
    );
  });

  testWidgets('a block that is made by a drag does not grow in', (
    tester,
  ) async {
    final store = plannerStore(motion: true);
    await pumpMoving(tester, store);

    final from = pointAt(tester, wednesday, 12 * 60);
    final gesture = await tester.startGesture(
      from,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    for (var i = 1; i <= 4; i++) {
      await gesture.moveTo(from + Offset(0, hour * i / 4));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('planner-draft')),
        matching: find.byType(EditableText),
      ),
      'Write report',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    final block = blockNamed(store, 'Write report');
    expect(blockFinder(block.id), findsOneWidget);
    expect(growOf(block.id), findsNothing);
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('no free time: a message, and nothing grows', (tester) async {
    // 23:45: no half hour is left in the day.
    final store = plannerStore(now: 23 * 60 + 45, motion: true);
    final task = store.quickAdd(
      'Call the bank',
      placement: TaskPlacement.day(wednesday),
    )!;
    await pumpMoving(tester, store);

    await tester.tap(find.byKey(ValueKey('fit-${task.id}')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    expect(store.blocks(DayRange.single(wednesday)), isEmpty);
    expect(find.byKey(ValueKey('sticky-${task.id}')), findsOneWidget);
    expect(find.textContaining('No free gap'), findsOneWidget);
    // Let the message go away.
    await tester.pump(const Duration(milliseconds: 2500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a block that comes back with Undo does not grow in again', (
    tester,
  ) async {
    final store = plannerStore(motion: true);
    final task = store.quickAdd(
      'Call the bank',
      placement: TaskPlacement.day(wednesday),
    )!;
    await pumpMoving(tester, store);
    await tester.tap(find.byKey(ValueKey('fit-${task.id}')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final block = store.blocks(DayRange.single(wednesday)).single;
    expect(growOf(block.id), findsOneWidget);

    store.deleteBlocks([block.id], name: 'Unschedule');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(blockFinder(block.id), findsNothing);
    store.undo();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    expect(blockFinder(block.id), findsOneWidget);
    expect(growOf(block.id), findsNothing);
    // Let the message of Undo go away.
    await tester.pump(const Duration(milliseconds: 2500));
    await tester.pump(const Duration(milliseconds: 500));
  });
}
