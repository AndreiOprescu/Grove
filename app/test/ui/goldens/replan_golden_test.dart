// Golden screenshots of the window of "Reorganise rest of day", over Today.
//
// Make the pictures again after a wanted change of the look:
//   cd app && flutter test --update-goldens test/ui/goldens
import 'package:flutter/material.dart' hide Row;
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/ui/store_app.dart';

import '../planner/planner_support.dart';
import '../tasks/tasks_support.dart' show addTask, textOffPixels;

/// Today at 10:20 with the sleep line at 13:00: a block of a task, two tasks
/// with no time and a task with a deadline. One of them does not fit.
AppStore _store() {
  final store = plannerStore(now: 10 * 60 + 20)..screen = Screen.today;
  store
    ..createFromDraft(
      title: 'Stand-up',
      day: wednesday,
      start: 11 * 60,
      end: 11 * 60 + 30,
      asEvent: true,
    )
    ..createFromDraft(
      title: 'Write the report',
      day: wednesday,
      start: 9 * 60,
      end: 10 * 60 + 30,
      asEvent: false,
    );
  addTask(store, 'Water the ferns', id: 'FERNS', estimateMin: 15);
  addTask(store, 'Call the plumber', id: 'PLUMBER', estimateMin: 30);
  addTask(
    store,
    'Send the invoice',
    id: 'INVOICE',
    estimateMin: 60,
    due: '2026-10-28',
  );
  store
    ..addDayMarker(DayMarkerKind.sleep, wednesday)
    ..moveDayMarker(DayMarkerKind.sleep, wednesday, 13 * 60);
  store.selection = {};
  return store;
}

/// The window over Today, with "Write the report" 40% done.
Future<void> _replanShot(
  WidgetTester tester,
  String name, {
  Size size = desktopSize,
}) => withRealShadows(() async {
  final store = _store();
  await pumpPlanner(tester, store, size: size);
  await tester.tap(find.byKey(const ValueKey('replan-day')));
  await tester.pumpAndSettle();
  final report = blockNamed(store, 'Write the report').taskId!;
  final field = find.descendant(
    of: find.byKey(ValueKey('replan-field-$report')),
    matching: find.byType(EditableText),
  );
  await tester.enterText(field, '40');
  await tester.testTextInput.receiveAction(TextInputAction.done);
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  // A text on a part of a pixel looks different on each system.
  expect(textOffPixels(tester, within: find.byType(Dialog)), isEmpty);
  await expectLater(find.byType(StoreApp), matchesGoldenFile('$name.png'));
});

void main() {
  setUpAll(() async {
    TolerantGoldenComparator.install();
    await loadIconFont();
  });

  testWidgets('replan desktop grove', (tester) async {
    await _replanShot(tester, 'replan_desktop_grove_light');
  });

  testWidgets('replan phone grove', (tester) async {
    await _replanShot(tester, 'replan_phone_grove_light', size: phoneSize);
  });
}
