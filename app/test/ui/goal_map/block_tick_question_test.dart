// The tick of a block that holds open squares asks about each one.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/ui/goal_map/block_tick_question.dart';

import '../tasks/tasks_support.dart';

Finder byKey(String key) => find.byKey(ValueKey(key));

class Scene {
  Scene(this.store) : goal = store.addProject(title: 'Trip')! {
    final root = GoalSquare.rootIdOf(goal.id);
    book = store.addSquare(parentId: root, title: 'Book')!.id;
    pack = store.addSquare(parentId: root, title: 'Pack')!.id;
    store.scheduleSquare(
      squareId: book,
      day: wednesday,
      start: 12 * 60,
      length: 60,
    );
    block = store.selection.single;
    store.addSquareToBlock(squareId: pack, eventId: block);
  }

  final AppStore store;
  final GoalItem goal;
  late final String book;
  late final String pack;
  late final String block;
}

Future<Scene> pumpScene(WidgetTester tester) async {
  final scene = Scene(paneStore());
  await pumpPane(
    tester,
    Builder(
      builder: (context) => Center(
        child: GestureDetector(
          key: const ValueKey('tick'),
          behavior: HitTestBehavior.opaque,
          onTap: () =>
              unawaited(tickGoalBlock(context, scene.store, scene.block)),
          child: const SizedBox.square(dimension: 60),
        ),
      ),
    ),
    size: const Size(800, 700),
  );
  return scene;
}

void main() {
  testWidgets('a block with no squares gets its tick with no question', (
    tester,
  ) async {
    final store = paneStore();
    final goal = store.addGoal(
      title: 'Read',
      kind: GoalKind.hours,
      target: 60,
    )!;
    store.scheduleGoal(
      goalId: goal.id,
      day: wednesday,
      start: 12 * 60,
      length: 60,
    );
    final id = store.blocks(DayRange.single(wednesday)).single.id;
    await pumpPane(
      tester,
      Builder(
        builder: (context) => Center(
          child: GestureDetector(
            key: const ValueKey('tick'),
            behavior: HitTestBehavior.opaque,
            onTap: () => unawaited(tickGoalBlock(context, store, id)),
            child: const SizedBox.square(dimension: 60),
          ),
        ),
      ),
    );
    await tester.tap(byKey('tick'));
    await tester.pumpAndSettle();
    expect(find.text('How did it go?'), findsNothing);
    expect(store.event(id)!.doneAt, isNotNull);
  });

  testWidgets('it asks for each square, with Done as the first answer', (
    tester,
  ) async {
    final s = await pumpScene(tester);
    await tester.tap(byKey('tick'));
    await tester.pumpAndSettle();
    expect(find.text('How did it go?'), findsOneWidget);
    expect(find.text('Book'), findsOneWidget);
    expect(find.text('Pack'), findsOneWidget);

    await tester.tap(byKey('tick-question-save'));
    await tester.pumpAndSettle();
    expect(s.store.event(s.block)!.doneAt, isNotNull);
    expect(s.store.goalSquare(s.book)!.isDone, isTrue);
    expect(s.store.goalSquare(s.pack)!.isDone, isTrue);
  });

  testWidgets('each square gets its own answer, and one undo takes all back', (
    tester,
  ) async {
    final s = await pumpScene(tester);
    await tester.tap(byKey('tick'));
    await tester.pumpAndSettle();
    await tester.tap(byKey('tick-answer-${s.book}-startWaiting'));
    await tester.pumpAndSettle();
    expect(byKey('tick-wait-${s.book}'), findsOneWidget);
    await tester.tap(byKey('tick-answer-${s.pack}-notYet'));
    await tester.pumpAndSettle();
    await tester.tap(byKey('tick-question-save'));
    await tester.pumpAndSettle();

    expect(s.store.event(s.block)!.doneAt, isNotNull);
    final book = s.store.goalSquare(s.book)!;
    expect(book.isWaiting, isTrue);
    expect(book.waitMinutes, 3 * 24 * 60);
    expect(s.store.goalSquare(s.pack)!.isDone, isFalse);

    s.store.undo();
    await tester.pumpAndSettle();
    expect(s.store.event(s.block)!.doneAt, isNull);
    expect(s.store.goalSquare(s.book)!.isWaiting, isFalse);
    // The line that says what the undo did goes away by itself.
    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets('cancel leaves all as it was', (tester) async {
    final s = await pumpScene(tester);
    await tester.tap(byKey('tick'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(s.store.event(s.block)!.doneAt, isNull);
    expect(s.store.goalSquare(s.book)!.isDone, isFalse);
  });

  testWidgets('a block with a tick loses it with no question', (tester) async {
    final s = await pumpScene(tester);
    s.store.answerBlockTick(
      eventId: s.block,
      answers: {s.book: SquareAnswer.done, s.pack: SquareAnswer.notYet},
    );
    await tester.pump();
    await tester.tap(byKey('tick'));
    await tester.pumpAndSettle();
    expect(find.text('How did it go?'), findsNothing);
    expect(s.store.event(s.block)!.doneAt, isNull);
  });

  testWidgets('the root as Done with steps left asks first. No keeps it open', (
    tester,
  ) async {
    final s = await pumpScene(tester);
    final root = GoalSquare.rootIdOf(s.goal.id);
    s.store.addSquareToBlock(squareId: root, eventId: s.block);
    await tester.tap(byKey('tick'));
    await tester.pumpAndSettle();
    expect(byKey('tick-answer-$root-startWaiting'), findsNothing);
    await tester.tap(byKey('tick-answer-${s.pack}-notYet'));
    await tester.pumpAndSettle();
    await tester.tap(byKey('tick-question-save'));
    await tester.pumpAndSettle();

    expect(find.text('1 step is still open. Finish anyway?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(s.store.isProjectFinished(s.goal.id), isFalse);
    expect(s.store.event(s.block)!.doneAt, isNotNull);
    expect(s.store.goalSquare(s.book)!.isDone, isTrue);
  });
}
