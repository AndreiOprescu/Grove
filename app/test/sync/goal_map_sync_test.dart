import 'package:flutter_test/flutter_test.dart';
import 'package:grove/core/goals/goal_graph.dart';

import 'support.dart';

// Goal maps (shared schema 15) sync like every other row. Sync merges rows
// and knows nothing of the map, so two devices can together make a map that
// neither made: a loop, a lost square or a stale habit row. The map must stand
// on both devices, and be the same.

const goalId = 'G';
final root = GoalSquare.rootIdOf(goalId);

SquareLink l(String child, String parent) =>
    SquareLink(childId: child, parentId: parent);

GoalItem project(Device d) {
  final g = GoalItem(id: goalId, title: 'Delft', type: GoalType.project);
  d.repos.goals.upsert(g);
  d.repos.goalSquares.save(
    GoalSquare(id: root, goalId: goalId, title: 'Delft'),
  );
  return g;
}

void square(Device d, String id, {String? parent}) {
  d.repos.goalSquares.save(GoalSquare(id: id, goalId: goalId, title: id));
  d.repos.goalSquares.addLink(l(id, parent ?? root));
}

GoalGraph graphOf(Device d) => GoalGraph.build(
  goalId,
  d.repos.goalSquares.forGoal(goalId),
  d.repos.goalSquares.linksForGoal(goalId),
);

