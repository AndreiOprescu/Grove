// Ports of Sources/Grove/Shared/InlineTitleRules.swift and of
// `InlineTitleField` in Sources/Grove/Planner/BlockView.swift.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/grove_theme.dart';

enum BlurAction { commit, cancel }

/// What a title field does when focus leaves it without Return or Esc.
abstract final class InlineTitleRules {
  /// Text that is new is kept. Empty text, or the title the field started
  /// with, is dropped.
  static BlurAction onBlur(String text, {String initial = ''}) {
    final now = text.trim();
    return now.isEmpty || now == initial.trim()
        ? BlurAction.cancel
        : BlurAction.commit;
  }
}

/// True while the key for "the other kind" is down: Command on Apple
/// devices, Ctrl on the others.
bool commandHeld() {
  final apple =
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.iOS;
  final keys = HardwareKeyboard.instance;
  return apple ? keys.isMetaPressed : keys.isControlPressed;
}

/// A text field that takes the keys when it appears. Return saves. Esc
/// cancels. A click away saves what was typed, or cancels when there is
/// nothing to save.
class InlineTitleField extends StatefulWidget {
  const InlineTitleField({
    super.key,
    this.initial = '',
    required this.placeholder,
    this.onChanged,
    required this.onCommit,
    this.onBlurCommit,
    required this.onCancel,
  });

  final String initial;
  final String placeholder;
  final ValueChanged<String>? onChanged;

  /// Return. `command` is true when Command (or Ctrl) was down.
  final void Function(String text, bool command) onCommit;

  /// Saves on blur. Without it, blur calls `onCommit(text, false)`.
  final ValueChanged<String>? onBlurCommit;
  final VoidCallback onCancel;

  @override
  State<InlineTitleField> createState() => _InlineTitleFieldState();
}

class _InlineTitleFieldState extends State<InlineTitleField> {
  late final _text = TextEditingController(text: widget.initial);
  late final _focus = FocusNode(onKeyEvent: _key);

  /// Set by the first of Return, Esc or blur, so the others do nothing.
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _text.selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.initial.length,
    );
    _focus.addListener(_focusChanged);
  }

  @override
  void dispose() {
    _focus.removeListener(_focusChanged);
    _focus.dispose();
    _text.dispose();
    super.dispose();
  }

  void _finish(VoidCallback action) {
    if (_finished) return;
    _finished = true;
    action();
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      _finish(widget.onCancel);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _focusChanged() {
    if (_focus.hasFocus) return;
    _finish(() {
      final text = _text.text;
      switch (InlineTitleRules.onBlur(text, initial: widget.initial)) {
        case BlurAction.commit:
          final onBlur = widget.onBlurCommit;
          onBlur != null ? onBlur(text) : widget.onCommit(text, false);
        case BlurAction.cancel:
          widget.onCancel();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    final style = theme
        .body(12, weight: FontWeight.w600)
        .copyWith(color: theme.ink);
    return TextField(
      controller: _text,
      focusNode: _focus,
      autofocus: true,
      maxLines: 1,
      style: style,
      cursorColor: theme.accent,
      textInputAction: TextInputAction.done,
      decoration: InputDecoration.collapsed(
        hintText: widget.placeholder,
        hintStyle: style.copyWith(color: theme.muted),
      ),
      onChanged: widget.onChanged,
      // The field keeps the focus here. The owner takes it away.
      onEditingComplete: () {},
      onSubmitted: (text) =>
          _finish(() => widget.onCommit(text, commandHeld())),
    );
  }
}
