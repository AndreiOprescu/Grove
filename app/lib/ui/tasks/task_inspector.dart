// Port of Sources/Grove/Tasks/TaskInspector.swift.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:grove/core/model/link.dart';
import 'package:grove/core/model/task.dart';
import 'package:grove/core/planner/planner_math.dart';
import 'package:grove/state/state.dart' hide MotionRules;

import '../editor/rich_text_field.dart';
import '../theme/check_box.dart';
import '../theme/grove_theme.dart';
import '../theme/panel.dart';
import 'subtask_row.dart';
import 'task_widgets.dart';

/// The panel for the chosen task: title, descriptions, plan, details, tags,
/// subtasks and links.
class TaskInspector extends StatefulWidget {
  const TaskInspector({super.key, required this.store, required this.taskId});

  final AppStore store;
  final String taskId;

  /// How wide the panel is at the side of a desktop window.
  static const width = 340.0;

  @override
  State<TaskInspector> createState() => _TaskInspectorState();
}

class _TaskInspectorState extends State<TaskInspector> {
  // What the fields show. The store is only written when the user changes
  // something.
  final _title = TextEditingController();
  final _summary = TextEditingController();
  final _newSubtask = TextEditingController();
  final _newTag = TextEditingController();
  final _titleFocus = FocusNode();
  final _summaryFocus = FocusNode();
  String? _loadedId;

  /// The description, as the editor has it.
  String _notes = '';

  /// True from the first change of the description until the editor loses
  /// the keyboard. In that time the store does not change the text under the
  /// caret (it can add the id of a link to the saved text).
  bool _typing = false;

  /// What the editor of the description asks the store: the `[[` list and
  /// the links. Made one time for each task, and not in `build`. The task
  /// itself is not in its own list.
  late EditorServices _services;
  Timer? _notesTimer;
  Timer? _summaryTimer;

  /// The subtasks that show their description and length.
  Set<String> _openSubtasks = {};

  AppStore get _store => widget.store;
  String get _id => widget.taskId;

  @override
  void initState() {
    super.initState();
    _load(_id);
    _titleFocus.addListener(_titleFocusChanged);
    _summaryFocus.addListener(_summaryFocusChanged);
  }

