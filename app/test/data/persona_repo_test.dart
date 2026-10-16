import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:grove/core/model/goal.dart';
import 'package:grove/core/model/task.dart';
import 'package:grove/core/services/persona.dart';
import 'package:grove/data/data.dart';

import 'helpers.dart';

// The persona (shared migration 10): the skills, the rewards on tasks and
// goals, and the earnings log. An earning stays when its task is gone.

RewardItem taskReward(String task, String skill, int points) => RewardItem(
  id: PersonaRules.taskRewardId(task, skill),
  taskId: task,
  skillId: skill,
  points: points,
);

EarningItem earning(String task, String skill, int points, String at) =>
    EarningItem(
      id: PersonaRules.earningId(EarningSource.task, task, skill),
      skillId: skill,
      points: points,
      source: EarningSource.task,
      sourceId: task,
      title: 'Gym',
      earnedAt: at,
    );

void main() {
  group('skills', () {
    test('a new database has the 8 built-in skills, in order', () {
      final r = makeRepos();
      expect(r.skills.all().map((s) => s.id), [
        for (final s in PersonaRules.builtins) s.id,
      ]);
      expect(r.skills.all().every((s) => s.builtin && !s.hidden), isTrue);
    });

    test('there are ten migrations: the seven of the Mac app, and three of '
        'this app only', () {
      final db = makeRepos().db;
      expect(Migrations.all.length, 10);
      expect(db.userVersion, 10);
    });

    test('a skill can be renamed, hidden and added', () {
      final r = makeRepos();
      final mind = r.skills.get('skill-mind')!;
      r.skills.save(mind.copyWith(name: 'Brain', hidden: true));
      r.skills.save(SkillItem(id: 'S9', name: 'Cooking', sort: 9));
      final all = r.skills.all();
      expect(all.length, 9);
      expect(r.skills.get('skill-mind')!.name, 'Brain');
      expect(r.skills.get('skill-mind')!.hidden, isTrue);
      expect(all.last.name, 'Cooking');
      expect(all.last.builtin, isFalse);
    });

    test('the built-in skills are not in the outbox: a seed never wins over '
        'a rename from another device', () {
      final r = makeRepos();
      final stamps = r.db.query(
        "SELECT stamp FROM outbox WHERE tbl = 'skills'",
        const [],
        (row) => row.asInt(0),
      );
      expect(stamps, isEmpty);
      r.skills.save(r.skills.get('skill-mind')!.copyWith(name: 'Brain'));
      expect(
        r.db.query(
          "SELECT pk FROM outbox WHERE tbl = 'skills'",
          const [],
          (row) => row.text(0),
        ),
        ['skill-mind'],
      );
    });

    test('upgrading a version 9 database adds the built-in skills', () {
      final dir = tempDir('grove-m10-');
      final path = oldDatabase(dir, 9, '');
      final r = Repos(Database.open(path));
      expect(r.skills.all().length, 8);
      final stamps = r.db.query(
        "SELECT stamp FROM outbox WHERE tbl = 'skills'",
        const [],
        (row) => row.asInt(0),
      );
      expect(stamps, isEmpty);
      r.db.close();
    });
  });

  group('rewards', () {
    test('a task has its rewards, a goal has its own', () {
      final r = makeRepos();
      r.tasks.save(TaskItem(id: 't1', title: 'Gym'));
      r.goals.upsert(GoalItem(id: 'g1', title: 'Read'));
      r.rewards.save(taskReward('t1', 'skill-strength', 10));
      r.rewards.save(taskReward('t1', 'skill-health', 5));
      r.rewards.save(
        RewardItem(
          id: PersonaRules.goalRewardId('g1', 'skill-mind'),
          goalId: 'g1',
          skillId: 'skill-mind',
          points: 20,
        ),
      );
      expect(r.rewards.forTask('t1').map((x) => x.points), [10, 5]);
      expect(r.rewards.forGoal('g1').single.points, 20);
      expect(r.rewards.forTask('nope'), isEmpty);
    });

    test('saving a reward again changes its points', () {
      final r = makeRepos();
      r.tasks.save(TaskItem(id: 't1', title: 'Gym'));
      r.rewards.save(taskReward('t1', 'skill-strength', 10));
      r.rewards.save(taskReward('t1', 'skill-strength', 15));
      expect(r.rewards.forTask('t1').single.points, 15);
    });

    test('deleting the task deletes its rewards', () {
      final r = makeRepos();
      r.tasks.save(TaskItem(id: 't1', title: 'Gym'));
      r.rewards.save(taskReward('t1', 'skill-strength', 10));
      r.tasks.delete('t1');
      expect(r.rewards.forTask('t1'), isEmpty);
    });

    test('rewards of many tasks in one query', () {
      final r = makeRepos();
      r.tasks.save(TaskItem(id: 't1', title: 'Gym'));
      r.tasks.save(TaskItem(id: 't2', title: 'Call'));
      r.rewards.save(taskReward('t1', 'skill-strength', 10));
      r.rewards.save(taskReward('t2', 'skill-social', 5));
      final by = r.rewards.forTasks(['t1', 't2', 't3']);
      expect(by.keys.toSet(), {'t1', 't2'});
    });
  });

  group('earnings', () {
    test('points add up by skill', () {
      final r = makeRepos();
      r.earnings.save(
        earning('t1', 'skill-strength', 10, '2026-10-15T09:00:00'),
      );
      r.earnings.save(
        earning('t2', 'skill-strength', 5, '2026-10-15T10:00:00'),
      );
      r.earnings.save(earning('t2', 'skill-health', 3, '2026-10-15T10:00:00'));
      expect(r.earnings.pointsBySkill(), {
        'skill-strength': 15,
        'skill-health': 3,
      });
    });

    test('the newest earnings come first', () {
      final r = makeRepos();
      r.earnings.save(
        earning('t1', 'skill-strength', 10, '2026-10-15T09:00:00'),
      );
      r.earnings.save(earning('t2', 'skill-mind', 5, '2026-10-15T10:00:00'));
      expect(r.earnings.recent(limit: 1).single.sourceId, 't2');
    });

    test('the earnings of one tick are found by their source', () {
      final r = makeRepos();
      r.earnings.save(
        earning('t1', 'skill-strength', 10, '2026-10-15T09:00:00'),
      );
      r.earnings.save(earning('t1', 'skill-health', 2, '2026-10-15T09:00:00'));
      expect(r.earnings.forSource(EarningSource.task, 't1').length, 2);
      expect(r.earnings.forSource(EarningSource.goalBlock, 't1'), isEmpty);
    });

    test('deleting the task keeps its earnings', () {
      final r = makeRepos();
      r.tasks.save(TaskItem(id: 't1', title: 'Gym'));
      r.earnings.save(
        earning('t1', 'skill-strength', 10, '2026-10-15T09:00:00'),
      );
      r.tasks.delete('t1');
      expect(r.earnings.pointsBySkill(), {'skill-strength': 10});
    });
  });

  group('export', () {
    test('the file has the skills, the rewards and the earnings', () {
      final r = makeRepos();
      r.tasks.save(TaskItem(id: 't1', title: 'Gym'));
      r.rewards.save(taskReward('t1', 'skill-strength', 10));
      r.earnings.save(
        earning('t1', 'skill-strength', 10, '2026-10-15T09:00:00'),
      );
      final obj = jsonDecode(DataExport.export(r.db)) as Map<String, Object?>;
      expect(obj['schema'], 10);
      final tables = obj['tables'] as Map;
      expect((tables['skills'] as List).length, 8);
      expect((tables['rewards'] as List).length, 1);
      expect((tables['earnings'] as List).length, 1);

      final b = makeRepos();
      DataExport.importData(DataExport.export(r.db), b);
      expect(b.earnings.pointsBySkill(), {'skill-strength': 10});
      expect(b.rewards.forTask('t1').single.points, 10);
    });

    test('an older file with no skills gets the built-in skills back', () {
      final r = makeRepos();
      r.tasks.save(TaskItem(id: 't1', title: 'Gym'));
      final obj = jsonDecode(DataExport.export(r.db)) as Map<String, Object?>;
      final tables = obj['tables'] as Map;
      tables
        ..remove('skills')
        ..remove('rewards')
        ..remove('earnings');
      obj['schema'] = 9;
      final b = makeRepos();
      DataExport.importData(jsonEncode(obj), b);
      expect(b.skills.all().length, 8);
      expect(b.tasks.get('t1'), isNotNull);
    });

    test('the tables come after what they point at', () {
      final t = DataExport.tables;
      expect(t.indexOf('skills'), lessThan(t.indexOf('rewards')));
      expect(t.indexOf('skills'), lessThan(t.indexOf('earnings')));
      expect(t.indexOf('tasks'), lessThan(t.indexOf('rewards')));
      expect(t.indexOf('goals'), lessThan(t.indexOf('rewards')));
    });
  });
}
