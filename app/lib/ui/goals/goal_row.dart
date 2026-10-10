// Port of Sources/Grove/Goals/GoalRow.swift.
import 'package:flutter/material.dart';
import 'package:grove/core/model/goal.dart';
import 'package:grove/state/state.dart' hide MotionRules;

import '../planner/inline_title_field.dart' show BlurAction, InlineTitleRules;
import '../planner/payload_drag.dart';
import '../planner/planner_dialogs.dart' show DialogButton;
import '../tasks/task_widgets.dart';
import '../theme/grove_theme.dart';
import '../theme/named_colors.dart';
import '../theme/panel.dart';

/// One goal in the panel: colour dot, title, "2.5 / 5 h done", a bar and
/// "4 h planned". A goal is never done itself; its blocks are ticked in the
/// planner. Click it to open the editor under it; click again to close.
/// Drag it onto a day to plan a block of it. Right-click to edit or delete.
class GoalRow extends StatelessWidget {
  const GoalRow({
    super.key,
    required this.store,
    required this.goal,
    required this.progress,
    required this.isOpen,
    required this.onToggle,
  });

  final AppStore store;
  final GoalItem goal;
  final GoalProgress progress;
  final bool isOpen;
  final VoidCallback onToggle;

  Future<void> _confirmDelete(BuildContext context) async {
    final delete = await showDialog<bool>(
      context: context,
      builder: (context) {
        final theme = GroveTheme.of(context);
        return Dialog(
          backgroundColor: theme.solidSurface,
          insetPadding: const EdgeInsets.all(20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(theme.radius),
            side: BorderSide(color: theme.line),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 12,
                children: [
                  ThemedHeading('Delete “${goal.title}”?', 18),
                  Text(
                    'Its blocks stay in the planner as plain blocks and no '
                    'longer count. You can undo this.',
                    style: theme.body(13).copyWith(color: theme.muted),
                  ),
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      DialogButton(
                        label: 'Cancel',
                        onTap: () => Navigator.of(context).pop(false),
                      ),
                      DialogButton(
                        key: const ValueKey('goal-delete-confirm'),
                        label: 'Delete Goal',
                        primary: true,
                        onTap: () => Navigator.of(context).pop(true),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    if (delete ?? false) store.deleteGoal(goal.id);
  }

  void _menu(BuildContext context, Offset global) =>
      showGroveMenu(context, global, [
        MenuLine(isOpen ? 'Close Editor' : 'Edit…', onToggle),
        const MenuLine.divider(),
        MenuLine('Delete Goal…', () => _confirmDelete(context)),
      ]);

  /// The part that is always there. A click opens or closes the editor; a
  /// drag plans a block.
  Widget _summary(BuildContext context, GroveTheme theme, Color tint) =>
      Semantics(
        container: true,
        button: true,
        label: GoalRules.accessibilityText(goal.title, progress),
        hint: 'Click to edit. Drag it into a day to plan time for it',
        onTap: onToggle,
        excludeSemantics: true,
        child: PayloadDrag(
          payload: DragPayload.goal(goal.id),
          label: goal.title,
          child: GestureDetector(
            key: ValueKey('goal-${goal.id}'),
            behavior: HitTestBehavior.opaque,
            onTap: onToggle,
            onSecondaryTapUp: (d) => _menu(context, d.globalPosition),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 8,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: SizedBox(
                    width: 10,
                    height: 10,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: tint,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    spacing: 5,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        spacing: 6,
                        children: [
                          Expanded(
                            child: Text(
                              goal.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme
                                  .body(13, weight: FontWeight.w600)
                                  .copyWith(color: theme.ink),
                            ),
                          ),
                          Text(
                            GoalRules.progressText(progress),
                            maxLines: 1,
                            style: theme
                                .number(11, weight: FontWeight.w600)
                                .copyWith(color: theme.muted),
                          ),
                        ],
                      ),
                      GoalBar(parts: GoalRules.bar(progress), tint: tint),
                      Text(
                        GoalRules.plannedText(progress),
                        style: theme.body(10).copyWith(color: theme.muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    final tint = theme.color(GoalRules.blockColor(goal));
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.surface2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isOpen
              ? theme.accent.withValues(alpha: 0.6)
              : const Color(0x00000000),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _summary(context, theme, tint),
            if (isOpen)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: GoalEditor(
                  key: ValueKey('goal-editor-${goal.id}'),
                  store: store,
                  goal: goal,
                  onClose: onToggle,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A thin bar against the week's target. The solid part is done, the
/// lighter part planned. Full when the goal is at or over its target.
class GoalBar extends StatelessWidget {
  const GoalBar({super.key, required this.parts, required this.tint});

  final ({double done, double planned}) parts;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    Widget part(double share, Color color) => FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: share.clamp(0.0, 1.0),
      child: DecoratedBox(
        decoration: ShapeDecoration(color: color, shape: const StadiumBorder()),
        child: const SizedBox.expand(),
      ),
    );
    return ExcludeSemantics(
      child: SizedBox(
        height: 6,
        child: DecoratedBox(
          decoration: ShapeDecoration(
            color: theme.surface,
            shape: const StadiumBorder(),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              part(parts.planned, tint.withValues(alpha: 0.35)),
              part(parts.done, tint),
            ],
          ),
        ),
      ),
    );
  }
}

/// The editor under an open goal row: name, Hours or Sessions, the weekly
/// target and the colour. Each change is saved at once and is one undo
/// step. The name is saved with Return or when the editor closes.
class GoalEditor extends StatefulWidget {
  const GoalEditor({
    super.key,
    required this.store,
    required this.goal,
    required this.onClose,
  });

  final AppStore store;
  final GoalItem goal;
  final VoidCallback onClose;

  @override
  State<GoalEditor> createState() => _GoalEditorState();
}

class _GoalEditorState extends State<GoalEditor> {
  late final _title = TextEditingController(text: widget.goal.title);

  AppStore get _store => widget.store;
  GoalItem get _goal => widget.goal;

  @override
  void dispose() {
    // The name is saved when the editor closes.
    final store = _store;
    final id = _goal.id;
    final title = _title.text;
    writeLater(store, () => _save(store, id, title));
    _title.dispose();
    super.dispose();
  }

  static void _save(AppStore store, String id, String title) {
    final saved = store.goal(id)?.title ?? '';
    if (InlineTitleRules.onBlur(title, initial: saved) == BlurAction.commit) {
      store.updateGoal(id, title: title);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    final goal = _goal;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: 10,
      children: [
        GroveField(
          key: ValueKey('goal-name-${goal.id}'),
          controller: _title,
          placeholder: 'Name',
          label: 'Goal name',
          boxed: true,
          fill: theme.surface,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          onSubmitted: (_) {
            _save(_store, goal.id, _title.text);
            widget.onClose();
          },
          onEscape: () {
            _title.text = goal.title;
            widget.onClose();
          },
        ),
        GoalKindPicker(
          kind: goal.kind,
          onChange: (k) => _store.updateGoal(goal.id, kind: k),
        ),
        TargetStepper(
          kind: goal.kind,
          value: GoalRules.target(goal),
          onChange: (value) => goal.kind == GoalKind.hours
              ? _store.updateGoal(goal.id, targetMin: value)
              : _store.updateGoal(goal.id, targetCount: value),
        ),
        ColourDots(
          current: goal.color,
          onPick: (name) => _store.updateGoal(goal.id, color: name),
        ),
      ],
    );
  }
}

/// Two buttons side by side: Hours or Sessions. They never take the
/// keyboard focus, so a name being typed beside them stays in its field.
class GoalKindPicker extends StatelessWidget {
  const GoalKindPicker({super.key, required this.kind, required this.onChange});

  final GoalKind kind;
  final ValueChanged<GoalKind> onChange;

  @override
  Widget build(BuildContext context) => Segments<GoalKind>(
    value: kind,
    values: GoalKind.values,
    name: GoalRules.kindName,
    label: 'Goal kind',
    onPick: onChange,
    tip: (k) => k == GoalKind.hours
        ? "Count the hours of the goal's blocks"
        : "Count the goal's blocks, whatever their length",
  );
}

/// "5 h / week" or "3 sessions / week" with a minus and a plus button.
/// Each click moves half an hour or one session (`GoalRules.stepTarget`).
/// The buttons never take the keyboard focus, so a name being typed beside
/// them stays in its field.
class TargetStepper extends StatelessWidget {
  const TargetStepper({
    super.key,
    required this.kind,
    required this.value,
    required this.onChange,
  });

  final GoalKind kind;
  final int value;
  final ValueChanged<int> onChange;

  Widget _step(GroveTheme theme, {required bool up}) {
    final next = GoalRules.stepTarget(value, kind: kind, up: up);
    final off = next == value;
    final hours = kind == GoalKind.hours;
    final label = hours
        ? (up ? 'More time' : 'Less time')
        : (up ? 'More sessions' : 'Fewer sessions');
    final tip = hours
        ? (up ? 'Half an hour more per week' : 'Half an hour less per week')
        : (up ? 'One more session per week' : 'One less session per week');
    void tap() => onChange(next);
    return Tooltip(
      message: tip,
      excludeFromSemantics: true,
      child: Semantics(
        container: true,
        button: true,
        enabled: !off,
        label: label,
        onTap: off ? null : tap,
        excludeSemantics: true,
        child: MouseRegion(
          cursor: off ? MouseCursor.defer : SystemMouseCursors.click,
          child: GestureDetector(
            key: ValueKey(up ? 'target-more' : 'target-less'),
            behavior: HitTestBehavior.opaque,
            onTap: off ? null : tap,
            child: SizedBox(
              width: 22,
              height: 22,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.surface2,
                  shape: BoxShape.circle,
                  border: Border.all(color: theme.line),
                ),
                child: Icon(
                  up ? Icons.add : Icons.remove,
                  size: 12,
                  color: off ? theme.muted.withValues(alpha: 0.5) : theme.ink,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    return Row(
      spacing: 6,
      children: [
        Expanded(
          child: Text(
            GoalRules.targetText(kind, value),
            style: theme
                .number(12, weight: FontWeight.w600)
                .copyWith(color: theme.ink),
          ),
        ),
        _step(theme, up: false),
        _step(theme, up: true),
      ],
    );
  }
}
