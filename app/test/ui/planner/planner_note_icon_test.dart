// The note icon on a block (PLAN §5.1.2: "a small ✎ icon if linked notes
// exist"). The view draws it when the block says it has a note.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/ui/planner/block_view.dart';

import '../tasks/tasks_support.dart' show pumpPane;
import 'planner_support.dart';

PlannerBlock noteBlock({
  bool hasNote = true,
  int minutes = 60,
  String? taskId,
  String? goalId,
}) => PlannerBlock(
  id: 'b1',
  title: 'Design review',
  day: wednesday,
  startMinute: 9 * 60,
  endMinute: 9 * 60 + minutes,
  kind: EventKind.block,
  taskId: taskId,
  goalId: goalId,
  isDone: false,
  color: 'accent',
  isRecurring: false,
  hasNote: hasNote,
);

Future<void> pumpBlock(
  WidgetTester tester,
  PlannerBlock block, {
  double width = 200,
}) {
  final size = Size(width, block.length / 60 * hour - 1);
  return pumpPane(
    tester,
    Align(
      alignment: Alignment.topLeft,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: BlockView(
          block: block,
          start: block.startMinute,
          end: block.endMinute,
          size: size,
          isOverlay: false,
          isSelected: false,
          isDragging: false,
          isRenaming: false,
          onTap: () {},
          onToggleDone: () {},
          onRename: (_) {},
          onCancelRename: () {},
          onDragStart: (_, _) {},
          onDragUpdate: (_) {},
          onDragEnd: () {},
          onMenu: (_) {},
        ),
      ),
    ),
    size: const Size(400, 300),
  );
}

final noteIcon = find.byKey(const ValueKey('block-note-b1'));

final heard = find.bySemanticsLabel(RegExp('Has a linked note'));

void main() {
  testWidgets('a block with a linked note shows the note icon', (tester) async {
    await pumpBlock(tester, noteBlock());

    expect(noteIcon, findsOneWidget);
    // A screen reader says it with the block.
    expect(heard, findsOneWidget);
    // It is small, and inside the block.
    final icon = tester.getRect(noteIcon);
    final block = tester.getRect(find.byType(BlockView));
    expect(icon.width, lessThanOrEqualTo(12));
    expect(block.contains(icon.topLeft), isTrue);
    expect(block.contains(icon.bottomRight), isTrue);
    // The time and the title are still there.
    expect(find.textContaining('9:00'), findsOneWidget);
    expect(find.text('Design review'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a block with no linked note shows no icon', (tester) async {
    await pumpBlock(tester, noteBlock(hasNote: false));

    expect(noteIcon, findsNothing);
    expect(heard, findsNothing);
  });

  testWidgets('a task block and a goal block show it too', (tester) async {
    await pumpBlock(tester, noteBlock(taskId: 't1'));
    expect(noteIcon, findsOneWidget);

    await pumpBlock(tester, noteBlock(goalId: 'g1'));
    expect(noteIcon, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a short block shows it in its one line', (tester) async {
    await pumpBlock(tester, noteBlock(minutes: 15));

    expect(noteIcon, findsOneWidget);
    final icon = tester.getRect(noteIcon);
    final title = tester.getRect(find.text('Design review'));
    // After the title, on the same line.
    expect(icon.left, greaterThanOrEqualTo(title.left));
    expect(icon.center.dy, closeTo(title.center.dy, 2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a narrow block leaves the icon out: the title comes first', (
    tester,
  ) async {
    await pumpBlock(tester, noteBlock(), width: 60);
    expect(noteIcon, findsNothing);
    expect(find.text('Design review'), findsOneWidget);

    await pumpBlock(tester, noteBlock(minutes: 15), width: 60);
    expect(noteIcon, findsNothing);
    expect(find.text('Design review'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
