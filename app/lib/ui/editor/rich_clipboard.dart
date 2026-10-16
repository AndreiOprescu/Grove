// Copy, cut and paste in a rich text box. Other apps get plain words; a
// paste inside Grove keeps the format.
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:grove/core/parsing/markdown_plain.dart';

import 'markdown_controller.dart';

/// Copy, cut and paste of every rich text box. The clipboard of the
/// computer gets the plain words. Grove keeps the Markdown of its last copy,
/// so a paste of the same words, in any box, keeps the format. The keys and
/// the menu of the text both come here.
abstract final class RichClipboard {
  /// The plain words of the last copy and their Markdown, while the app runs.
  static ({String plain, String markdown})? _kept;

  /// Forgets the last copy. For tests.
  @visibleForTesting
  static void forget() => _kept = null;

  /// Copies the selection, then takes it away when `cut`. With "Show marks"
  /// on, the field copies the text as it is, marks and all.
  static void copy(
    EditableTextState field,
    MarkdownController c,
    SelectionChangedCause cause, {
    bool cut = false,
  }) {
    final s = c.selection;
    if (!s.isValid || s.isCollapsed) return;
    if (cut && field.widget.readOnly) return;
    if (c.showMarks) {
      cut ? field.cutSelection(cause) : field.copySelection(cause);
      return;
    }
    final markdown = c.selectedMarkdown;
    final plain = MarkdownPlain.text(markdown);
    _kept = (plain: plain, markdown: markdown);
    Clipboard.setData(ClipboardData(text: plain));
    if (cut) {
      c.replaceSelection('');
      if (cause == SelectionChangedCause.toolbar) _afterToolbar(field);
    } else if (cause == SelectionChangedCause.toolbar) {
      // As the field does: the handles stay, and on Android the selection
      // ends.
      field.bringIntoView(s.extent);
      field.hideToolbar(false);
      if (defaultTargetPlatform == TargetPlatform.android) {
        c.selection = TextSelection.collapsed(offset: s.end);
      }
    }
    field.clipboardStatus.update();
  }

  /// Pastes the clipboard at the selection, as one step. Words that are the
  /// last copy of Grove go in with their format. Other text goes in as it
  /// is; marks in it make format, as typed marks do.
  static Future<void> paste(
    EditableTextState field,
    MarkdownController c,
    SelectionChangedCause cause,
  ) async {
    if (field.widget.readOnly || !c.selection.isValid) return;
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || !field.mounted || !c.selection.isValid) return;
    final kept = _kept;
    final same = kept != null && _lines(text) == _lines(kept.plain);
    c.replaceSelection(same ? kept.markdown : text);
    if (cause == SelectionChangedCause.toolbar) _afterToolbar(field);
  }

  /// Windows may give `\r\n` back for `\n`.
  static String _lines(String text) => text.replaceAll('\r\n', '\n');

  static void _afterToolbar(EditableTextState field) {
    field.hideToolbar();
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (field.mounted) {
        field.bringIntoView(field.textEditingValue.selection.extent);
      }
    }, debugLabel: 'RichClipboard.bringIntoView');
  }
}

/// ⌘C, ⌘X and the Copy and Cut keys of the system go through
/// [RichClipboard.copy].
class RichCopyAction extends ContextAction<CopySelectionTextIntent> {
  RichCopyAction(this.controller);

  final MarkdownController controller;

  @override
  bool isEnabled(CopySelectionTextIntent intent, [BuildContext? context]) =>
      callingAction?.isEnabled(intent) ?? true;

  @override
  Object? invoke(CopySelectionTextIntent intent, [BuildContext? context]) {
    final field = context?.findAncestorStateOfType<EditableTextState>();
    if (field == null) return callingAction?.invoke(intent);
    if (!field.widget.selectionEnabled) return null;
    RichClipboard.copy(
      field,
      controller,
      intent.cause,
      cut: intent.collapseSelection,
    );
    return null;
  }
}

/// ⌘V and the Paste key of the system go through [RichClipboard.paste].
class RichPasteAction extends ContextAction<PasteTextIntent> {
  RichPasteAction(this.controller);

  final MarkdownController controller;

  @override
  bool isEnabled(PasteTextIntent intent, [BuildContext? context]) =>
      callingAction?.isEnabled(intent) ?? true;

  @override
  Object? invoke(PasteTextIntent intent, [BuildContext? context]) {
    final field = context?.findAncestorStateOfType<EditableTextState>();
    if (field == null) return callingAction?.invoke(intent);
    if (!field.widget.selectionEnabled) return null;
    RichClipboard.paste(field, controller, intent.cause);
    return null;
  }
}
