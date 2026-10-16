// The Persona screen: a drawn person, a bar for each skill, and the newest
// points. Ticking a task or a goal block done pays the points of its reward.
import 'package:flutter/material.dart' hide Row;
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/ui/goals/goal_panel.dart';
import 'package:grove/ui/persona/level_up_layer.dart';
import 'package:grove/ui/persona/persona_painter.dart';
import 'package:grove/ui/persona/persona_view.dart';
import 'package:grove/ui/persona/reward_editor.dart';
import 'package:grove/ui/tasks/task_inspector.dart';

import '../planner/planner_support.dart';
import '../tasks/tasks_support.dart' show addTask;

AppStore personaStore() => plannerStore()..screen = Screen.persona;

const strength = 'skill-strength';

Finder bar(String skillId) => find.byKey(ValueKey('persona-skill-$skillId'));

Finder inBar(String skillId, String text) =>
    find.descendant(of: bar(skillId), matching: find.text(text));

/// A task "Gym" that gives [points] Strength, ticked done.
void gym(AppStore store, {int points = 10}) {
  addTask(store, 'Gym', id: 'GYM');
  store.setTaskReward(taskId: 'GYM', skillId: strength, points: points);
  store.toggleDone(taskId: 'GYM');
}

void main() {
  testWidgets('a new persona: the drawing, the name, 8 skills at level 1', (
    tester,
  ) async {
    final store = personaStore();
    await pumpPlanner(tester, store, size: const Size(1100, 1400));
    expect(tester.takeException(), isNull);
    expect(find.byType(PersonaView), findsOneWidget);
    expect(find.byType(PersonaDrawing), findsOneWidget);
    expect(find.text('Persona'), findsWidgets);
    expect(find.byKey(const ValueKey('persona-name')), findsOneWidget);
    expect(find.text('You'), findsOneWidget);
    for (final s in store.skills) {
      expect(bar(s.id), findsOneWidget);
      expect(inBar(s.id, s.name), findsOneWidget);
      expect(inBar(s.id, 'Level 1'), findsOneWidget);
    }
    expect(
      find.text('No points yet. Finish a task with a reward.'),
      findsOneWidget,
    );
  });

  testWidgets('a ticked task fills the bar and shows in the newest points', (
    tester,
  ) async {
    final store = personaStore();
    await pumpPlanner(tester, store, size: const Size(1100, 1400));
    gym(store, points: 30);
    await tester.pumpAndSettle();
    expect(inBar(strength, '30 / 60'), findsOneWidget);
    expect(find.text('+30 Strength'), findsOneWidget);
    expect(find.text('Gym'), findsOneWidget);
    final full = tester.getSize(
      find.byKey(const ValueKey('persona-skill-skill-strength-bar')),
    );
    final fill = tester.getSize(
      find.byKey(const ValueKey('persona-skill-skill-strength-fill')),
    );
    expect(fill.width, closeTo(full.width / 2, 1));
  });

  testWidgets('a new level shows a pop-up over the screen', (tester) async {
    final store = personaStore();
    await pumpPlanner(tester, store, size: const Size(1100, 1400));
    gym(store, points: 60);
    await tester.pump();
    expect(find.byKey(const ValueKey('level-up')), findsOneWidget);
    expect(find.text('Strength reached level 2'), findsOneWidget);
    expect(inBar(strength, 'Level 2'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('level-up')), findsNothing);
  });

  testWidgets('the name can be changed', (tester) async {
    final store = personaStore();
    await pumpPlanner(tester, store, size: const Size(1100, 1400));
    await tester.tap(find.byKey(const ValueKey('persona-name')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('persona-name-field')),
      'Andrei',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(store.personaName, 'Andrei');
    expect(find.text('Andrei'), findsOneWidget);
  });

  testWidgets('a skill can be added; a hidden skill has no bar', (
    tester,
  ) async {
    final store = personaStore();
    await pumpPlanner(tester, store, size: const Size(1100, 1400));
    await tester.tap(find.byKey(const ValueKey('persona-add-skill')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('persona-new-skill')),
      'Cooking',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(store.skills.last.name, 'Cooking');
    expect(bar(store.skills.last.id), findsOneWidget);

    store.setSkillHidden(strength, hidden: true);
    await tester.pumpAndSettle();
    expect(bar(strength), findsNothing);
    expect(find.text('1 hidden skill'), findsOneWidget);
  });

  testWidgets('the task panel sets the reward of a task', (tester) async {
    final store = plannerStore();
    addTask(store, 'Gym', id: 'GYM');
    store.selectedTaskId = 'GYM';
    await pumpPlanner(tester, store, size: const Size(1280, 1400));
    expect(find.byType(TaskInspector), findsOneWidget);
    expect(find.byType(RewardEditor), findsOneWidget);
    expect(find.text('Skill points'), findsOneWidget);
    store.setTaskReward(taskId: 'GYM', skillId: strength, points: 10);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reward-$strength')), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('reward-$strength-points')),
      '25',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(store.taskRewards('GYM').single.points, 25);
    await tester.tap(find.byKey(const ValueKey('reward-$strength-remove')));
    await tester.pumpAndSettle();
    expect(store.taskRewards('GYM'), isEmpty);
  });

  testWidgets('the goal panel sets the reward per hour of a goal', (
    tester,
  ) async {
    final store = plannerStore();
    final block = goalBlock(store);
    final goalId = store.goals().single.id;
    store
      ..setGoalReward(goalId: goalId, skillId: strength, points: 10)
      ..openGoalPanel(block);
    await pumpPlanner(tester, store, size: const Size(1280, 1400));
    expect(find.byType(GoalPanel), findsOneWidget);
    expect(find.byType(RewardEditor), findsOneWidget);
    expect(find.text('Skill points per hour'), findsOneWidget);
    expect(find.text('This block gives 15 Strength'), findsOneWidget);
  });

  testWidgets('the level-up layer shows nothing without a new level', (
    tester,
  ) async {
    final store = plannerStore();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: LevelUpLayer(store: store, child: const SizedBox.expand()),
      ),
    );
    expect(find.byKey(const ValueKey('level-up')), findsNothing);
  });

  group('Your days', () {
    Finder days(String text) => find.descendant(
      of: find.byKey(const ValueKey('persona-days')),
      matching: find.text(text),
    );

    Finder inDays(Key key) => find.descendant(
      of: find.byKey(const ValueKey('persona-days')),
      matching: find.byKey(key),
    );

    double fill(WidgetTester t, String name) =>
        t.getSize(find.byKey(ValueKey('days-$name-fill'))).width /
        t.getSize(find.byKey(ValueKey('days-$name-bar'))).width;

    testWidgets('3 bars count the good, okay and rough days of this month', (
      tester,
    ) async {
      final store = personaStore();
      store
        ..setMood(store.dailyNote(d('2026-10-01')).id, Mood.sun)
        ..setMood(store.dailyNote(d('2026-10-02')).id, Mood.sun)
        ..setMood(store.dailyNote(d('2026-10-03')).id, Mood.rain)
        ..setMood(store.dailyNote(d('2026-09-30')).id, Mood.cloud);
      await pumpPlanner(tester, store, size: const Size(1100, 1400));
      expect(tester.takeException(), isNull);
      expect(days('Your days'), findsOneWidget);
      expect(days('Good'), findsOneWidget);
      expect(days('Okay'), findsOneWidget);
      expect(days('Rough'), findsOneWidget);
      expect(find.byKey(const ValueKey('days-good-count')), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('days-good-count'))).data,
        '2',
      );
      expect(fill(tester, 'good'), closeTo(1, 0.02));
      expect(fill(tester, 'rough'), closeTo(0.5, 0.02));
      expect(fill(tester, 'okay'), 0);

      await tester.tap(days('All time'));
      await tester.pumpAndSettle();
      expect(store.daySpan, DaySpan.all);
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('days-okay-count'))).data,
        '1',
      );
    });

    testWidgets('no marked days shows a hint', (tester) async {
      final store = personaStore();
      await pumpPlanner(tester, store, size: const Size(1100, 1400));
      expect(
        days('No days marked yet. Pick one below or in a daily note.'),
        findsOneWidget,
      );
    });

    testWidgets("a mood picked here is today's mood", (tester) async {
      final store = personaStore();
      await pumpPlanner(tester, store, size: const Size(1100, 1400));
      await tester.tap(inDays(const ValueKey('mood-sun')));
      await tester.pumpAndSettle();
      expect(store.todayMood, Mood.sun);
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('days-good-count'))).data,
        '1',
      );
    });

    testWidgets('wide: the days are beside the person; narrow: below it', (
      tester,
    ) async {
      final store = personaStore();
      await pumpPlanner(tester, store, size: const Size(1280, 1400));
      var hero = tester.getRect(find.byKey(const ValueKey('persona-hero')));
      var card = tester.getRect(find.byKey(const ValueKey('persona-days')));
      expect(card.left, greaterThan(hero.right));
      expect(card.top, closeTo(hero.top, 1));

      await pumpPlanner(tester, store, size: const Size(420, 1800));
      expect(tester.takeException(), isNull);
      hero = tester.getRect(find.byKey(const ValueKey('persona-hero')));
      card = tester.getRect(find.byKey(const ValueKey('persona-days')));
      expect(card.top, greaterThan(hero.bottom));
    });
  });
}
