// Port of Sources/Grove/Calendar/EventEditor.swift: the card to make or
// change an event. Nothing is saved until Save.
//
// The Mac app shows it as a popover on the event. Here it is a card in the
// middle of the screen, over a dim layer: a popover has no room on a phone.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:grove/core/model/day_key.dart';
import 'package:grove/core/model/event.dart';
import 'package:grove/core/model/link.dart';
import 'package:grove/core/model/recurrence.dart';
import 'package:grove/core/planner/planner_math.dart';
import 'package:grove/core/recurrence/recurrence_engine.dart';
import 'package:grove/state/state.dart' hide MotionRules;

import '../editor/rich_text_field.dart';
import '../planner/kind_switch.dart';
import '../planner/planner_dialogs.dart' show showRecurringQuestion;
import '../tasks/task_widgets.dart';
import '../shell/shell_layout.dart';
import '../theme/grove_theme.dart';
import '../theme/named_colors.dart';
import '../theme/panel.dart';
import '../theme/symbols.dart';

/// Shows `child`, and the event editor over it while the store has an event
/// in `editingEvent`.
///
/// On a wide window the card is at the top right and the screen under it
/// still works, as with the popover of the Mac app: the keys stay with the
/// planner, and a click on the screen closes a card with no unsaved change.
/// On a phone the card is in the middle, over a dim layer.
class EventEditorHost extends StatefulWidget {
  const EventEditorHost({
    super.key,
    required this.store,
    required this.child,
    this.asksScope = false,
  });

  final AppStore store;
  final Widget child;

  /// True on a screen with no planner under the card (the Notes screen).
  /// The planner asks "This event only" or "All events" for a day of a
  /// series. With no planner, the host asks.
  final bool asksScope;

  @override
  State<EventEditorHost> createState() => _EventEditorHostState();
}

class _EventEditorHostState extends State<EventEditorHost> {
  /// True when the open card has a change that is not saved.
  bool _dirty = false;

  /// True while the question of a series is open.
  bool _asking = false;

  AppStore get _store => widget.store;

  @override
  void initState() {
    super.initState();
    _store.addListener(_storeChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _ask());
  }

