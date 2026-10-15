// The reward of a task or a goal: which skills get how many points when it
// is ticked done. For a goal the points are per hour of a goal block.
import 'package:flutter/material.dart';
import 'package:grove/core/services/persona.dart';
import 'package:grove/state/state.dart' hide MotionRules;

import '../tasks/task_widgets.dart';
import '../theme/grove_theme.dart';
import '../theme/panel.dart';

class RewardEditor extends StatelessWidget {
  const RewardEditor.task({
    super.key,
    required this.store,
    required this.ownerId,
  }) : isGoal = false,
       blockMinutes = null;

  /// [blockMinutes]: the length of the open goal block, to show what it
  /// gives.
  const RewardEditor.goal({
    super.key,
    required this.store,
    required this.ownerId,
    this.blockMinutes,
  }) : isGoal = true;

  final AppStore store;
  final String ownerId;
  final bool isGoal;
  final int? blockMinutes;

  /// The points a new line starts with.
  static const startPoints = 10;

  List<RewardItem> get _rewards =>
      isGoal ? store.goalRewards(ownerId) : store.taskRewards(ownerId);

  void _set(String skillId, int points) => isGoal
      ? store.setGoalReward(goalId: ownerId, skillId: skillId, points: points)
      : store.setTaskReward(taskId: ownerId, skillId: skillId, points: points);

  /// "This block gives 15 Strength, 8 Health". Null when it gives nothing.
  static String? blockLine(
    List<RewardItem> rewards,
    Map<String, String> names,
    int minutes,
  ) {
    final parts = [
      for (final r in rewards)
        if (PersonaRules.blockPoints(perHour: r.points, minutes: minutes)
            case final n when n > 0)
          '$n ${names[r.skillId] ?? ''}'.trim(),
    ];
    return parts.isEmpty ? null : 'This block gives ${parts.join(', ')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    final rewards = _rewards;
    final skills = store.skills;
    final names = {for (final s in skills) s.id: s.name};
    final used = {for (final r in rewards) r.skillId};
    final free = [
      for (final s in skills)
        if (!s.hidden && !used.contains(s.id)) s,
    ];
    final small = theme.body(12).copyWith(color: theme.muted);
    final minutes = blockMinutes;
    final line = minutes == null ? null : blockLine(rewards, names, minutes);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: 8,
      children: [
        ThemedHeading(
          isGoal ? 'Skill points per hour' : 'Skill points',
          12,
          weight: FontWeight.w700,
          color: theme.ink,
        ),
        if (rewards.isEmpty)
          Text(
            isGoal
                ? 'No points. Add a skill to earn points for each hour of a '
                      'done block.'
                : 'No points. Add a skill to earn points when this is done.',
            style: small,
          ),
        for (final r in rewards)
          Row(
            key: ValueKey('reward-${r.skillId}'),
            spacing: 8,
            children: [
              Expanded(
                child: Text(
                  names[r.skillId] ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.body(13).copyWith(color: theme.ink),
                ),
              ),
              SizedBox(
                width: 64,
                child: _PointsField(
                  key: ValueKey('reward-${r.skillId}-points'),
                  points: r.points,
                  label: '${names[r.skillId] ?? ''} points',
                  onSet: (n) => _set(r.skillId, n),
                ),
              ),
              IconTap(
                key: ValueKey('reward-${r.skillId}-remove'),
                icon: Icons.close,
                label: 'Remove ${names[r.skillId] ?? 'skill'}',
                size: 14,
                onTap: () => _set(r.skillId, 0),
              ),
            ],
          ),
        ?(line == null ? null : Text(line, style: small)),
        if (free.isNotEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: Builder(
              builder: (context) => TextTap(
                key: const ValueKey('reward-add'),
                label: 'Add skill',
                onTap: () {
                  final box = context.findRenderObject()! as RenderBox;
                  showGroveMenu(
                    context,
                    box.localToGlobal(Offset(0, box.size.height)),
                    [
                      for (final s in free)
                        MenuLine(s.name, () => _set(s.id, startPoints)),
                    ],
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}

/// A number from 1 to 999. Saved on Return and when the field loses focus.
/// An empty field or 0 removes the line. Text that is not a number is
/// dropped.
class _PointsField extends StatefulWidget {
  const _PointsField({
    super.key,
    required this.points,
    required this.label,
    required this.onSet,
  });

  final int points;
  final String label;
  final ValueChanged<int> onSet;

  @override
  State<_PointsField> createState() => _PointsFieldState();
}

class _PointsFieldState extends State<_PointsField> {
  late final _text = TextEditingController(text: '${widget.points}');
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _save();
    });
  }

  @override
  void didUpdateWidget(_PointsField old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && old.points != widget.points) {
      _text.text = '${widget.points}';
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _save() {
    final raw = _text.text.trim();
    final n = raw.isEmpty ? 0 : int.tryParse(raw);
    // Not a number: the field shows the saved points again.
    if (n == null || n == widget.points) {
      _text.text = '${widget.points}';
      return;
    }
    widget.onSet(n);
    if (n > 0) _text.text = '${PersonaRules.clampPoints(n)}';
  }

  @override
  Widget build(BuildContext context) => GroveField(
    controller: _text,
    focusNode: _focus,
    placeholder: '0',
    label: widget.label,
    boxed: true,
    maxLength: 3,
    keyboard: TextInputType.number,
    plainTyping: true,
    onSubmitted: (_) => _save(),
  );
}
