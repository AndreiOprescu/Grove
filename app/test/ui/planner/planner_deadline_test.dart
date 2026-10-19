// A deadline on the Planner: a small flag in the block, and a tick box that
// ticks the deadline done.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'planner_note_icon_test.dart' show pumpBlock;
import 'planner_support.dart';

PlannerBlock deadlineBlock({int minutes = 60, bool isDone = false}) =>
    PlannerBlock(
      id: 'b1',
      title: 'Essay',
      day: wednesday,
      startMinute: 9 * 60,
      endMinute: 9 * 60 + minutes,
      kind: EventKind.event,
      isDone: isDone,
      color: 'accent',
      isRecurring: false,
      isDeadline: true,
    );

final flag = find.byKey(const ValueKey('block-deadline-b1'));
final check = find.byKey(const ValueKey('check-b1'));

void main() {
  testWidgets('a deadline block shows a flag and a tick box', (tester) async {
    await pumpBlock(tester, deadlineBlock());
    expect(flag, findsOneWidget);
    expect(check, findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Deadline')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a short deadline block still shows the flag', (tester) async {
    await pumpBlock(tester, deadlineBlock(minutes: 20));
    expect(flag, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a plain event block has no flag and no tick box', (
    tester,
  ) async {
    await pumpBlock(
      tester,
      PlannerBlock(
        id: 'b1',
        title: 'Lunch',
        day: wednesday,
        startMinute: 9 * 60,
        endMinute: 10 * 60,
        kind: EventKind.event,
        isDone: false,
        color: 'accent',
        isRecurring: false,
      ),
    );
    expect(flag, findsNothing);
    expect(check, findsNothing);
  });
}
