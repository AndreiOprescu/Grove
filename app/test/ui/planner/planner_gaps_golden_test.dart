// Golden screenshots of the planner parts that came after F7: the subtasks
// of a goal block with their window, and the focus timer.
//
// Make the pictures again after a wanted change of the look:
//   cd app && flutter test --update-goldens test/ui/planner
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/ui/planner/block_subtask_editor.dart';
import 'package:grove/ui/store_app.dart';

import '../tasks/tasks_support.dart' show textOffPixels;
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
}