  @override
  void didUpdateWidget(TaskInspector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.taskId != _id || oldWidget.store != _store) {
      _flushLater(oldWidget.store, oldWidget.taskId);
      _load(_id);
    }
  }

  @override
  void dispose() {
    _flushLater(_store, _id);
    _titleFocus.removeListener(_titleFocusChanged);
    _summaryFocus.removeListener(_summaryFocusChanged);
    for (final c in [_title, _summary, _newSubtask, _newTag]) {
      c.dispose();
    }
    for (final f in [_titleFocus, _summaryFocus]) {
      f.dispose();
    }
    super.dispose();
  }

  // MARK: Loading and saving

  void _load(String id) {
    _services = _store.editorServices(excluding: ItemRef(ItemType.task, id));
    _typing = false;
    final t = _store.task(id);
    if (t == null) return;
    _title.text = t.title;
    _summary.text = t.summary;
    _notes = t.notes;
    _loadedId = id;
    _newSubtask.clear();
    _newTag.clear();
    _openSubtasks = {};
  }

  /// Stops the waiting saves and gives the write of all text of task `id`
  /// that is not saved. null when these fields do not show that task.
  VoidCallback? _takeUnsaved(AppStore store, String id) {
    _notesTimer?.cancel();
    _notesTimer = null;
    _summaryTimer?.cancel();
    _summaryTimer = null;
    if (_loadedId != id) return null;
    final title = _title.text.trim();
    final summary = _summary.text;
    final notes = _notes;
    return () {
      final t = store.task(id);
      if (t == null) return;
      if (SummaryText.clean(summary) != t.summary) {
        store.setSummary(id, summary);
      }
      if (title.isNotEmpty && title != t.title) {
        store.editTask(
          id,
          (t) => t.copyWith(title: title),
          name: 'Rename Task',
        );
      }
      if (notes != t.notes) store.setNotes(id, notes);
    };
  }

  /// Writes any text of the task that is not saved, now.
  void _flush() => _takeUnsaved(_store, _id)?.call();

  /// The same, after the frame in work. For when the panel goes away or
  /// gets a new task.
  void _flushLater(AppStore store, String id) {
    final write = _takeUnsaved(store, id);
    if (write != null) writeLater(store, write);
  }

  /// The store changed: fields the user is not in show the saved text.
  void _storeChanged() {
    final t = _store.task(_id);
    if (t == null || _loadedId != _id) return;
    if (!_titleFocus.hasFocus && t.title != _title.text) _title.text = t.title;
    // The panel builds again after this, so the editor gets the new text.
    if (!_typing && _notesTimer == null) _notes = t.notes;
    if (!_summaryFocus.hasFocus &&
        t.summary != SummaryText.clean(_summary.text)) {
      _summary.text = t.summary;
    }
  }

  void _titleFocusChanged() {
    if (!_titleFocus.hasFocus) _commitTitle();
  }

  void _commitTitle() {
    final name = _title.text.trim();
    if (name.isEmpty) {
      final saved = _store.task(_id)?.title;
      if (saved != null) _title.text = saved;
      return;
    }
    _store.editTask(_id, (t) => t.copyWith(title: name), name: 'Rename Task');
  }

  void _summaryChanged(String text) {
    final id = _id;
    _summaryTimer?.cancel();
    _summaryTimer = Timer(const Duration(milliseconds: 500), () {
      _summaryTimer = null;
      if (_loadedId == id) _store.setSummary(id, _summary.text);
    });
  }

  void _summaryFocusChanged() {
    if (!_summaryFocus.hasFocus) _commitSummary();
  }

  void _commitSummary() {
    _summaryTimer?.cancel();
    _summaryTimer = null;
    if (_loadedId == _id) _store.setSummary(_id, _summary.text);
  }

  void _notesChanged(String text) {
    final id = _id;
    _notes = text;
    _typing = true;
    _notesTimer?.cancel();
    _notesTimer = Timer(const Duration(milliseconds: 500), () {
      _notesTimer = null;
      if (_loadedId == id) _store.setNotes(id, _notes);
    });
  }

  /// The description lost the keyboard: the text is saved, and the editor
  /// shows the saved text. That text can have link ids added.
  void _notesFocusChanged(bool focused) {
    if (focused || !mounted) return;
    _flush();
    final saved = _store.task(_id)?.notes;
    setState(() {
      _typing = false;
      if (saved != null && _loadedId == _id) _notes = saved;
    });
  }

  void _close() => _store.selectedTaskId = null;

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      _close();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // MARK: Content

  Widget _header(GroveTheme theme, TaskItem task) {
    final label = task.isDone ? 'Mark as not done' : 'Mark as done';
    void toggle() => _store.toggleDone(taskId: task.id);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 8,
      children: [
        Tooltip(
          message: label,
          excludeFromSemantics: true,
          child: Semantics(
            container: true,
            button: true,
            checked: task.isDone,
            label: label,
            onTap: toggle,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                key: const ValueKey('inspector-check'),
                behavior: HitTestBehavior.opaque,
                onTap: toggle,
                child: CheckBox(
                  isOn: task.isDone,
                  size: 20,
                  motion: _store.motionSetting,
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: GroveField(
            key: const ValueKey('inspector-title'),
            controller: _title,
            focusNode: _titleFocus,
            placeholder: 'Title',
            label: 'Title',
            style: theme
                .heading(16, weight: FontWeight.w600)
                .copyWith(
                  color: theme.ink,
                  decoration: task.isDone ? TextDecoration.lineThrough : null,
                ),
            maxLines: 4,
            onSubmitted: (_) => _commitTitle(),
          ),
        ),
        IconTap(
          key: const ValueKey('inspector-delete'),
          icon: Icons.delete_outline,
          label: 'Delete task',
          tip:
              'Delete this task, its subtasks and its blocks. You can undo '
              'this.',
          color: theme.muted,
          onTap: () {
            _flush();
            _store.deleteTask(task.id);
          },
        ),
        IconTap(
          key: const ValueKey('inspector-close'),
          icon: Icons.close,
          label: 'Close',
          tip: 'Close  (Esc)',
          color: theme.muted,
          onTap: _close,
        ),
      ],
    );
  }

  Widget _plan(GroveTheme theme, TaskItem task) {
    final date = task.planDate ?? task.planWeek ?? _store.selectedDay;
    final dated =
        task.bucket == TaskBucket.day || task.bucket == TaskBucket.week;
    return _section(theme, 'Plan', [
      Segments<TaskBucket>(
        key: const ValueKey('inspector-plan'),
        value: task.bucket,
        values: const [
          TaskBucket.inbox,
          TaskBucket.day,
          TaskBucket.week,
          TaskBucket.someday,
        ],
        name: (b) => switch (b) {
          TaskBucket.inbox => 'Inbox',
          TaskBucket.day => 'Day',
          TaskBucket.week => 'Week',
          TaskBucket.someday => 'Someday',
        },
        label: 'Plan',
        onPick: (b) => _store.moveTask(
          task.id,
          to: InspectorOptions.placement(bucket: b, date: date),
        ),
      ),
      if (dated)
        Row(
          children: [
            Expanded(
              child: Text(
                task.bucket == TaskBucket.day ? 'Day' : 'Week of',
                style: theme.body(12).copyWith(color: theme.muted),
              ),
            ),
            DayPick(
              key: const ValueKey('inspector-plan-day'),
              day: date,
              label: task.bucket == TaskBucket.day ? 'Day' : 'Week of',
              onPick: (d) => _store.moveTask(
                task.id,
                to: InspectorOptions.placement(bucket: task.bucket, date: d),
              ),
            ),
          ],
        ),
    ]);
  }

  Widget _details(GroveTheme theme, TaskItem task, List<ListItem> lists) {
    final dueDay = InspectorOptions.dueDay(task.due);
    final repeat = RepeatPreset.of(task.recurrence);
    String listName(String id) {
      if (id.isEmpty) return 'No list';
      final l = lists.where((l) => l.id == id).firstOrNull;
      if (l == null) return 'No list';
      return '${l.emoji.isEmpty ? '' : '${l.emoji} '}${l.name}';
    }

    return _section(theme, 'Details', [
      _row(
        theme,
        'Priority',
        SizedBox(
          width: 190,
          child: Segments<int>(
            key: const ValueKey('inspector-priority'),
            value: task.priority,
            values: const [0, 1, 2, 3],
            name: (p) => const ['None', 'Low', 'Med', 'High'][p],
            label: 'Priority',
            onPick: (p) => _store.editTask(
              task.id,
              (t) => t.copyWith(priority: p),
              name: 'Set Priority',
            ),
          ),
        ),
      ),
      _row(
        theme,
        'Colour',
        ColourDots(
          current: task.color,
          onPick: (name) => _store.setTaskColor(task.id, name),
        ),
      ),
      _row(
        theme,
        'Takes',
        MenuPick<int>(
          key: const ValueKey('inspector-length'),
          value: task.estimateMin,
          values: InspectorOptions.estimates(including: task.estimateMin),
          name: PlannerMath.duration,
          label: 'Takes',
          onPick: (m) => _store.editTask(
            task.id,
            (t) => t.copyWith(estimateMin: m),
            name: 'Set Length',
          ),
        ),
      ),
      _row(
        theme,
        'Due',
        dueDay != null
            ? Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 6,
                children: [
                  DayPick(
                    key: const ValueKey('inspector-due'),
                    day: dueDay,
                    label: 'Due',
                    onPick: (d) => _store.editTask(
                      task.id,
                      (t) => t.copyWith(
                        due: InspectorOptions.dueString(
                          d,
                          keepingTimeOf: t.due,
                        ),
                      ),
                      name: 'Set Due Date',
                    ),
                  ),
                  IconTap(
                    key: const ValueKey('inspector-due-clear'),
                    icon: Icons.cancel,
                    label: 'Remove the due date',
                    tip: 'Remove the due date',
                    color: theme.muted,
                    onTap: () => _store.editTask(
                      task.id,
                      (t) => t.copyWith(due: null),
                      name: 'Clear Due Date',
                    ),
                  ),
                ],
              )
            : TextTap(
                key: const ValueKey('inspector-due-add'),
                label: 'Add a due date',
                onTap: () => _store.editTask(
                  task.id,
                  (t) => t.copyWith(
                    due: (task.planDate ?? _store.selectedDay).string,
                  ),
                  name: 'Set Due Date',
                ),
              ),
      ),
      _row(
        theme,
        'Repeat',
        MenuPick<RepeatPreset>(
          key: const ValueKey('inspector-repeat'),
          value: repeat,
          values: [
            for (final p in RepeatPreset.values)
              if (p != RepeatPreset.custom || repeat == RepeatPreset.custom) p,
          ],
          name: (p) => p.label,
          label: 'Repeat',
          onPick: (p) {
            if (p == RepeatPreset.custom) return;
            _store.editTask(
              task.id,
              (t) => t.copyWith(recurrence: p.rule),
              name: 'Set Repeat',
            );
          },
        ),
      ),
      _row(
        theme,
        'List',
        MenuPick<String>(
          key: const ValueKey('inspector-list'),
          value: task.listId ?? '',
          values: ['', for (final l in lists) l.id],
          name: listName,
          label: 'List',
          onPick: (id) => _store.editTask(
            task.id,
            (t) => t.copyWith(listId: id.isEmpty ? null : id),
            name: 'Set List',
          ),
        ),
      ),
    ]);
  }

  Widget _tags(GroveTheme theme, TaskItem task) {
    final names = _store.tagNames(task.id);
    return _section(theme, 'Tags', [
      if (names.isNotEmpty)
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            for (final name in names)
              ThemedChip(
                tint: theme.accent2,
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 3,
                  children: [
                    Text(
                      '#$name',
                      style: theme
                          .body(11, weight: FontWeight.w500)
                          .copyWith(color: theme.accent2),
                    ),
                    IconTap(
                      key: ValueKey('remove-tag-$name'),
                      icon: Icons.close,
                      size: 11,
                      label: 'Remove tag $name',
                      tip: 'Remove this tag',
                      color: theme.accent2,
                      onTap: () => _store.setTags(
                        taskId: task.id,
                        to: [
                          for (final n in names)
                            if (n != name) n,
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      GroveField(
        key: const ValueKey('add-tag'),
        controller: _newTag,
        placeholder: 'Add a tag',
        style: theme.body(12).copyWith(color: theme.ink),
        keepFocus: true,
        onSubmitted: (text) {
          _store.setTags(taskId: task.id, to: [...names, text]);
          _newTag.clear();
        },
      ),
    ]);
  }

  Widget _subtasks(GroveTheme theme, TaskItem task) {
    final subs = _store.subtasks(task.id);
    return _section(theme, SubtaskRules.header(subs), [
      for (final sub in subs)
        SubtaskRow(
          key: ValueKey('sub-${sub.id}'),
          store: _store,
          sub: sub,
          expanded: _openSubtasks.contains(sub.id),
          toggleExpanded: () => setState(() {
            if (!_openSubtasks.remove(sub.id)) _openSubtasks.add(sub.id);
          }),
        ),
      Row(
        spacing: 8,
        children: [
          Icon(Icons.add, size: 13, color: theme.muted),
          Expanded(
            child: GroveField(
              key: const ValueKey('inspector-add-subtask'),
              controller: _newSubtask,
              placeholder: 'Add a subtask',
              style: theme.body(12).copyWith(color: theme.ink),
              keepFocus: true,
              onSubmitted: (_) => _addSubtask(task.id),
            ),
          ),
        ],
      ),
    ]);
  }

  /// Adds the typed subtask. It opens at once, and the others close, so
  /// its description and length can be set.
  void _addSubtask(String id) {
    final added = _store.addSubtask(to: id, title: _newSubtask.text);
    if (added == null) return;
    _newSubtask.clear();
    setState(() => _openSubtasks = {added});
  }

  Widget? _links(GroveTheme theme, TaskItem task) {
    final here = _store.repos.links.backlinks(ItemRef(ItemType.task, task.id));
    final sourceId = task.sourceNoteId;
    final source = sourceId == null ? null : _store.repos.notes.get(sourceId);
    if (here.isEmpty && source == null) return null;
    return _section(theme, 'Linked here', [
      if (source != null)
        _linkRow(
          theme,
          Icons.sticky_note_2_outlined,
          'Created from note “${source.title}”',
          () => _store.open(ItemRef(ItemType.note, source.id)),
        ),
      for (final ref in here)
        if (_store.repos.refs.resolveTitle('', id: ref.id) case final target?)
          _linkRow(
            theme,
            switch (ref.type) {
              ItemType.task => Icons.check_circle_outline,
              ItemType.note => Icons.sticky_note_2_outlined,
              ItemType.event => Icons.calendar_today_outlined,
            },
            target.title,
            () => _store.open(ref),
          ),
    ]);
  }

  Widget _linkRow(
    GroveTheme theme,
    IconData icon,
    String text,
    VoidCallback action,
  ) => Semantics(
    container: true,
    button: true,
    label: text,
    onTap: action,
    excludeSemantics: true,
    child: MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: action,
        child: Row(
          spacing: 8,
          children: [
            Icon(icon, size: 13, color: theme.accent),
            Expanded(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.body(12).copyWith(color: theme.ink),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  // MARK: Pieces

  Widget _section(GroveTheme theme, String name, List<Widget> children) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: 8,
        children: [
          ThemedHeading(name, 12, weight: FontWeight.w700, color: theme.ink),
          ...children,
        ],
      );

  Widget _row(GroveTheme theme, String label, Widget child) => Row(
    spacing: 8,
    children: [
      SizedBox(
        width: 60,
        child: Text(
          label,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.clip,
          style: theme.body(12).copyWith(color: theme.muted),
        ),
      ),
      Expanded(
        child: Align(alignment: Alignment.centerRight, child: child),
      ),
    ],
  );

  Widget _content(GroveTheme theme, TaskItem task) {
    final lists = _store.repos.lists.all();
    final links = _links(theme, task);
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          spacing: 16,
          children: [
            _header(theme, task),
            _section(theme, 'Short description', [
              GroveField(
                key: const ValueKey('inspector-summary'),
                controller: _summary,
                focusNode: _summaryFocus,
                placeholder: 'One short line. It shows on the planner.',
                label: 'Short description',
                maxLines: 3,
                maxLength: SummaryText.maxLength,
                boxed: true,
                onChanged: _summaryChanged,
                onSubmitted: (_) => _commitSummary(),
              ),
            ]),
            _section(theme, 'Description', [
              KeyedSubtree(
                key: const ValueKey('inspector-notes'),
                // A new editor for each task: the caret, the open `[[` list
                // and the undo steps of one task do not go to the next one.
                child: RichTextField(
                  key: ValueKey(_id),
                  text: _notes,
                  services: _services,
                  placeholder:
                      'The longer description. Type [[ to mention a task.',
                  minHeight: 90,
                  label: 'Description',
                  onChanged: _notesChanged,
                  onFocusChange: _notesFocusChanged,
                ),
              ),
            ]),
            _plan(theme, task),
            _details(theme, task, lists),
            _tags(theme, task),
            _subtasks(theme, task),
            ?links,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => StoreBuilder(
    store: _store,
    onChange: _storeChanged,
    builder: (context) {
      final theme = GroveTheme.of(context);
      final task = _store.task(_id);
      return Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: _key,
        child: Panel(
          key: const ValueKey('inspector'),
          child: task == null
              ? Center(
                  child: Text(
                    'This task is gone.',
                    style: theme.body(13).copyWith(color: theme.muted),
                  ),
                )
              : _content(theme, task),
        ),
      );
    },
  );
}
