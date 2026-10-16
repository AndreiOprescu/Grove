import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

// The persona (tables `skills`, `rewards` and `earnings`, shared migration
// 10) syncs like every other row. The 8 built-in skills are on every device
// from the start: they are never sent, so a new device never wins over a
// rename made on another one (ADR 0003).

const strength = 'skill-strength';

List<String> skillNames(Device d) => [
  for (final s in d.repos.skills.all()) s.name,
];

TaskItem gymTask(Repos r) {
  final t = TaskItem(id: 'GYM', title: 'Gym');
  r.tasks.save(t);
  return t;
}

EarningItem gymEarning() => EarningItem(
  id: PersonaRules.earningId(EarningSource.task, 'GYM', strength),
  skillId: strength,
  points: 10,
  source: EarningSource.task,
  sourceId: 'GYM',
  title: 'Gym',
  earnedAt: '2026-10-15T09:00:00',
);

void main() {
  late MemoryRemote remote;
  late Device a, b;

  setUp(() {
    remote = MemoryRemote();
    a = Device(remote);
    b = Device(remote);
  });

  test(
    'the built-in skills are never sent, and no device has them twice',
    () async {
      expect(a.waiting.where((w) => w.startsWith('skills')), isEmpty);
      await settle([a, b]);
      expect(remoteRows(remote, 'skills'), isEmpty);
      for (final d in [a, b]) {
        expect(d.repos.skills.all().length, 8);
      }
      expectSame([a, b]);
    },
  );

  test('a rename wins over the built-in skill of a new device', () async {
    a.later();
    a.repos.skills.save(
      a.repos.skills.get(strength)!.copyWith(name: 'Fitness'),
    );
    await a.sync();
    expect(remoteRows(remote, 'skills'), ['$strength saved']);

    // A device that starts after the rename.
    final c = Device(remote);
    await settle([a, b, c]);
    for (final d in [a, b, c]) {
      expect(skillNames(d).first, 'Fitness');
    }
    expectSame([a, b, c]);
  });

  test('a new skill, a hidden skill, a reward and an earning reach the other '
      'device', () async {
    a.later();
    final cooking = SkillItem(name: 'Cooking', sort: 9);
    a.repos.skills.save(cooking);
    a.repos.skills.save(
      a.repos.skills.get('skill-money')!.copyWith(hidden: true),
    );
    gymTask(a.repos);
    a.repos.rewards.save(
      RewardItem(
        id: PersonaRules.taskRewardId('GYM', strength),
        taskId: 'GYM',
        skillId: strength,
        points: 10,
      ),
    );
    a.repos.earnings.save(gymEarning());
    await settle([a, b]);

    expect(skillNames(b).last, 'Cooking');
    expect(b.repos.skills.get('skill-money')!.hidden, isTrue);
    expect(b.repos.rewards.forTask('GYM').single.points, 10);
    expect(b.repos.earnings.pointsBySkill(), {strength: 10});
    expectSame([a, b]);
  });

  test(
    'an earning taken back (un-ticked) goes on the other device too',
    () async {
      a.later();
      gymTask(a.repos);
      a.repos.earnings.save(gymEarning());
      await settle([a, b]);
      expect(b.repos.earnings.pointsBySkill(), {strength: 10});

      a.later();
      a.repos.earnings.delete(gymEarning().id);
      await settle([a, b]);
      expect(b.repos.earnings.pointsBySkill(), isEmpty);
      expectSame([a, b]);
    },
  );

  test('"Use the data of the account" keeps the built-in skills, and takes '
      'the renames of the account', () async {
    a.later();
    a.repos.skills.save(
      a.repos.skills.get('skill-mind')!.copyWith(name: 'Brain'),
    );
    await a.sync();

    final c = Device(remote);
    c.later();
    c.repos.skills.save(SkillItem(name: 'Only here', sort: 9));
    await c.engine.replaceWithAccount('user-1');

    expect(skillNames(c), [
      'Strength',
      'Brain',
      'Social',
      'Focus',
      'Creativity',
      'Health',
      'Home',
      'Money',
    ]);
    expect(c.waiting, isEmpty);
  });
}