void main() {
  late MemoryRemote remote;
  late Device a, b;

  setUp(() {
    remote = MemoryRemote();
    a = Device(remote);
    b = Device(remote);
  });

  group('The schema', () {
    test('the tables are synced and exported, after what they point at', () {
      const tables = SyncMigrations.syncedTables;
      final squares = tables.indexOf('goal_squares');
      expect(squares, greaterThan(tables.indexOf('goals')));
      expect(tables.indexOf('square_links'), greaterThan(squares));
      expect(tables.indexOf('square_blocks'), greaterThan(squares));
      expect(
        tables.indexOf('square_blocks'),
        greaterThan(tables.indexOf('events')),
      );
      expect(DataExport.tables, tables);
      expect(SyncMigrations.addedColumns['goal_squares'], {
        'deleted',
        'user_id',
      });
      expect(SyncMigrations.addedColumns['square_links'], {
        'deleted',
        'user_id',
        'updated_at',
      });
    });

    test('the SQL for Supabase has the tables and the goal columns', () {
      final sql = supabaseSql(RemoteSchema.read(a.db));
      for (final t in ['goal_squares', 'square_links', 'square_blocks']) {
        expect(sql, contains('create table if not exists public."$t" ('));
      }
      for (final c in ['done_when', 'work_minutes', 'due_day', 'why']) {
        expect(sql, contains(c), reason: c);
      }
    });

    test('a link table can be repaired: it has a rowid', () {
      for (final t in ['square_links', 'square_blocks']) {
        expect(
          a.db.query('SELECT rowid FROM $t', const [], (r) => r.value(0)),
          isEmpty,
          reason: t,
        );
      }
    });
  });

  group('Upgrade', () {
    test(
      'an old remote goal row with empty columns reads as a habit',
      () async {
        a.repos.goals.upsert(GoalItem(id: goalId, title: 'Read'));
        a.db.execute(
          'UPDATE goals SET type = NULL, done_when = NULL, why = NULL',
        );
        await settle([a, b]);
        final got = b.repos.goals.get(goalId)!;
        expect(got.type, GoalType.habit);
        expect(got.title, 'Read');
      },
    );
  });

  group('Two devices', () {
    test('a whole map reaches the other device', () async {
      project(a);
      square(a, 'write');
      square(a, 'read', parent: 'write');
      final e = EventItem(
        title: 'Block',
        start: at('2026-11-05T10:00'),
        end: at('2026-11-05T11:00'),
        kind: EventKind.block,
        goalId: goalId,
      );
      a.repos.events.save(e);
      a.repos.goalSquares.addBlock('read', e.id);
      await settle([a, b]);
      expectSame([a, b]);
      expect(b.repos.goals.get(goalId)!.isProject, isTrue);
      expect(graphOf(b).childrenOf('write'), ['read']);
      expect(b.repos.goalSquares.blocksOf('read'), [e.id]);
    });

    test('two devices that together make a loop get the same map, with no '
        'loop', () async {
      project(a);
      square(a, 'x');
      square(a, 'y');
      await settle([a, b]);
      a.later();
      a.repos.goalSquares.addLink(l('x', 'y'));
      b.later();
      b.repos.goalSquares.addLink(l('y', 'x'));
      await settle([a, b]);
      expectSame([a, b]);
      for (final d in [a, b]) {
        final g = graphOf(d);
        expect(g.droppedLinks, isNotEmpty);
        expect(g.reachesRoot('x'), isTrue);
        expect(g.reachesRoot('y'), isTrue);
        expect(g.ranks.length, 3);
      }
      expect(graphOf(a).droppedLinks, graphOf(b).droppedLinks);
    });

    test('a square deleted on one device while the other links to it leaves '
        'no lost square', () async {
      project(a);
      square(a, 'x');
      square(a, 'y');
      await settle([a, b]);
      a.later();
      a.repos.goalSquares.delete('x');
      b.later();
      b.repos.goalSquares.addLink(l('y', 'x'));
      await settle([a, b]);
      expectSame([a, b]);
      for (final d in [a, b]) {
        expect(graphOf(d).reachesRoot('y'), isTrue);
      }
    });

    test('a square edited after the other device deleted it comes back '
        'loose', () async {
      project(a);
      square(a, 'mid');
      square(a, 'x', parent: 'mid');
      await settle([a, b]);
      a.later();
      a.repos.goalSquares.delete('x');
      b.later();
      b.repos.goalSquares.save(
        b.repos.goalSquares.get('x')!.copyWith(title: 'Edited'),
      );
      await settle([a, b]);
      expectSame([a, b]);
      for (final d in [a, b]) {
        final g = graphOf(d);
        expect(g.square('x').title, 'Edited');
        // Its link went with the delete, so it has no line now.
        expect(g.isLoose('x'), isTrue);
      }
    });

    test('the length of a square reaches the other device', () async {
      project(a);
      square(a, 'x');
      await settle([a, b]);
      a.repos.goalSquares.save(
        a.repos.goalSquares.get('x')!.copyWith(lengthMinutes: 45),
      );
      await settle([a, b]);
      expectSame([a, b]);
      expect(b.repos.goalSquares.get('x')!.lengthMinutes, 45);
    });

    test('two devices that make it a project reach the same rows', () async {
      final g = GoalItem(id: goalId, title: 'Delft');
      a.repos.goals.upsert(g);
      a.repos.goalSubtasks.save(
        GoalSubtaskItem(id: 's', goalId: goalId, title: 'Read'),
      );
      await settle([a, b]);
      a.later();
      a.repos.goalSquares.convert(g);
      b.later();
      b.repos.goalSquares.convert(b.repos.goals.get(goalId)!);
      await settle([a, b]);
      a.repos.goalSquares.heal();
      b.repos.goalSquares.heal();
      await settle([a, b]);
      expectSame([a, b]);
      expect(a.repos.goalSquares.forGoal(goalId), hasLength(2));
      expect(a.repos.goalSubtasks.forGoal(goalId), isEmpty);
      expect(graphOf(a).childrenOf(root), ['sq:s']);
    });

    test('a device that did not know saves the goal: the heal keeps the '
        'project', () async {
      final g = GoalItem(id: goalId, title: 'Delft');
      a.repos.goals.upsert(g);
      await settle([a, b]);
      a.later();
      a.repos.goalSquares.convert(g);
      b.later();
      b.repos.goals.upsert(b.repos.goals.get(goalId)!.copyWith(title: 'New'));
      await settle([a, b]);
      expect(a.repos.goals.get(goalId)!.type, GoalType.habit);
      a.repos.goalSquares.heal();
      b.repos.goalSquares.heal();
      await settle([a, b]);
      expectSame([a, b]);
      final got = b.repos.goals.get(goalId)!;
      expect(got.isProject, isTrue);
      expect(got.title, 'New');
    });

    test('a subtask added by a device that did not know becomes a square '
        'on both', () async {
      final g = GoalItem(id: goalId, title: 'Delft');
      a.repos.goals.upsert(g);
      await settle([a, b]);
      a.later();
      a.repos.goalSquares.convert(g);
      b.later();
      b.repos.goalSubtasks.save(
        GoalSubtaskItem(id: 'late', goalId: goalId, title: 'Late'),
      );
      await settle([a, b]);
      a.repos.goalSquares.heal();
      b.repos.goalSquares.heal();
      await settle([a, b]);
      expectSame([a, b]);
      expect(a.repos.goalSubtasks.forGoal(goalId), isEmpty);
      expect(graphOf(b).childrenOf(root), ['sq:late']);
    });

    test(
      'deleting the goal on one device takes the whole map on both',
      () async {
        project(a);
        square(a, 'x');
        await settle([a, b]);
        b.later();
        b.repos.goals.delete(goalId);
        await settle([a, b]);
        expectSame([a, b]);
        expect(a.repos.goalSquares.forGoal(goalId), isEmpty);
        expect(a.repos.goalSquares.linksForGoal(goalId), isEmpty);
      },
    );
  });
}
