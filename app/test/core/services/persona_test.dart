import 'package:flutter_test/flutter_test.dart';
import 'package:grove/core/services/persona.dart';

void main() {
  group('SkillLevel', () {
    test('a skill with no points is at level 1 with an empty bar', () {
      final l = SkillLevel.of(0);
      expect(l.level, 1);
      expect(l.into, 0);
      expect(l.needed, 60);
      expect(l.fill, 0);
    });

    test('level 1 to 2 needs 60 points, then each level 10 more', () {
      expect(SkillLevel.of(59).level, 1);
      expect(SkillLevel.of(60).level, 2);
      expect(SkillLevel.of(60).into, 0);
      expect(SkillLevel.of(60).needed, 70);
      expect(SkillLevel.of(129).level, 2);
      expect(SkillLevel.of(130).level, 3);
      expect(SkillLevel.of(130).needed, 80);
    });

    test('the bar is the share of this level that is done', () {
      expect(SkillLevel.of(30).fill, 0.5);
      expect(SkillLevel.of(95).fill, 0.5);
    });

    test('points below zero count as zero', () {
      expect(SkillLevel.of(-5).level, 1);
      expect(SkillLevel.of(-5).into, 0);
    });

    test('the persona level uses steps 4 times as big', () {
      expect(SkillLevel.persona(239).level, 1);
      expect(SkillLevel.persona(240).level, 2);
      expect(SkillLevel.persona(240).needed, 280);
    });

    test('a very big number stays fast and gives a level', () {
      expect(SkillLevel.of(10000000).level, greaterThan(100));
    });
  });

  group('PersonaRules', () {
    test('there are 8 built-in skills with fixed ids', () {
      expect(PersonaRules.builtins.map((s) => s.name), [
        'Strength',
        'Mind',
        'Social',
        'Focus',
        'Creativity',
        'Health',
        'Home',
        'Money',
      ]);
      expect(PersonaRules.builtins.first.id, 'skill-strength');
      expect(PersonaRules.builtins.last.id, 'skill-money');
    });

    test('a goal block pays its points per hour, by its length', () {
      expect(PersonaRules.blockPoints(perHour: 10, minutes: 60), 10);
      expect(PersonaRules.blockPoints(perHour: 10, minutes: 90), 15);
      expect(PersonaRules.blockPoints(perHour: 10, minutes: 20), 3);
      expect(PersonaRules.blockPoints(perHour: 10, minutes: 0), 0);
      expect(PersonaRules.blockPoints(perHour: 1, minutes: 15), 0);
    });

    test('the points of a reward stay between 1 and 999', () {
      expect(PersonaRules.clampPoints(0), 1);
      expect(PersonaRules.clampPoints(25), 25);
      expect(PersonaRules.clampPoints(5000), 999);
    });

    test('ids are fixed, so two devices make the same row', () {
      expect(
        PersonaRules.taskRewardId('t1', 'skill-mind'),
        'r:task:t1:skill-mind',
      );
      expect(
        PersonaRules.goalRewardId('g1', 'skill-mind'),
        'r:goal:g1:skill-mind',
      );
      expect(
        PersonaRules.earningId(EarningSource.task, 't1', 'skill-mind'),
        'e:task:t1:skill-mind',
      );
      expect(
        PersonaRules.earningId(EarningSource.goalBlock, 'b1', 'skill-mind'),
        'e:goal_block:b1:skill-mind',
      );
    });

    test('a skill name is trimmed and has at most 24 letters', () {
      expect(PersonaRules.cleanName('  Cooking  '), 'Cooking');
      expect(PersonaRules.cleanName('x' * 40).length, 24);
    });
  });
}