  @override
  void didUpdateWidget(EventEditorHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      oldWidget.store.removeListener(_storeChanged);
      widget.store.addListener(_storeChanged);
    }
  }

  @override
  void dispose() {
    _store.removeListener(_storeChanged);
    super.dispose();
  }

  /// A change can come in the middle of a frame. A window opens after it.
  void _storeChanged() {
    if (!widget.asksScope || _store.recurringPrompt == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _ask());
    WidgetsBinding.instance.scheduleFrame();
  }

  Future<void> _ask() async {
    if (!mounted || !widget.asksScope || _asking) return;
    final prompt = _store.recurringPrompt;
    if (prompt == null) return;
    _asking = true;
    final scope = await showRecurringQuestion(context, prompt.verb);
    _asking = false;
    if (scope != null) {
      _store.answerRecurring(scope, prompt: prompt);
    } else if (_store.recurringPrompt?.id == prompt.id) {
      _store.cancelRecurring();
    }
    unawaited(_ask());
  }

  @override
  Widget build(BuildContext context) => StoreBuilder(
    store: _store,
    builder: (context) {
      final asked = _store.editingEvent;
      var editing = asked;
      if (asked != null &&
          !asked.isNew &&
          _store.event(asked.item.id) == null) {
        // The event went away under the card, for example with Delete.
        writeLater(_store, () {
          if (identical(_store.editingEvent, asked)) _store.closeEditor();
        });
        editing = null;
      }
      if (editing == null) _dirty = false;
      final phone =
          ShellRules.layoutFor(MediaQuery.sizeOf(context).width) ==
          ShellLayout.phone;
      final open = editing != null;
      return CallbackShortcuts(
        bindings: {
          if (open)
            const SingleActivator(LogicalKeyboardKey.escape):
                _store.closeEditor,
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (_) {
                if (_store.editingEvent != null && !_dirty) {
                  _store.closeEditor();
                }
              },
              child: widget.child,
            ),
            if (editing != null) ...[
              if (phone)
                Positioned.fill(
                  child: Semantics(
                    label: 'Close the event',
                    button: true,
                    onTap: _store.closeEditor,
                    child: GestureDetector(
                      key: const ValueKey('event-editor-scrim'),
                      behavior: HitTestBehavior.opaque,
                      onTap: _store.closeEditor,
                      child: const ColoredBox(color: Color(0x40000000)),
                    ),
                  ),
                ),
              Positioned.fill(
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Align(
                      alignment: phone ? Alignment.center : Alignment.topRight,
                      child: EventEditor(
                        key: ValueKey(
                          'event-editor-${editing.anchor}-${editing.item.id}',
                        ),
                        store: _store,
                        editing: editing,
                        onDirty: (dirty) => _dirty = dirty,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    },
  );
}

class EventEditor extends StatefulWidget {
  const EventEditor({
    super.key,
    required this.store,
    required this.editing,
    this.onDirty,
  });

  final AppStore store;
  final EditingEvent editing;

  /// Called when the card gets, or loses, a change that is not saved.
  final ValueChanged<bool>? onDirty;

  static const width = 360.0;
  static const labelWidth = 52.0;

  @override
  State<EventEditor> createState() => _EventEditorState();
}

class _EventEditorState extends State<EventEditor> {
  /// The draft of each open card. A change of screen makes a new card for
  /// the same `EditingEvent`, and the card must not lose what was typed.
  static final _drafts = Expando<EventItem>('event drafts');

  late EventItem _draft;

  /// The event as the store has it. The card is "dirty" when the draft is
  /// not the same.
  late EventItem _base;
  late final TextEditingController _title;
  late final TextEditingController _location;

  AppStore get _store => widget.store;
  EditingEvent get _editing => widget.editing;

  EventItem? get _original =>
      _editing.isNew ? null : _store.event(_editing.item.id);
  bool get _isDayOfSeries => OccurrenceId.parse(_editing.item.id) != null;
  bool get _isDirty => _draft != _base;

  EventItem get _stored {
    final original = _original;
    return original == null ? _editing.item : _store.draft(original);
  }

  /// What other items link to. A day of a repeating event stands for the
  /// whole series.
  ItemRef get _linkRef =>
      ItemRef(ItemType.event, MeetingNote.linkId(_editing.item));

  @override
  void initState() {
    super.initState();
    _draft = _drafts[_editing] ?? _editing.item;
    _base = _stored;
    _title = TextEditingController(text: _draft.title);
    _location = TextEditingController(text: _draft.location);
    widget.onDirty?.call(_isDirty);
  }

  /// The event can change under the card: the arrows or a drag move it, Undo
  /// puts it back. The card follows the event in each field that the user did
  /// not change in the card. So Save does not put an old time back.
  @override
  void didUpdateWidget(EventEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    final stored = _stored;
    if (stored == _base) return;
    final mine = _draft;
    final was = _base;
    final next = stored.copyWith(
      title: mine.title != was.title ? mine.title : stored.title,
      start: mine.start != was.start ? mine.start : stored.start,
      end: mine.end != was.end ? mine.end : stored.end,
      allDay: mine.allDay != was.allDay ? mine.allDay : stored.allDay,
      color: mine.color != was.color ? mine.color : stored.color,
      location: mine.location != was.location ? mine.location : stored.location,
      notes: mine.notes != was.notes ? mine.notes : stored.notes,
      recurrence: mine.recurrence != was.recurrence
          ? mine.recurrence
          : stored.recurrence,
      isDeadline: mine.isDeadline != was.isDeadline
          ? mine.isDeadline
          : stored.isDeadline,
      doneAt: mine.doneAt != was.doneAt ? mine.doneAt : stored.doneAt,
    );
    _draft = next;
    _drafts[_editing] = next;
    if (_title.text != next.title) _title.text = next.title;
    if (_location.text != next.location) _location.text = next.location;
    _base = stored;
    widget.onDirty?.call(_isDirty);
  }

  @override
  void dispose() {
    _title.dispose();
    _location.dispose();
    super.dispose();
  }

  void _set(EventItem draft) {
    // A picker can answer after the card is gone.
    if (!mounted) return;
    final next = _fit(draft);
    setState(() => _draft = next);
    _drafts[_editing] = next;
    widget.onDirty?.call(_isDirty);
  }

  /// The day of the end is not before the day of the start. The last day of
  /// a repeat is not before the day of the event: such an event would be on
  /// no screen, with no way to open it again.
  static EventItem _fit(EventItem e) {
    var next = e;
    if (next.end.day < next.start.day) {
      next = next.copyWith(end: next.end.copyWith(day: next.start.day));
    }
    final rule = next.recurrence;
    final until = rule?.until;
    if (rule != null && until != null && until < next.start.day) {
      next = next.copyWith(recurrence: rule.copyWith(until: next.start.day));
    }
    return next;
  }

  void _save() {
    final original = _original;
    if (_editing.isNew) {
      _store.saveEvent(_draft, from: null);
    } else if (original != null) {
      _store.saveEvent(_draft, from: original);
    } else {
      _store.closeEditor(); // the event is gone
    }
  }

  /// An activity that is saved can turn into a task: the "Task" chip.
  bool get _canBeTask =>
      !_editing.isNew &&
      _draft.isActivity &&
      _store.kindSwitch(_editing.item.id) == EventKind.block;

  /// Saves the changes of the card first, then makes the activity a task.
  /// The card closes and the task panel opens.
  void _turnIntoTask() {
    final id = _editing.item.id;
    final original = _original;
    if (_isDirty && original != null) _store.saveEvent(_draft, from: original);
    if (_store.kindSwitch(id) != EventKind.block) {
      _store.closeEditor();
      _store.showToast(
        'This activity cannot be a task: it repeats, is all day or goes past '
        'midnight.',
      );
      return;
    }
    _store.toggleKind(id);
  }

  // Build

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    final apple =
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.iOS;
    final rule = _draft.recurrence;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): _store.closeEditor,
        SingleActivator(LogicalKeyboardKey.enter, meta: apple, control: !apple):
            _save,
      },
      child: FocusTraversalGroup(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: EventEditor.width),
          child: Semantics(
            container: true,
            scopesRoute: true,
            explicitChildNodes: true,
            label: switch ((_editing.isNew, _draft.isActivity)) {
              (true, true) => 'New activity',
              (false, true) => 'Activity',
              (true, false) => 'New event',
              (false, false) => 'Event',
            },
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: theme.surface,
                borderRadius: BorderRadius.circular(theme.radius),
                border: Border.all(color: theme.line),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 24,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(theme.radius),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: DefaultTextStyle(
                    style: theme.body(12).copyWith(color: theme.ink),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: 12,
                      children: [
                        GroveField(
                          key: const ValueKey('event-title'),
                          controller: _title,
                          placeholder: _draft.isActivity
                              ? 'Activity title'
                              : 'Event title',
                          autofocus: _editing.isNew,
                          padding: EdgeInsets.zero,
                          style: theme.heading(20).copyWith(color: theme.ink),
                          onChanged: (text) =>
                              _set(_draft.copyWith(title: text)),
                          onSubmitted: (_) => _save(),
                          onEscape: _store.closeEditor,
                        ),
                        if (_canBeTask)
                          _row(
                            theme,
                            'Type',
                            KindChips(
                              keyPrefix: 'event-kind',
                              activity: true,
                              onPick: (activity) {
                                if (!activity) _turnIntoTask();
                              },
                            ),
                          ),
                        Row(
                          spacing: 20,
                          children: [
                            _allDay(theme),
                            if (_canBeDeadline) _deadline(theme),
                          ],
                        ),
                        _dateRow(theme, 'Starts', _draft.start, (to) {
                          _set(EventDraft.setStart(_draft, to));
                        }),
                        _dateRow(theme, 'Ends', _draft.end, (to) {
                          _set(_draft.copyWith(end: to));
                        }),
                        _colours(theme),
                        _row(
                          theme,
                          'Location',
                          Expanded(
                            child: GroveField(
                              key: const ValueKey('event-location'),
                              controller: _location,
                              placeholder: '',
                              label: 'Location',
                              boxed: true,
                              onChanged: (text) =>
                                  _set(_draft.copyWith(location: text)),
                              onEscape: _store.closeEditor,
                            ),
                          ),
                        ),
                        _notes(theme),
                        ..._linked(theme),
                        if (!_draft.isDeadline) ..._repeat(theme, rule),
                        if (_isDayOfSeries)
                          Text(
                            'When you save, Grove asks if the change is for '
                            'this event only or all events.',
                            style: theme.body(11).copyWith(color: theme.muted),
                          ),
                        _buttons(theme),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(GroveTheme theme, String text) => SizedBox(
    width: EventEditor.labelWidth,
    child: Text(
      text,
      maxLines: 1,
      style: theme.body(12).copyWith(color: theme.muted),
    ),
  );

  Widget _row(GroveTheme theme, String label, Widget field) =>
      Row(children: [_label(theme, label), field]);

  // Rows

  Widget _allDay(GroveTheme theme) => _switch(
    theme,
    label: 'All day',
    key: const ValueKey('event-all-day'),
    on: _draft.allDay,
    onTap: () => _set(EventDraft.setAllDay(_draft, !_draft.allDay)),
  );

  /// Only a plain event that does not repeat can be a deadline: a tick is
  /// for one event, not for each day of a series.
  bool get _canBeDeadline =>
      _draft.kind == EventKind.event &&
      _draft.goalId == null &&
      _draft.recurrence == null &&
      !_isDayOfSeries;

  Widget _deadline(GroveTheme theme) => _switch(
    theme,
    label: 'Deadline',
    key: const ValueKey('event-deadline'),
    on: _draft.isDeadline,
    onTap: () => _set(EventDraft.setDeadline(_draft, !_draft.isDeadline)),
  );

  Widget _switch(
    GroveTheme theme, {
    required String label,
    required Key key,
    required bool on,
    required VoidCallback onTap,
  }) {
    return Semantics(
      container: true,
      toggled: on,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          key: key,
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 8,
            children: [
              Text(label, style: theme.body(12).copyWith(color: theme.ink)),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: on ? theme.accent : theme.line,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: SizedBox(
                  width: 30,
                  height: 18,
                  child: Align(
                    alignment: on
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: theme.surface,
                          shape: BoxShape.circle,
                        ),
                        child: const SizedBox(width: 14, height: 14),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dateRow(
    GroveTheme theme,
    String label,
    WallTime value,
    ValueChanged<WallTime> onPick,
  ) => Row(
    spacing: 6,
    children: [
      _label(theme, label),
      const Spacer(),
      DayPick(
        key: ValueKey('event-${label.toLowerCase()}-day'),
        day: value.day,
        label: '$label, day',
        onPick: (day) => onPick(value.copyWith(day: day)),
      ),
      if (!_draft.allDay)
        _TimePick(
          key: ValueKey('event-${label.toLowerCase()}-time'),
          minute: value.minute,
          label: '$label, time',
          onPick: (minute) => onPick(value.copyWith(minute: minute)),
        ),
    ],
  );

  Widget _colours(GroveTheme theme) => Row(
    children: [
      _label(theme, 'Colour'),
      for (final name in NamedColors.blockColorNames)
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Tooltip(
            message: name[0].toUpperCase() + name.substring(1),
            excludeFromSemantics: true,
            child: Semantics(
              container: true,
              button: true,
              selected: _draft.color == name,
              label: 'Colour $name',
              onTap: () => _set(_draft.copyWith(color: name)),
              excludeSemantics: true,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  key: ValueKey('event-colour-$name'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _set(_draft.copyWith(color: name)),
                  child: Container(
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: _draft.color == name
                          ? Border.all(color: theme.ink, width: 2)
                          : null,
                    ),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: theme.color(name),
                      ),
                      child: const SizedBox.square(dimension: 18),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
    ],
  );

  /// The same editor as tasks and notes. A click on a link opens it only
  /// when nothing is unsaved here, because opening a link closes this card.
  /// One object for the life of the card: a new one would make the editor
  /// read the state of each link again.
  late final EditorServices _services = _makeServices();

  EditorServices _makeServices() {
    final s = _store.editorServices(excluding: _linkRef);
    return EditorServices(
      suggest: s.suggest,
      isLive: s.isLive,
      title: s.title,
      storeImage: s.storeImage,
      loadImage: s.loadImage,
      notify: s.notify,
      showMarks: s.showMarks,
      open: (id, title) {
        if (_isDirty) {
          _store.showToast('Save the event first. Then open the link.');
          return;
        }
        _store
          ..closeEditor()
          ..openMention(id: id, title: title);
      },
    );
  }

  Widget _notes(GroveTheme theme) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: 4,
    children: [
      Text('Notes', style: theme.body(12).copyWith(color: theme.muted)),
      RichTextField(
        key: const ValueKey('event-notes'),
        text: _draft.notes,
        services: _services,
        placeholder: 'Notes. Type [[ to link something.',
        minHeight: 64,
        onChanged: (text) => _set(_draft.copyWith(notes: text)),
      ),
    ],
  );

  // Meeting note and links

  static String _icon(ItemType type) => switch (type) {
    ItemType.task => 'checkmark.circle',
    ItemType.note => 'note.text',
    ItemType.event => 'calendar',
  };

  void _openMeetingNote(EventItem event) {
    if (_isDirty) {
      _store.showToast('Save the event first. Then make the note.');
      return;
    }
    _store
      ..closeEditor()
      ..createMeetingNote(event);
  }

  void _openLinked(ItemRef ref) {
    if (_isDirty) {
      _store.showToast('Save the event first. Then open the link.');
      return;
    }
    _store
      ..closeEditor()
      ..open(ref);
  }

  List<Widget> _linked(GroveTheme theme) {
    final original = _original;
    if (_editing.isNew || original == null) return const [];
    final here = _store.linkedItems(_linkRef);
    final meeting = _store.meetingNote(original);
    return [
      Align(
        alignment: Alignment.centerLeft,
        child: Tooltip(
          message: meeting == null
              ? 'Make a note for this event, with a place for the agenda '
                    'and action items'
              : 'Show the note of this event',
          excludeFromSemantics: true,
          child: CardButton(
            key: const ValueKey('event-meeting-note'),
            label: meeting == null
                ? 'Create meeting note'
                : 'Open meeting note',
            onTap: () => _openMeetingNote(original),
          ),
        ),
      ),
      if (here.isNotEmpty)
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 6,
          children: [
            const ThemedHeading('Linked here', 12, weight: FontWeight.w700),
            for (final item in here)
              Semantics(
                container: true,
                button: true,
                label: item.title,
                onTap: () => _openLinked(item.ref),
                excludeSemantics: true,
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    key: ValueKey('event-linked-${item.id}'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _openLinked(item.ref),
                    child: Row(
                      spacing: 8,
                      children: [
                        Icon(
                          symbolIcon(_icon(item.ref.type)),
                          size: 14,
                          color: theme.accent,
                        ),
                        Expanded(
                          child: Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.body(12).copyWith(color: theme.ink),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
    ];
  }

  // Repeat

  /// The repeat rule without its end. The preset list only knows plain rules.
  RecurrenceRule? get _plainRule =>
      _draft.recurrence?.copyWith(until: null, count: null);

  void _setRule(RecurrenceRule? rule) =>
      _set(_draft.copyWith(recurrence: rule));

  void _setPreset(RepeatPreset preset) {
    if (preset == RepeatPreset.custom) return;
    final old = _draft.recurrence;
    _setRule(preset.rule?.copyWith(until: old?.until, count: old?.count));
  }

  void _setEnds(RepeatEnds ends) {
    final rule = _draft.recurrence;
    if (rule == null) return;
    _setRule(switch (ends) {
      RepeatEnds.never => rule.copyWith(until: null, count: null),
      RepeatEnds.on => rule.copyWith(
        until: _draft.start.day.adding(days: 30),
        count: null,
      ),
      RepeatEnds.after => rule.copyWith(until: null, count: 10),
    });
  }

  List<Widget> _repeat(GroveTheme theme, RecurrenceRule? rule) {
    final plain = _plainRule;
    final current = RepeatPreset.of(plain);
    return [
      _row(
        theme,
        'Repeat',
        Flexible(
          child: MenuPick<RepeatPreset>(
            key: const ValueKey('event-repeat'),
            value: current,
            values: [
              if (current == RepeatPreset.custom) RepeatPreset.custom,
              for (final p in RepeatPreset.values)
                if (p != RepeatPreset.custom) p,
            ],
            name: (p) => p == RepeatPreset.custom && plain != null
                ? EventDraft.repeatLabel(plain)
                : p.label,
            label: 'Repeat',
            onPick: _setPreset,
          ),
        ),
      ),
      if (rule != null && rule.freq == Freq.weekly) _weekdays(theme, rule),
      if (rule != null)
        Row(
          spacing: 6,
          children: [
            _label(theme, 'Ends'),
            MenuPick<RepeatEnds>(
              key: const ValueKey('event-ends'),
              value: EventDraft.ends(rule),
              values: RepeatEnds.values,
              name: (e) => switch (e) {
                RepeatEnds.never => 'Never',
                RepeatEnds.on => 'On a day',
                RepeatEnds.after => 'After',
              },
              label: 'Ends',
              onPick: _setEnds,
            ),
            ..._endsDetail(theme, rule),
          ],
        ),
    ];
  }

  /// M T W T F S S. The first event's own weekday is on when there is no
  /// list.
  Widget _weekdays(GroveTheme theme, RecurrenceRule rule) {
    // The card of a later day of a series: the first event is the one of
    // the series, not the day in the card.
    final series = OccurrenceId.parse(_editing.item.id)?.series;
    final first = series == null ? null : _store.event(series);
    final start = (first ?? _draft).start.day.weekdayIndex;
    final on = {
      ...(rule.weekdays ?? [start]),
    };
    return Row(
      children: [
        _label(theme, 'On'),
        for (var d = 1; d <= 7; d++)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Semantics(
              container: true,
              button: true,
              selected: on.contains(d),
              label: NotesRules.weekdays[d - 1],
              onTap: () =>
                  _setRule(EventDraft.toggleWeekday(rule, d, start: start)),
              excludeSemantics: true,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  key: ValueKey('event-weekday-$d'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () =>
                      _setRule(EventDraft.toggleWeekday(rule, d, start: start)),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: on.contains(d)
                          ? theme.accent
                          : theme.line.withValues(alpha: 0.5),
                    ),
                    child: SizedBox.square(
                      dimension: 24,
                      child: Center(
                        child: Text(
                          NotesRules.weekdays[d - 1][0],
                          style: theme
                              .body(11, weight: FontWeight.w600)
                              .copyWith(
                                color: on.contains(d)
                                    ? theme.surface
                                    : theme.ink,
                              ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  List<Widget> _endsDetail(GroveTheme theme, RecurrenceRule rule) {
    final until = rule.until;
    final count = rule.count;
    if (until != null) {
      return [
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: DayPick(
              key: const ValueKey('event-until'),
              day: until,
              label: 'Last day',
              onPick: (day) => _setRule(rule.copyWith(until: day)),
            ),
          ),
        ),
      ];
    }
    if (count != null) {
      void step(int by) =>
          _setRule(rule.copyWith(count: (count + by).clamp(1, 999)));
      return [
        IconTap(
          key: const ValueKey('event-count-less'),
          icon: Icons.remove,
          label: 'One time less',
          onTap: () => step(-1),
        ),
        Text(
          '$count time${count == 1 ? '' : 's'}',
          key: const ValueKey('event-count'),
          style: theme.body(12).copyWith(color: theme.ink),
        ),
        IconTap(
          key: const ValueKey('event-count-more'),
          icon: Icons.add,
          label: 'One time more',
          onTap: () => step(1),
        ),
      ];
    }
    return const [];
  }

  // Buttons

  Widget _buttons(GroveTheme theme) {
    final original = _original;
    return Row(
      spacing: 8,
      children: [
        if (original != null)
          CardButton(
            key: const ValueKey('event-delete'),
            label: 'Delete',
            onTap: () => _store.deleteEvent(original),
          ),
        const Spacer(),
        CardButton(
          key: const ValueKey('event-cancel'),
          label: 'Cancel',
          onTap: _store.closeEditor,
        ),
        Tooltip(
          message: 'Save',
          excludeFromSemantics: true,
          child: CardButton(
            key: const ValueKey('event-save'),
            label: 'Save',
            primary: true,
            onTap: _save,
          ),
        ),
      ],
    );
  }
}

/// A time of the day. A click opens the time picker.
class _TimePick extends StatelessWidget {
  const _TimePick({
    super.key,
    required this.minute,
    required this.label,
    required this.onPick,
  });

  /// Minutes since midnight.
  final int minute;

  /// What a screen reader says in front of the time.
  final String label;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    final text = PlannerMath.clock(minute);
    Future<void> open() async {
      final picked = await showTimePicker(
        context: context,
        initialTime: TimeOfDay(hour: minute ~/ 60 % 24, minute: minute % 60),
        initialEntryMode: TimePickerEntryMode.input,
        // The app shows 24 hour times in each place.
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        ),
      );
      if (picked != null) onPick(picked.hour * 60 + picked.minute);
    }

    return Semantics(
      container: true,
      button: true,
      label: label,
      value: text,
      onTap: open,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: open,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: theme.surface2,
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: theme.line),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              child: Text(
                text,
                maxLines: 1,
                style: theme.number(12).copyWith(color: theme.ink),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
