// The ticks that ask first: a block that holds open squares, and a project
// that still has open steps. All ticks of squares go through here, so the map,
// the panels and the grid do the same.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:grove/core/model/goal_square.dart';
import 'package:grove/state/state.dart' hide MotionRules;

import '../planner/planner_dialogs.dart';
import '../tasks/task_widgets.dart';
import '../theme/grove_theme.dart';
import '../theme/panel.dart';

/// Ticks a square, or takes the tick away. Finishing a project with open
/// steps asks first. Its steps and blocks stay as they are.
Future<void> tickSquare(
  BuildContext context,
  AppStore store,
  String squareId,
) async {
  final square = store.goalSquare(squareId);
  if (square == null) return;
  if (square.isRoot && !square.isDone) {
    final open = store.goalGraph(square.goalId)?.openCount ?? 0;
    if (open > 0 && !await confirmFinishEarly(context, open)) return;
  }
  store.toggleSquareDone(squareId);
}

/// "3 steps are still open. Finish anyway?". False when the user says no.
Future<bool> confirmFinishEarly(BuildContext context, int open) async {
  final finish = await showDialog<bool>(
    context: context,
    builder: (context) {
      final theme = GroveTheme.of(context);
      return PlannerSheet(
        width: 360,
        children: [
          ThemedHeading(
            open == 1
                ? '1 step is still open. Finish anyway?'
                : '$open steps are still open. Finish anyway?',
            18,
          ),
          Text(
            'The steps and blocks stay. Remove the tick to open the project '
            'again.',
            style: theme.body(13).copyWith(color: theme.muted),
          ),
          dialogButtons([
            DialogButton(
              label: 'Cancel',
              onTap: () => Navigator.of(context).pop(false),
            ),
            DialogButton(
              key: const ValueKey('finish-early-confirm'),
              label: 'Finish',
              primary: true,
              onTap: () => Navigator.of(context).pop(true),
            ),
          ]),
        ],
      );
    },
  );
  return finish ?? false;
}

/// Ticks a goal block, or takes the tick away. A block that holds open squares
/// asks about each one. The tick and the answers are one undo step.
Future<void> tickGoalBlock(
  BuildContext context,
  AppStore store,
  String eventId,
) async {
  final block = store.event(eventId);
  if (block == null) return;
  final open = block.doneAt == null
      ? store.openSquaresOfBlock(eventId)
      : const <GoalSquare>[];
  if (open.isEmpty) {
    store.toggleGoalBlockDone(eventId: eventId);
    return;
  }
  final answers = await showDialog<Map<String, SquareAnswer>>(
    context: context,
    builder: (context) => _TickQuestion(store: store, squares: open),
  );
  if (answers == null || !context.mounted) return;
  // The root is the result. Finishing it early asks, as on the map.
  final rootId = GoalSquare.rootIdOf(block.goalId ?? '');
  if (answers[rootId]?.kind == SquareAnswerKind.done) {
    final graph = store.goalGraph(block.goalId ?? '');
    final left = graph == null
        ? 0
        : graph.ids.where((id) {
            if (id == rootId || graph.square(id).isDone) return false;
            return answers[id]?.kind != SquareAnswerKind.done;
          }).length;
    if (left > 0 && !await confirmFinishEarly(context, left)) {
      answers[rootId] = SquareAnswer.notYet;
    }
  }
  store.answerBlockTick(eventId: eventId, answers: answers);
}

class _TickQuestion extends StatefulWidget {
  const _TickQuestion({required this.store, required this.squares});

  final AppStore store;
  final List<GoalSquare> squares;

  @override
  State<_TickQuestion> createState() => _TickQuestionState();
}

class _TickQuestionState extends State<_TickQuestion> {
  late final _kinds = <String, SquareAnswerKind>{
    for (final s in widget.squares) s.id: SquareAnswerKind.done,
  };
  late final _days = <String, int>{
    for (final s in widget.squares) s.id: WaitDays.of(s),
  };

  Map<String, SquareAnswer> get _answers => {
    for (final s in widget.squares)
      s.id: switch (_kinds[s.id]!) {
        SquareAnswerKind.done => SquareAnswer.done,
        SquareAnswerKind.notYet => SquareAnswer.notYet,
        SquareAnswerKind.startWaiting => SquareAnswer(
          SquareAnswerKind.startWaiting,
          waitMinutes: _days[s.id]! * WaitDays.minutesPerDay,
        ),
      },
  };

  Widget _row(GroveTheme theme, GoalSquare square) {
    final kind = _kinds[square.id]!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: 6,
      children: [
        Text(
          square.isRoot
              ? (widget.store.goal(square.goalId)?.title ?? square.title)
              : square.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.body(13, weight: FontWeight.w600),
        ),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final (k, name) in [
              (SquareAnswerKind.done, 'Done'),
              if (!square.isRoot)
                (SquareAnswerKind.startWaiting, 'Start waiting'),
              (SquareAnswerKind.notYet, 'Not yet'),
            ])
              DialogButton(
                key: ValueKey('tick-answer-${square.id}-${k.name}'),
                label: name,
                primary: kind == k,
                onTap: () => setState(() => _kinds[square.id] = k),
              ),
          ],
        ),
        if (kind == SquareAnswerKind.startWaiting)
          WaitDays(
            key: ValueKey('tick-wait-${square.id}'),
            days: _days[square.id]!,
            onChange: (d) => setState(() => _days[square.id] = d),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    return PlannerSheet(
      width: 380,
      children: [
        const ThemedHeading('How did it go?', 18),
        for (final s in widget.squares) _row(theme, s),
        dialogButtons([
          DialogButton(
            label: 'Cancel',
            onTap: () => Navigator.of(context).pop(),
          ),
          DialogButton(
            key: const ValueKey('tick-question-save'),
            label: 'Mark done',
            primary: true,
            onTap: () => Navigator.of(context).pop(_answers),
          ),
        ]),
      ],
    );
  }
}

/// The length of a wait, in days, with a button for less and for more.
class WaitDays extends StatelessWidget {
  const WaitDays({super.key, required this.days, required this.onChange});

  static const minutesPerDay = 24 * 60;
  static const maxDays = 365;

  final int days;
  final ValueChanged<int> onChange;

  /// The days of a square's wait: what it has, or the usual wait.
  static int of(GoalSquare square) {
    final minutes = square.waitMinutes ?? AppStoreGoalMap.defaultWaitMinutes;
    return (minutes / minutesPerDay).ceil().clamp(1, maxDays);
  }

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 6,
      children: [
        IconTap(
          key: const ValueKey('wait-less'),
          icon: Icons.remove,
          label: 'One day less',
          minSide: 28,
          onTap: () => onChange((days - 1).clamp(1, maxDays)),
        ),
        Text(
          GoalRules.waitDaysText(days),
          style: theme.number(12, weight: FontWeight.w600),
        ),
        IconTap(
          key: const ValueKey('wait-more'),
          icon: Icons.add,
          label: 'One day more',
          minSide: 28,
          onTap: () => onChange((days + 1).clamp(1, maxDays)),
        ),
      ],
    );
  }
}
