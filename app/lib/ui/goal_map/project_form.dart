// The form of a goal. A new goal picks Project or Habit. No field of a project
// is needed.
import 'package:flutter/material.dart';
import 'package:grove/core/model/day_key.dart';
import 'package:grove/core/model/goal.dart';
import 'package:grove/state/state.dart' hide MotionRules;

import '../goals/goal_row.dart';
import '../planner/planner_dialogs.dart';
import '../tasks/task_widgets.dart';
import '../theme/grove_theme.dart';
import '../theme/panel.dart';

/// The form of a new goal. Gives the goal, or null when the user cancelled.
Future<GoalItem?> showNewGoalForm(
  BuildContext context,
  AppStore store, {
  bool project = true,
}) => showDialog<GoalItem>(
  context: context,
  builder: (_) => _GoalForm(store: store, startAsProject: project),
);

/// The form of a project that exists.
Future<void> showProjectForm(
  BuildContext context,
  AppStore store,
  GoalItem goal,
) => showDialog<GoalItem>(
  context: context,
  builder: (_) => _GoalForm(store: store, goal: goal),
);

class _GoalForm extends StatefulWidget {
  const _GoalForm({required this.store, this.goal, this.startAsProject = true});

  final AppStore store;

  /// Null: a new goal.
  final GoalItem? goal;
  final bool startAsProject;

  @override
  State<_GoalForm> createState() => _GoalFormState();
}

class _GoalFormState extends State<_GoalForm> {
  GoalItem? get _old => widget.goal;

  late bool _project = widget.startAsProject;
  late final _title = TextEditingController(text: _old?.title ?? '');
  late final _what = TextEditingController(text: _old?.notes ?? '');
  late final _doneWhen = TextEditingController(text: _old?.doneWhen ?? '');
  late final _work = TextEditingController(
    text: _old?.workMinutes == null ? '' : GoalRules.hours(_old!.workMinutes!),
  );
  late final _why = TextEditingController(text: _old?.why ?? '');
  late DayKey? _due = _old?.dueDay;
  late String _color = _old?.color ?? '';
  GoalKind _kind = GoalKind.hours;
  int _target = GoalRules.defaultTarget;

  @override
  void initState() {
    super.initState();
    _title.addListener(_refresh);
  }

  @override
  void dispose() {
    _title.dispose();
    _what.dispose();
    _doneWhen.dispose();
    _work.dispose();
    _why.dispose();
    super.dispose();
  }

  void _refresh() => setState(() {});

  /// A habit needs a name. A project needs nothing.
  bool get _canSave => _project || _title.text.trim().isNotEmpty;

  void _save() {
    if (!_canSave) return;
    final store = widget.store;
    final old = _old;
    final minutes = GoalRules.parseHours(_work.text);
    GoalItem? result;
    if (old != null) {
      store.updateProject(
        old.id,
        title: _title.text,
        notes: _what.text.trim(),
        color: _color,
        doneWhen: _doneWhen.text.trim(),
        workMinutes: minutes,
        dueDay: _due,
        why: _why.text.trim(),
      );
      result = store.goal(old.id);
    } else if (_project) {
      result = store.addProject(
        title: _title.text,
        notes: _what.text.trim(),
        color: _color,
        doneWhen: _doneWhen.text.trim(),
        workMinutes: minutes,
        dueDay: _due,
        why: _why.text.trim(),
      );
    } else {
      result = store.addGoal(title: _title.text, kind: _kind, target: _target);
      if (result != null && _color.isNotEmpty) {
        store.updateGoal(result.id, color: _color);
        result = store.goal(result.id);
      }
    }
    Navigator.of(context).pop(result);
  }

  Widget _field(
    GroveTheme theme,
    String key,
    TextEditingController controller,
    String name, {
    int minLines = 1,
    int maxLines = 1,
    TextInputType? keyboard,
    bool autofocus = false,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    spacing: 4,
    children: [
      Text(name, style: theme.body(11).copyWith(color: theme.muted)),
      GroveField(
        key: ValueKey(key),
        controller: controller,
        placeholder: '',
        label: name,
        boxed: true,
        minLines: minLines,
        maxLines: maxLines,
        newlines: maxLines > 1,
        keyboard: keyboard,
        autofocus: autofocus,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      ),
    ],
  );

  Widget _typePicker() => Wrap(
    spacing: 6,
    children: [
      DialogButton(
        key: const ValueKey('form-type-project'),
        label: 'Project: it can finish',
        primary: _project,
        onTap: () => setState(() => _project = true),
      ),
      DialogButton(
        key: const ValueKey('form-type-habit'),
        label: 'Habit: every week',
        primary: !_project,
        onTap: () => setState(() => _project = false),
      ),
    ],
  );

  Widget _dueRow(GroveTheme theme, DayKey today) {
    final due = _due;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: 4,
      children: [
        Text('By when', style: theme.body(11).copyWith(color: theme.muted)),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            DayPick(
              key: const ValueKey('form-due'),
              day: due ?? today,
              label: 'By when',
              onPick: (d) => setState(() => _due = d),
            ),
            if (due == null)
              Text(
                'No date yet',
                style: theme.body(11).copyWith(color: theme.muted),
              )
            else
              IconTap(
                key: const ValueKey('form-due-clear'),
                icon: Icons.close,
                label: 'No date',
                color: theme.muted,
                minSide: 28,
                onTap: () => setState(() => _due = null),
              ),
          ],
        ),
      ],
    );
  }

  Future<void> _delete() async {
    final old = _old;
    if (old == null) return;
    final navigator = Navigator.of(context);
    await confirmDeleteGoal(context, widget.store, old);
    if (widget.store.goal(old.id) == null && navigator.mounted) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    final isNew = _old == null;
    return PlannerSheet(
      width: 440,
      children: [
        ThemedHeading(isNew ? 'New goal' : 'Edit project', 20),
        if (isNew) _typePicker(),
        _field(theme, 'form-title', _title, 'Name', autofocus: true),
        if (_project) ...[
          _field(
            theme,
            'form-what',
            _what,
            'What is it?',
            minLines: 2,
            maxLines: 4,
          ),
          _field(
            theme,
            'form-done-when',
            _doneWhen,
            'How do I know it is done?',
          ),
          _field(
            theme,
            'form-work',
            _work,
            'How much work? (hours)',
            keyboard: const TextInputType.numberWithOptions(decimal: true),
          ),
          _dueRow(theme, widget.store.clockToday),
          _field(theme, 'form-why', _why, 'Why does it matter?'),
        ] else ...[
          GoalKindPicker(
            kind: _kind,
            onChange: (k) => setState(() {
              _kind = k;
              _target = GoalRules.defaultTargetFor(k);
            }),
          ),
          TargetStepper(
            kind: _kind,
            value: _target,
            onChange: (v) => setState(() => _target = v),
          ),
        ],
        ColourDots(
          current: _color,
          onPick: (name) => setState(() => _color = name),
        ),
        dialogButtons([
          if (!isNew)
            DialogButton(
              key: const ValueKey('form-delete'),
              label: 'Delete project',
              onTap: _delete,
            ),
          DialogButton(
            label: 'Cancel',
            onTap: () => Navigator.of(context).pop(),
          ),
          DialogButton(
            key: const ValueKey('form-save'),
            label: isNew ? 'Create' : 'Save',
            primary: true,
            onTap: _canSave ? _save : null,
          ),
        ]),
      ],
    );
  }
}
