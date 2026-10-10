// Port of Sources/Grove/Tasks/QuickAddField.swift.
import 'package:flutter/material.dart';
import 'package:grove/core/parsing/quick_add_parser.dart';
import 'package:grove/state/state.dart' hide MotionRules;

import '../planner/inline_title_field.dart' show BlurAction, InlineTitleRules;
import '../theme/grove_theme.dart';
import 'task_format.dart';
import 'task_widgets.dart';

/// One line to add a task. It shows what the parser understood while the
/// user types.
class QuickAddField extends StatefulWidget {
  const QuickAddField({
    super.key,
    required this.store,
    required this.placement,
    required this.placementLabel,
  });

  final AppStore store;

  /// Where a task goes when the text names no date.
  final TaskPlacement placement;
  final String placementLabel;

  static const hint = 'Try “Call mum tomorrow 6pm for 20m #home /Errands !2”';

  @override
  State<QuickAddField> createState() => _QuickAddFieldState();
}

class _QuickAddFieldState extends State<QuickAddField> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  late int _requestSeen = widget.store.quickAddRequest;

  AppStore get _store => widget.store;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_focusChanged);
    _store.addListener(_storeChanged);
    if (_store.quickAddRequest != _store.quickAddHandled) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _takeRequest());
    }
  }

  @override
  void didUpdateWidget(QuickAddField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      oldWidget.store.removeListener(_storeChanged);
      widget.store.addListener(_storeChanged);
      _requestSeen = widget.store.quickAddRequest;
    }
  }

  @override
  void dispose() {
    _store.removeListener(_storeChanged);
    _focus.removeListener(_focusChanged);
    _focus.dispose();
    _text.dispose();
    super.dispose();
  }

  void _storeChanged() {
    if (_store.quickAddRequest == _requestSeen) return;
    _requestSeen = _store.quickAddRequest;
    _takeRequest();
  }

  /// "New task" from the palette or a shortcut: the field takes the keys.
  void _takeRequest() {
    if (!mounted) return;
    _store.quickAddHandled = _store.quickAddRequest;
    _focus.requestFocus();
  }

  void _focusChanged() {
    if (!mounted) return;
    if (!_focus.hasFocus &&
        InlineTitleRules.onBlur(_text.text) == BlurAction.commit) {
      _save();
    }
    setState(() {});
  }

  /// Saves the text as a task. Also used when focus leaves the field.
  bool _save() {
    final task = _store.quickAdd(_text.text, placement: widget.placement);
    if (task == null) return false;
    _text.clear();
    final landed = TaskFormat.placeLabel(task, today: _store.clockToday);
    if (landed != widget.placementLabel) _store.showToast('Added to $landed');
    if (mounted) setState(() {});
    return true;
  }

  void _escape() {
    _text.clear();
    _focus.unfocus();
    setState(() {});
  }

  Widget _preview(GroveTheme theme) {
    final lists = [for (final l in _store.repos.lists.all()) l.name];
    final result = QuickAddParser(
      today: _store.clockToday,
      lists: lists,
    ).parse(_text.text);
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        if (!result.chips.any((c) => c.kind == ChipKind.date))
          TaskChip(
            widget.placementLabel,
            icon: Icons.inbox_outlined,
            tint: theme.accent,
          ),
        for (final chip in result.chips)
          TaskChip(
            chip.text,
            icon: TaskFormat.icon(chip.kind),
            tint: theme.accent,
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    final empty = trimSpaces(_text.text).isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      spacing: 6,
      children: [
        GroveField(
          key: const ValueKey('quick-add'),
          controller: _text,
          focusNode: _focus,
          placeholder: 'Add a task…',
          boxed: true,
          radius: 10,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          leading: Icon(Icons.add_circle, size: 16, color: theme.accent),
          keepFocus: true,
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _save(),
          onEscape: _escape,
        ),
        if (!empty)
          _preview(theme)
        else if (_focus.hasFocus)
          Text(
            QuickAddField.hint,
            style: theme.body(10).copyWith(color: theme.muted),
          ),
      ],
    );
  }
}
