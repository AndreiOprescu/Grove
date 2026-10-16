import 'package:flutter_test/flutter_test.dart';
import 'package:grove/core/services/persona.dart';

import 'support.dart';

// The persona: ticking a task or a goal block done pays the points of its
// reward to the skills. Un-ticking takes them back. The points are a log:
// a later change of the reward, or deleting the task, does not change them.

// 2026-10-05 is a Monday.
final monday = d('2026-10-05');

int points(AppStore s, String skill) => s.skillPoints[skill] ?? 0;

const strength = 'skill-strength';
const health = 'skill-health';
const mind = 'skill-mind';

/// A task "Gym" that gives 10 Strength and 5 Health.
TaskItem gym(AppStore s) {
  final t = s.quickAdd('Gym')!;
  s.setTaskReward(taskId: t.id, skillId: strength, points: 10);
  s.setTaskReward(taskId: t.id, skillId: health, points: 5);
  return t;
}

void main() {
  group('Skills', () {
    test('a new Grove has the 8 skills, all at level 1 with no points', () {
      final s = makeStore();
      expect(s.skills.length, 8);
      expect(s.skillPoints, isEmpty);
      expect(s.skillLevel(strength).level, 1);
      expect(s.personaLevel.level, 1);
    });

    test('a skill can be added, renamed and hidden; undo works', () {
      final s = makeStore();
      final id = s.addSkill('  Cooking ')!;
      expect(s.skills.last.name, 'Cooking');
      expect(s.addSkill('   '), isNull);
      s.renameSkill(id, 'Kitchen');
      expect(s.skills.last.name, 'Kitchen');
      s.setSkillHidden(mind, hidden: true);
      expect(s.visibleSkills.map((x) => x.id), isNot(contains(mind)));
      expect(s.skills.map((x) => x.id), contains(mind));
      s.undo();
      expect(s.visibleSkills.map((x) => x.id), contains(mind));
    });

    test('the persona has a name; "You" when none is set', () {
      final s = makeStore();
      expect(s.personaName, 'You');
      s.renamePersona('  Andrei  ');
      expect(s.personaName, 'Andrei');
      s.undo();
      expect(s.personaName, 'You');
    });
  });

  group('Rewards', () {
    test('a task keeps a list of skills and points', () {
      final s = makeStore();
      final t = gym(s);
      expect(s.taskRewards(t.id).map((r) => (r.skillId, r.points)), [
        (strength, 10),
        (health, 5),
      ]);
    });

    test('setting the same skill again changes the points; 0 removes it', () {
      final s = makeStore();
      final t = gym(s);
      s.setTaskReward(taskId: t.id, skillId: strength, points: 20);
      expect(s.taskRewards(t.id).first.points, 20);
      s.setTaskReward(taskId: t.id, skillId: strength, points: 0);
      expect(s.taskRewards(t.id).map((r) => r.skillId), [health]);
    });

    test('points stay at most 999', () {
      final s = makeStore();
      final t = s.quickAdd('Gym')!;
      s.setTaskReward(taskId: t.id, skillId: strength, points: 5000);
      expect(s.taskRewards(t.id).single.points, 999);
    });

    test('a reward change is one undo step', () {
      final s = makeStore();
      final t = gym(s);
      s.undo();
      expect(s.taskRewards(t.id).map((r) => r.skillId), [strength]);
    });

    test('deleting a task deletes its rewards; undo brings them back', () {
      final s = makeStore();
      final t = gym(s);
      s.deleteTask(t.id);
      expect(s.taskRewards(t.id), isEmpty);
      s.undo();
      expect(s.taskRewards(t.id).length, 2);
    });
  });

  group('Ticking a task', () {
    test('ticking pays the points; un-ticking takes them back', () {
      final s = makeStore();
      final t = gym(s);
      s.toggleDone(taskId: t.id);
      expect(points(s, strength), 10);
      expect(points(s, health), 5);
      s.toggleDone(taskId: t.id);
      expect(points(s, strength), 0);
      expect(s.recentEarnings(), isEmpty);
    });

    test('undo of the tick takes the points back; redo pays again', () {
      final s = makeStore();
      final t = gym(s);
      s.toggleDone(taskId: t.id);
      s.undo();
      expect(points(s, strength), 0);
      s.redo();
      expect(points(s, strength), 10);
    });

    test('a task with no reward pays nothing', () {
      final s = makeStore();
      final t = s.quickAdd('Read mail')!;
      s.toggleDone(taskId: t.id);
      expect(s.skillPoints, isEmpty);
    });

    test('the log says the task title and the points', () {
      final s = makeStore();
      final t = gym(s);
      s.toggleDone(taskId: t.id);
      final log = s.recentEarnings();
      expect(log.map((e) => (e.title, e.points)).toSet(), {
        ('Gym', 10),
        ('Gym', 5),
      });
      expect(log.first.source, EarningSource.task);
    });

    test('a later change of the reward does not change old points', () {
      final s = makeStore();
      final t = gym(s);
      s.toggleDone(taskId: t.id);
      s.setTaskReward(taskId: t.id, skillId: strength, points: 50);
      expect(points(s, strength), 10);
    });

    test('deleting a done task keeps its points', () {
      final s = makeStore();
      final t = gym(s);
      s.toggleDone(taskId: t.id);
      s.deleteTask(t.id);
      expect(points(s, strength), 10);
    });

    test('a repeating task: the next copy has the same reward', () {
      final s = makeStore(clock: WallTime(day: monday, minute: 600));
      final t = s.quickAdd('Gym every day')!;
      s.setTaskReward(taskId: t.id, skillId: strength, points: 10);
      s.toggleDone(taskId: t.id);
      final next = s.repos.tasks.all().firstWhere(
        (x) => x.id != t.id && x.title == t.title,
      );
      expect(s.taskRewards(next.id).single.points, 10);
      s.toggleDone(taskId: next.id);
      expect(points(s, strength), 20);
    });

    test('ticking pays a hidden skill too', () {
      final s = makeStore();
      final t = gym(s);
      s.setSkillHidden(strength, hidden: true);
      s.toggleDone(taskId: t.id);
      expect(points(s, strength), 10);
    });
  });

  group('Ticking a goal block', () {
    /// A goal "Gym" that gives 10 Strength per hour, and a block of it on
    /// Monday 10:00 of [length] minutes. Gives the goal and the block id.
    (GoalItem, String) gymBlock(AppStore s, {int length = 90}) {
      final g = s.addGoal(title: 'Gym')!;
      s.setGoalReward(goalId: g.id, skillId: strength, points: 10);
      s.scheduleGoal(goalId: g.id, day: monday, start: 600, length: length);
      return (g, s.selection.single);
    }

    test('a block pays the points per hour, by its length', () {
      final s = makeStore();
      final (_, block) = gymBlock(s);
      s.toggleGoalBlockDone(eventId: block);
      expect(points(s, strength), 15);
      expect(s.recentEarnings().single.source, EarningSource.goalBlock);
      expect(s.recentEarnings().single.title, 'Gym');
    });

    test('un-ticking the block takes the points back', () {
      final s = makeStore();
      final (_, block) = gymBlock(s, length: 60);
      s.toggleGoalBlockDone(eventId: block);
      s.toggleGoalBlockDone(eventId: block);
      expect(points(s, strength), 0);
    });

    test('a very short block can pay 0, and then there is no log line', () {
      final s = makeStore();
      final g = s.addGoal(title: 'Gym')!;
      s.setGoalReward(goalId: g.id, skillId: strength, points: 1);
      s.scheduleGoal(goalId: g.id, day: monday, start: 600, length: 15);
      s.toggleGoalBlockDone(eventId: s.selection.single);
      expect(s.recentEarnings(), isEmpty);
    });

    test('deleting the goal keeps the points of its done blocks', () {
      final s = makeStore();
      final (g, block) = gymBlock(s, length: 60);
      s.toggleGoalBlockDone(eventId: block);
      s.deleteGoal(g.id);
      expect(points(s, strength), 10);
      expect(s.goalRewards(g.id), isEmpty);
      s.undo();
      expect(s.goalRewards(g.id).single.points, 10);
      expect(points(s, strength), 10);
    });

    test('goal subtasks pay nothing', () {
      final s = makeStore();
      final (g, _) = gymBlock(s);
      final sub = s.addGoalSubtask(to: g.id, title: 'Legs')!;
      s.toggleGoalSubtask(sub);
      expect(s.skillPoints, isEmpty);
    });
  });

  group('Levels', () {
    test('a tick that crosses a level shows the level-up', () {
      final s = makeStore();
      final t = s.quickAdd('Marathon')!;
      s.setTaskReward(taskId: t.id, skillId: strength, points: 60);
      expect(s.levelUp, isNull);
      s.toggleDone(taskId: t.id);
      expect(s.skillLevel(strength).level, 2);
      expect(s.levelUp?.skillName, 'Strength');
      expect(s.levelUp?.level, 2);
    });

    test('a tick that stays in the level shows nothing', () {
      final s = makeStore();
      final t = gym(s);
      s.toggleDone(taskId: t.id);
      expect(s.levelUp, isNull);
    });

    test('the persona level counts all the points', () {
      final s = makeStore();
      final t = s.quickAdd('Big day')!;
      s.setTaskReward(taskId: t.id, skillId: strength, points: 200);
      s.setTaskReward(taskId: t.id, skillId: mind, points: 40);
      s.toggleDone(taskId: t.id);
      expect(s.personaLevel.level, 2);
    });
  });

  group('Days', () {
    const now = WallTime(day: DayKey('2026-10-16'), minute: 600);

    test('the bars count the moods of the daily notes in the span', () {
      final s = makeStore(clock: now);
      s.setMood(s.dailyNote(d('2026-10-01')).id, Mood.sun);
      s.setMood(s.dailyNote(d('2026-10-02')).id, Mood.sun);
      s.setMood(s.dailyNote(d('2026-10-03')).id, Mood.rain);
      s.setMood(s.dailyNote(d('2026-09-30')).id, Mood.cloud);
      final month = s.dayCounts(DaySpan.month);
      expect(month.of(Mood.sun), 2);
      expect(month.of(Mood.cloud), 0);
      expect(month.of(Mood.rain), 1);
      expect(s.dayCounts(DaySpan.all).of(Mood.cloud), 1);
      expect(s.dayCounts(DaySpan.all).total, 4);
    });

    test("today's mood is set from the Persona screen; undo works", () {
      final s = makeStore(clock: now);
      expect(s.todayMood, isNull);
      expect(s.existingDailyNote(now.day), isNull);
      s.setTodayMood(Mood.sun);
      expect(s.todayMood, Mood.sun);
      expect(s.existingDailyNote(now.day)?.mood, 3);
      expect(s.dayCounts(DaySpan.month).of(Mood.sun), 1);
      s.setTodayMood(Mood.sun);
      expect(s.todayMood, isNull);
      s.undo();
      expect(s.todayMood, Mood.sun);
    });

    test('the span is this month first, and it is kept', () {
      final prefs = MemoryPrefs();
      final s = makeStore(clock: now, prefs: prefs);
      expect(s.daySpan, DaySpan.month);
      s.setDaySpan(DaySpan.all);
      expect(s.daySpan, DaySpan.all);
      expect(makeStore(prefs: prefs).daySpan, DaySpan.all);
    });
  });
}
