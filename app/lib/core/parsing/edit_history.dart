import 'utf16_range.dart';

export 'utf16_range.dart';

/// A text and its selection at one moment.
class EditSnapshot {
  const EditSnapshot(this.text, this.selection);

  final String text;
  final Utf16Range selection;

  @override
  bool operator ==(Object other) =>
      other is EditSnapshot &&
      other.text == text &&
      other.selection == selection;

  @override
  int get hashCode => Object.hash(text, selection);

  @override
  String toString() => 'EditSnapshot("$text", $selection)';
}

class _Step {
  _Step(this.before, this.after, {required this.typing, required this.at});

  final EditSnapshot before;
  EditSnapshot after;
  final bool typing;
  DateTime at;
}

/// Undo and redo for one text box. Each step keeps the text before and after a change.
/// Quick typing joins into one step; a pause, any other change or [breakGroup] ends it.
class EditHistory {
  EditHistory({
    this.limit = 200,
    this.typingPause = const Duration(seconds: 1),
  });

  /// The most steps kept. The oldest go first.
  final int limit;

  /// Typing after a longer pause than this starts a new step.
  final Duration typingPause;

  final _undo = <_Step>[];
  final _redo = <_Step>[];
  bool _broken = true;

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  /// Keeps a change. `typing` is true for letters typed one by one. `at` is the time of the
  /// change, now when left out. A new change forgets what could be redone.
  void record(
    EditSnapshot before,
    EditSnapshot after, {
    bool typing = false,
    DateTime? at,
  }) {
    final now = at ?? DateTime.now();
    _redo.clear();
    final last = _undo.isEmpty ? null : _undo.last;
    if (typing &&
        !_broken &&
        last != null &&
        last.typing &&
        last.after.text == before.text &&
        now.difference(last.at) <= typingPause) {
      last
        ..after = after
        ..at = now;
      return;
    }
    _undo.add(_Step(before, after, typing: typing, at: now));
    if (_undo.length > limit) _undo.removeAt(0);
    _broken = !typing;
  }

  /// The next typing starts a new step, for example after the caret moved.
  void breakGroup() => _broken = true;

  /// The text to go back to, or null when there is nothing to undo.
  EditSnapshot? undo() {
    if (_undo.isEmpty) return null;
    final step = _undo.removeLast();
    _redo.add(step);
    _broken = true;
    return step.before;
  }

  /// The text to go forward to, or null when there is nothing to redo.
  EditSnapshot? redo() {
    if (_redo.isEmpty) return null;
    final step = _redo.removeLast();
    _undo.add(step);
    _broken = true;
    return step.after;
  }

  /// Forgets every step, for example when another note is loaded.
  void clear() {
    _undo.clear();
    _redo.clear();
    _broken = true;
  }
}
