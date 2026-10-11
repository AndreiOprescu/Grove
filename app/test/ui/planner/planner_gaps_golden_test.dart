// Golden screenshots of the planner parts that came after F7: the subtasks
// of a goal block with their window, the pencil of a block with a linked
// note, and the focus timer.
//
// Make the pictures again after a wanted change of the look:
//   cd app && flutter test --update-goldens test/ui/planner
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/ui/planner/block_subtask_editor.dart';
import 'package:grove/ui/planner/focus_card.dart';
import 'package:grove/ui/planner/planner_grid.dart';
import 'package:grove/ui/planner/planner_kind.dart';
import 'package:grove/ui/planner/planner_view.dart';
import 'package:grove/ui/store_app.dart';

import '../tasks/tasks_support.dart' show pumpPane, textOffPixels;
import 'planner_support.dart';

void main() {
  setUpAll(() async {
    TolerantGoldenComparator.install();
    await loadIconFont();
  });

  testWidgets('a goal block with subtasks and their window', (tester) async {
    await withRealShadows(() async {
      final store = plannerStore(now: 10 * 60 + 20);
      // On Monday: the window in the middle does not hide the two blocks.
      final monday = wednesday.adding(days: -2);
      final tall = goalBlock(store, day: monday, start: 570, length: 120);
      final short = goalBlock(store, day: monday, start: 12 * 60, length: 30);
      final names = ['Chapter 3', 'Chapter 4', 'Notes', 'Summary', 'Quiz'];
      for (final name in names) {
        store.addBlockSubtask(to: tall, title: name);
      }
      store
        ..toggleBlockSubtask(store.blockSubtasks(tall).first.id)
        ..addBlockSubtask(to: short, title: 'Chapter 5')
        ..addBlockSubtask(to: short, title: 'Chapter 6');
      await pumpPlanner(tester, store);
      store.openBlockSubtasks(tall);
      await tester.pumpAndSettle();

      expect(
        textOffPixels(tester, within: find.byType(BlockSubtaskEditor)),
        isEmpty,
      );
      await expectLater(
        find.byType(StoreApp),
        matchesGoldenFile('goldens/planner_subtasks_grove_light.png'),
      );
    });
  });

  // The linked note of a block is its meeting note (card Q-35).
  testWidgets('blocks with a linked note have the pencil', (tester) async {
    await withRealShadows(() async {
      final store = plannerStore(now: 10 * 60 + 20);
      String add(String title, int start, int length, {bool asEvent = false}) {
        store.createFromDraft(
          title: title,
          day: wednesday,
          start: start,
          end: start + length,
          asEvent: asEvent,
        );
        return blockNamed(store, title).id;
      }

      final noted = [
        add('Team sync', 9 * 60 + 30, 45, asEvent: true),
        add('Write report', 10 * 60 + 30, 60),
        goalBlock(store, start: 12 * 60, length: 90),
        add('Call Sam', 15 * 60, 15),
      ];
      add('Lunch', 14 * 60, 45);
      for (final id in noted) {
        store.createMeetingNote(store.event(id)!);
      }
      store
        ..selection = {}
        ..selectedTaskId = null
        ..screen = Screen.planner;
      // The planner with no shell around it: a new look of the top strip
      // does not change this picture.
      await pumpPane(
        tester,
        PlannerView(store: store, kind: PlannerKind.week),
        size: const Size(1100, 560),
      );

      for (final id in noted) {
        expect(find.byKey(ValueKey('block-note-$id')), findsOneWidget);
      }
      expect(textOffPixels(tester, within: find.byType(PlannerGrid)), isEmpty);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/planner_linked_note_grove_light.png'),
      );
    });
  });

  testWidgets('the focus timer asks "Mark done?" over the planner', (
    tester,
  ) async {
    await withRealShadows(() async {
      final store = focusStore();
      final id = hourBlock(store, 'Write report');
      setFocusClock(tester, 10, 59, 59);
      await pumpPlanner(tester, store);
      store.startFocus(store.event(id)!);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text('Time is up. Mark done?'), findsOneWidget);

      expect(textOffPixels(tester, within: find.byType(FocusCard)), isEmpty);
      await expectLater(
        find.byType(StoreApp),
        matchesGoldenFile('goldens/planner_focus_done_grove_light.png'),
      );
    });
  });

  // The three faces of the card: the count down, the question for a task,
  // and the end of a block with no task.
  for (final (name, themeId, brightness) in [
    ('grove_light', ThemeId.grove, Brightness.light),
    ('futuristic_dark', ThemeId.futuristic, Brightness.dark),
  ]) {
    testWidgets('the focus card, $name', (tester) async {
      await withRealShadows(() async {
        final store = focusStore();
        FocusSession session({String? taskId, bool finished = false}) =>
            FocusSession(
              blockId: 'b1',
              taskId: taskId,
              title: 'Write report',
              day: focusDay,
              start: DateTime(2099, 3, 4, 10),
              end: DateTime(2099, 3, 4, 11),
              finished: finished,
            );
        setFocusClock(tester, 10, 35);
        await pumpPane(
          tester,
          Padding(
            padding: const EdgeInsets.all(20),
            child: Wrap(
              spacing: 20,
              children: [
                FocusCard(
                  store: store,
                  session: session(taskId: 't1'),
                ),
                FocusCard(
                  store: store,
                  session: session(taskId: 't1', finished: true),
                ),
                FocusCard(store: store, session: session(finished: true)),
              ],
            ),
          ),
          size: const Size(790, 190),
          themeId: themeId,
          brightness: brightness,
        );
        expect(find.text('25:00'), findsOneWidget);

        expect(textOffPixels(tester), isEmpty);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/focus_card_$name.png'),
        );
      });
    });
  }
}
