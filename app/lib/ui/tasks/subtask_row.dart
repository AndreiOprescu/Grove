// Port of Sources/Grove/Tasks/SubtaskRow.swift.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:grove/core/model/task.dart';
import 'package:grove/core/planner/planner_math.dart';
import 'package:grove/state/state.dart' hide MotionRules;

import '../theme/check_box.dart';
import '../theme/grove_theme.dart';
import '../theme/panel.dart';
import 'task_widgets.dart';

/// One subtask in the task panel. Closed: check box, name, duration chip,
/// arrow. Open: also a description, a duration menu and a delete button.
/// The name saves on Return and when the field loses the keyboard. The
/// description saves after a short pause and on blur. One burst of typing
/// is one undo step (see `AppStore.setNotes`).
class SubtaskRow extends StatefulWidget {
  const SubtaskRow({
    super.key,
    required this.store,
    required this.sub,
    required this.expanded,
    required this.toggleExpanded,
  });

  final AppStore store;
  final TaskItem sub;
  final bool expanded;
  final VoidCallback toggleExpanded;

  @override
  State<SubtaskRow> createState() => _SubtaskRowState();
}

class _SubtaskRowState extends State<SubtaskRow> {
  late final _title = TextEditingController(text: widget.sub.title);
  late final _notes = TextEditingController(text: widget.sub.notes);
  final _titleFocus = FocusNode();
  final _notesFocus = FocusNode();
  Timer? _saveTimer;

  AppStore get _store => widget.store;
  TaskItem get _sub => widget.sub;

  @override
  void initState() {
    super.initState();
    _titleFocus.addListener(_titleFocusChanged);
    _notesFocus.addListener(_notesFocusChanged);
  }

  @override
  void didUpdateWidget(SubtaskRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sub.title != _sub.title && !_titleFocus.hasFocus) {
      _title.text = _sub.title;
    }
    if (oldWidget.sub.notes != _sub.notes &&
        !_notesFocus.hasFocus &&
        _saveTimer == null) {
      _notes.text = _sub.notes;
    }
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    // What the user typed is saved when the row goes away.
    final store = _store;
    final id = _sub.id;
    final title = _title.text;
    final notes = _notes.text;
    writeLater(store, () {
      final current = store.task(id);
      if (current == null) return;
      final name = SubtaskRules.renamed(title, from: current.title);
      if (name != null) {
        store.editTask(
          id,
          (t) => t.copyWith(title: name),
          name: 'Rename Subtask',
        );
      }
      store.setNotes(id, notes);
    });
    _titleFocus.removeListener(_titleFocusChanged);
    _notesFocus.removeListener(_notesFocusChanged);
    _title.dispose();
    _notes.dispose();
    _titleFocus.dispose();
    _notesFocus.dispose();
    super.dispose();
  }

  // MARK: Saving

  void _titleFocusChanged() {
    if (!_titleFocus.hasFocus) _commitTitle();
  }

  void _commitTitle() {
    final current = _store.task(_sub.id);
    if (current == null) return;
    final name = SubtaskRules.renamed(_title.text, from: current.title);
    if (name != null) {
      _store.editTask(
        _sub.id,
        (t) => t.copyWith(title: name),
        name: 'Rename Subtask',
      );
      _title.text = name;
    } else if (_title.text != current.title) {
      // Empty or not changed: show what is saved.
      _title.text = current.title;
    }
  }

  void _notesFocusChanged() {
    if (_notesFocus.hasFocus) return;
    _saveNotes();
    // The saved text can have link ids added.
    final saved = _store.task(_sub.id)?.notes;
    if (saved != null && saved != _notes.text) _notes.text = saved;
  }

  void _scheduleNotesSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 500), _saveNotes);
  }

  void _saveNotes() {
    _saveTimer?.cancel();
    _saveTimer = null;
    _store.setNotes(_sub.id, _notes.text);
  }

  // MARK: Pieces

  Widget _checkbox() {
    final label = _sub.isDone
        ? 'Mark ${_sub.title} as not done'
        : 'Mark ${_sub.title} as done';
    void toggle() => _store.toggleDone(taskId: _sub.id);
    return Semantics(
      container: true,
      button: true,
      checked: _sub.isDone,
      label: label,
      onTap: toggle,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          key: ValueKey('sub-check-${_sub.id}'),
          behavior: HitTestBehavior.opaque,
          onTap: toggle,
          child: CheckBox(isOn: _sub.isDone, size: 14),
        ),
      ),
    );
  }

  Widget _details(GroveTheme theme) => Padding(
    padding: const EdgeInsets.only(left: 22),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: 8,
      children: [
        GroveField(
          key: ValueKey('sub-notes-${_sub.id}'),
          controller: _notes,
          focusNode: _notesFocus,
          placeholder: 'Description',
          label: 'Description of ${_sub.title}',
          style: theme.body(12).copyWith(color: theme.ink),
          minLines: 2,
          maxLines: 6,
          boxed: true,
          onChanged: (_) => _scheduleNotesSave(),
        ),
        Row(
          spacing: 8,
          children: [
            Text('Takes', style: theme.body(12).copyWith(color: theme.muted)),
            MenuPick<int>(
              key: ValueKey('sub-length-${_sub.id}'),
              value: _sub.estimateMin,
              values: SubtaskRules.durationsIncluding(_sub.estimateMin),
              name: PlannerMath.duration,
              label: 'Length of ${_sub.title}',
              onPick: (m) => _store.editTask(
                _sub.id,
                (t) => t.copyWith(estimateMin: m),
                name: 'Set Length',
              ),
            ),
            const Spacer(),
            IconTap(
              key: ValueKey('sub-delete-${_sub.id}'),
              icon: Icons.delete_outline,
              label: 'Delete subtask ${_sub.title}',
              tip: 'Delete this subtask',
              color: theme.muted,
              onTap: () => _store.deleteTask(_sub.id),
            ),
          ],
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    final chip = widget.expanded ? null : SubtaskRules.chip(_sub.estimateMin);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: 6,
      children: [
        Row(
          spacing: 8,
          children: [
            _checkbox(),
            Expanded(
              child: GroveField(
                key: ValueKey('sub-title-${_sub.id}'),
                controller: _title,
                focusNode: _titleFocus,
                placeholder: 'Name',
                label: 'Name of the subtask',
                style: theme
                    .body(12)
                    .copyWith(
                      color: _sub.isDone ? theme.muted : theme.ink,
                      decoration: _sub.isDone
                          ? TextDecoration.lineThrough
                          : null,
                      decorationColor: theme.muted,
                    ),
                onSubmitted: (_) => _commitTitle(),
              ),
            ),
            if (chip != null)
              ThemedChip(
                tint: theme.accent2,
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                child: Text(
                  chip,
                  style: theme
                      .body(11, weight: FontWeight.w500)
                      .copyWith(color: theme.accent2),
                ),
              ),
            IconTap(
              key: ValueKey('sub-toggle-${_sub.id}'),
              icon: widget.expanded
                  ? Icons.keyboard_arrow_down
                  : Icons.keyboard_arrow_right,
              size: 14,
              label: widget.expanded
                  ? 'Hide details of ${_sub.title}'
                  : 'Show details of ${_sub.title}',
              tip: widget.expanded
                  ? 'Hide the description and length'
                  : 'Show the description and length',
              color: theme.muted,
              onTap: widget.toggleExpanded,
            ),
          ],
        ),
        if (widget.expanded) _details(theme),
      ],
    );
  }
}
