// The window of "Reorganise rest of day" (the button next to Timeline): a
// bar and a number per task for how much of it is done, and where each one
// goes. The plan itself is `ReplanRules`; the store applies it.
import 'package:flutter/material.dart';
import 'package:grove/core/planner/planner_math.dart';
import 'package:grove/state/state.dart' hide MotionRules;

import '../settings/settings_parts.dart';
import '../tasks/task_widgets.dart';
import '../theme/grove_theme.dart';
import '../theme/panel.dart';
import 'planner_dialogs.dart';

/// How much of each item is done, by item id, when the user picked Apply.
/// Null when the user closed the window.
Future<Map<String, int>?> showReplanSheet(
  BuildContext context,
  ReplanInput input,
) => showDialog<Map<String, int>>(
  context: context,
  builder: (context) => _ReplanSheet(input: input),
);

class _ReplanSheet extends StatefulWidget {
  const _ReplanSheet({required this.input});

  final ReplanInput input;

  @override
  State<_ReplanSheet> createState() => _ReplanSheetState();
}

class _ReplanSheetState extends State<_ReplanSheet> {
  late final Map<String, int> _pct = {
    for (final i in widget.input.items) i.id: 0,
  };

  /// The rows keep the order of the plan at 0%, so a row does not jump
  /// away from the bar that is being dragged.
  late final List<ReplanItem> _order = [
    for (final s in ReplanRules.plan(widget.input, const {})) s.item,
  ];

  void _set(String id, int pct) {
    final p = ReplanRules.clampPct(pct);
    if (_pct[id] != p) setState(() => _pct[id] = p);
  }

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    final input = widget.input;
    final steps = {for (final s in ReplanRules.plan(input, _pct)) s.item.id: s};
    final misses = steps.values.where((s) => s.overflow && !s.item.isGoal);
    final removed = steps.values.where((s) => s.overflow && s.item.isGoal);
    final until = input.end >= PlannerMath.dayEnd
        ? 'midnight'
        : PlannerMath.clock(input.end);
    return PlannerSheet(
      width: 460,
      children: [
        const ThemedHeading('Reorganise rest of day', 20),
        Text(
          'From ${PlannerMath.clock(input.from)} until $until',
          style: theme.body(12).copyWith(color: theme.muted),
        ),
        for (final item in _order)
          _ReplanRow(
            key: ValueKey('replan-row-${item.id}'),
            step: steps[item.id]!,
            onPct: (p) => _set(item.id, p),
          ),
        Text(
          _footer(misses.length, removed.length),
          key: const ValueKey('replan-footer'),
          style: theme.body(12).copyWith(color: theme.muted),
        ),
        dialogButtons([
          DialogButton(
            key: const ValueKey('replan-cancel'),
            label: 'Cancel',
            onTap: () => Navigator.of(context).pop(),
          ),
          DialogButton(
            key: const ValueKey('replan-apply'),
            label: 'Apply',
            primary: true,
            onTap: () => Navigator.of(context).pop({..._pct}),
          ),
        ]),
      ],
    );
  }
}

/// What does not fit: tasks go back to today's list, goal blocks go.
String _footer(int tasks, int goals) {
  if (tasks == 0 && goals == 0) return 'All fit.';
  return [
    if (tasks == 1) "1 will not fit and goes back to today's list.",
    if (tasks > 1) "$tasks will not fit and go back to today's list.",
    if (goals == 1) '1 goal block will not fit and is removed.',
    if (goals > 1) '$goals goal blocks will not fit and are removed.',
  ].join(' ');
}

/// One item: its name, the bar, the number and where it goes.
class _ReplanRow extends StatefulWidget {
  const _ReplanRow({super.key, required this.step, required this.onPct});

  final ReplanStep step;
  final ValueChanged<int> onPct;

  @override
  State<_ReplanRow> createState() => _ReplanRowState();
}

class _ReplanRowState extends State<_ReplanRow> {
  late final _text = TextEditingController(text: '${widget.step.pct}');
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _save();
    });
  }

  @override
  void didUpdateWidget(_ReplanRow old) {
    super.didUpdateWidget(old);
    // The field shows what the user types until Return or a click away.
    if (!_focus.hasFocus && old.step.pct != widget.step.pct) {
      _text.text = '${widget.step.pct}';
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _typed(String raw) {
    final n = int.tryParse(raw.trim());
    if (n != null) widget.onPct(n);
  }

  /// Return or a click away: the field shows the value, 0 to 100. Text that
  /// is not a number is dropped.
  void _save() {
    final n = int.tryParse(_text.text.trim());
    final p = n == null ? widget.step.pct : ReplanRules.clampPct(n);
    if (n != null) widget.onPct(p);
    _text.text = '$p';
  }

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    final step = widget.step;
    final item = step.item;
    final at = step.placedAt;
    final left = step.done
        ? 'done'
        : '${PlannerMath.duration(step.remaining)} left';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 2,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          spacing: 10,
          children: [
            Expanded(
              child: SettingsSlider(
                sliderKey: ValueKey('replan-slider-${item.id}'),
                label: item.title,
                valueText: '${step.pct}% · $left',
                value: step.pct.toDouble(),
                min: 0,
                max: 100,
                onChanged: (v) {
                  final p = v.round();
                  _text.text = '$p';
                  widget.onPct(p);
                },
              ),
            ),
            SizedBox(
              width: 56,
              child: GroveField(
                key: ValueKey('replan-field-${item.id}'),
                controller: _text,
                focusNode: _focus,
                placeholder: '0',
                label: 'Percent done of ${item.title}',
                boxed: true,
                maxLength: 3,
                keyboard: TextInputType.number,
                plainTyping: true,
                onChanged: _typed,
                onSubmitted: (_) => _save(),
              ),
            ),
          ],
        ),
        Text(
          step.done
              ? 'Done'
              : at != null
              ? '→ ${PlannerMath.clock(at)}'
              // A goal block that does not fit goes; its worked part stays.
              : !item.isGoal
              ? 'Will not fit'
              : step.pct > 0
              ? 'Will not fit · rest removed'
              : 'Will not fit · removed',
          key: ValueKey('replan-outcome-${item.id}'),
          maxLines: 1,
          style: theme
              .number(11)
              .copyWith(
                color: step.overflow
                    ? theme.muted
                    : step.done
                    ? theme.ink
                    : theme.accent,
              ),
        ),
      ],
    );
  }
}
