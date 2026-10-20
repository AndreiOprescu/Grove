// Port of Sources/Grove/Editor/RichTextEditor.swift, EditorToolbar.swift and
// MentionPopup.swift: the Markdown editor with its row of buttons, the small
// pictures of its images and the `[[` list. Use it wherever a task, an
// event or a note has text.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:grove/core/model/link.dart';
import 'package:grove/core/parsing/markdown_edit.dart'
    show MarkdownEdit, PrefixKind, TextEdit;
import 'package:grove/core/parsing/markdown_spans.dart';
import 'package:grove/state/state.dart' hide MotionRules;

import '../theme/grove_theme.dart';
import '../theme/named_colors.dart';
import 'editor_tools.dart';
import 'link_dialog.dart';
import 'markdown_controller.dart';
import 'rich_clipboard.dart';

class RichTextField extends StatefulWidget {
  const RichTextField({
    super.key,
    required this.text,
    required this.onChanged,
    this.services,
    this.placeholder = '',
    this.minHeight = 80,
    this.fontSize = 13,
    this.onFocusChange,
    this.controller,
    this.focusNode,
    this.autofocus = false,
    this.pickImages,
    this.openLink,
    this.label,
  });

  /// The Markdown text. A new value from outside replaces what the editor
  /// shows.
  final String text;

  /// Called with the new text after each change the user makes.
  final ValueChanged<String> onChanged;

  /// What the editor needs from the app. With none it has no `[[` list.
  final EditorServices? services;
  final String placeholder;
  final double minHeight;
  final double fontSize;
  final ValueChanged<bool>? onFocusChange;

  /// The one who gives a controller closes it.
  final MarkdownController? controller;
  final FocusNode? focusNode;
  final bool autofocus;

  /// The "Add an image" button shows only when this is set, or when the
  /// app around the field gives a picker (`EditorTools`).
  final ImagePicker? pickImages;

  /// Opens a web link of the text in the browser. With null the editor
  /// uses the one of the app around it (`EditorTools`); with none a click
  /// on a web link does nothing.
  final LinkOpener? openLink;

  /// What a screen reader says. The placeholder when null.
  final String? label;

  /// The width of the `[[` list, and the height of one of its rows.
  static const listWidth = 300.0;
  static const listRow = 30.0;

  @override
  State<RichTextField> createState() => RichTextFieldState();
}

class RichTextFieldState extends State<RichTextField> {
  MarkdownController? _own;
  FocusNode? _ownFocus;
  final _link = LayerLink();
  final _portal = OverlayPortalController();
  final _bubblePortal = OverlayPortalController();
  final _fieldKey = GlobalKey();

  /// The text the owner of the field knows.
  String _reported = '';
  bool _loading = false;

  /// Where the pointer went down, and the selection at that time. A click
  /// on a check box leaves the caret where it was.
  Offset? _downAt;
  TextSelection? _selectionAtDown;

  /// The link whose bubble is open, and the text it was found in.
  _LinkSpot? _bubble;

  ImagePicker? get _pickImages =>
      widget.pickImages ?? EditorTools.maybeOf(context)?.pickImages;

  LinkOpener? get _openLink =>
      widget.openLink ?? EditorTools.maybeOf(context)?.openLink;

  MarkdownController get controller =>
      widget.controller ?? (_own ??= MarkdownController(text: widget.text));

  FocusNode get _focus => widget.focusNode ?? (_ownFocus ??= FocusNode());

  static final _empty = EditorServices();

  @override
  void initState() {
    super.initState();
    _reported = widget.text;
    final c = controller;
    c.services = widget.services ?? _empty;
    if (c.text != widget.text) c.load(widget.text);
    c.focused = _focus.hasFocus;
    c.addListener(_changed);
    c.mentions.addListener(_listChanged);
    _focus.addListener(_focusChanged);
  }

  @override
  void didUpdateWidget(RichTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    assert(
      oldWidget.controller == widget.controller &&
          oldWidget.focusNode == widget.focusNode,
      'give a new key to a field that gets another controller or focus node',
    );
    final c = controller;
    if (!identical(oldWidget.services, widget.services)) {
      c.services = widget.services ?? _empty;
      c.forgetLive();
    }
    if (widget.text != _reported) {
      _reported = widget.text;
      _loading = true;
      try {
        c.load(widget.text);
      } finally {
        _loading = false;
      }
    }
  }

  @override
  void dispose() {
    final c = controller;
    c.removeListener(_changed);
    c.mentions.removeListener(_listChanged);
    _focus.removeListener(_focusChanged);
    _own?.dispose();
    _ownFocus?.dispose();
    super.dispose();
  }

  void _changed() {
    if (_loading || !mounted) return;
    _checkBubble();
    final text = controller.text;
    if (text != _reported) {
      _reported = text;
      widget.onChanged(text);
    }
    // The image strip and the planner button read the text and the caret.
    setState(() {});
  }

  void _focusChanged() {
    final has = _focus.hasFocus;
    if (!has) _closeBubble();
    if (controller.focused == has) return;
    controller.setFocused(has);
    widget.onFocusChange?.call(has);
    if (mounted) setState(() {});
  }

  void _listChanged() {
    if (!mounted) return;
    final open = controller.mentions.value != null;
    if (open == _portal.isShowing) return;
    if (open) {
      _portal.show();
    } else {
      _portal.hide();
    }
  }

  // Keys

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final c = controller;
    final key = event.logicalKey;
    final keys = HardwareKeyboard.instance;
    final apple =
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.iOS;
    final command = apple ? keys.isMetaPressed : keys.isControlPressed;
    final shift = keys.isShiftPressed;
    if (_bubble != null && key == LogicalKeyboardKey.escape) {
      _closeBubble();
      return KeyEventResult.handled;
    }
    if (c.mentions.value != null) {
      if (key == LogicalKeyboardKey.arrowDown) {
        c.moveList(1);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowUp) {
        c.moveList(-1);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.enter ||
          key == LogicalKeyboardKey.numpadEnter ||
          key == LogicalKeyboardKey.tab) {
        c.acceptCurrent();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.escape) {
        c.closeList();
        return KeyEventResult.handled;
      }
    }
    if (key == LogicalKeyboardKey.tab && !command && !keys.isAltPressed) {
      return c.indent(outdent: shift)
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }
    if (!command || keys.isAltPressed) return KeyEventResult.ignored;
    // Undo and redo of the text while the box has something to take back;
    // else the key goes on to the undo of the app.
    final z = key == LogicalKeyboardKey.keyZ;
    final redo =
        (z && shift) || (!apple && !shift && key == LogicalKeyboardKey.keyY);
    if (z || redo) {
      if (!(redo ? c.canRedo : c.canUndo)) return KeyEventResult.ignored;
      redo ? c.redo() : c.undo();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyK && !shift) {
      unawaited(_editLink());
      return KeyEventResult.handled;
    }
    if (shift) {
      if (key == LogicalKeyboardKey.keyT) {
        c.makeTask();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    final format = switch (key) {
      LogicalKeyboardKey.keyB => EditorFormat.bold,
      LogicalKeyboardKey.keyI => EditorFormat.italic,
      LogicalKeyboardKey.keyE => EditorFormat.code,
      _ => null,
    };
    if (format == null) return KeyEventResult.ignored;
    c.format(format);
    return KeyEventResult.handled;
  }

  // Clicks

  RenderEditable? get _editable {
    RenderEditable? found;
    void visit(RenderObject object) {
      if (found != null) return;
      if (object is RenderEditable) {
        found = object;
        return;
      }
      object.visitChildren(visit);
    }

    _fieldKey.currentContext?.findRenderObject()?.visitChildren(visit);
    return found;
  }

  /// The check box, mention, image name or link at a place of the window.
  MarkdownSpan? _spanAt(Offset global) {
    final editable = _editable;
    if (editable == null || !editable.attached) return null;
    final offset = editable.getPositionForPoint(global).offset;
    final c = controller;
    // The place between two letters belongs to the one before or after it.
    for (final at in [offset, offset - 1]) {
      final span = at < 0 ? null : c.hit(at);
      if (span == null) continue;
      final local = editable.globalToLocal(global);
      final boxes = editable.getBoxesForSelection(
        TextSelection(
          baseOffset: span.range.location,
          extentOffset: span.range.end,
        ),
      );
      for (final box in boxes) {
        if (box.toRect().inflate(2).contains(local)) return span;
      }
    }
    return null;
  }

  void _pointerDown(PointerDownEvent event) {
    if (event.buttons != kPrimaryButton) {
      _downAt = null;
      return;
    }
    _downAt = event.position;
    _selectionAtDown = controller.selection;
  }

  void _pointerUp(PointerUpEvent event) {
    final down = _downAt;
    _downAt = null;
    if (down == null || (event.position - down).distance > kTouchSlop) return;
    final span = _spanAt(event.position);
    if (span == null) return;
    final before = _selectionAtDown;
    // After the field has moved its caret for this click.
    scheduleMicrotask(() {
      if (!mounted) return;
      final c = controller;
      final services = c.services;
      switch (span.kind.type) {
        case SpanType.checkbox:
          if (before != null && before.isValid) c.selection = before;
          c.toggleCheckbox(span.range.location);
        case SpanType.mention:
          services.open(span.kind.id, span.kind.title ?? '');
        case SpanType.image:
          c.previewImage.value = span.kind.id;
        case SpanType.link:
        case SpanType.linkWords:
          _showBubble(span);
        default:
          break;
      }
    });
  }

  // Links

  /// Opens a web address in the browser. Only `http` and `https`; with no
  /// browser, or any other link, it does nothing.
  void _open(String text) {
    final open = _openLink;
    final url = webLink(text);
    if (open == null || url == null) return;
    final services = controller.services;
    void failed() => services.notify('Grove could not open the link.');
    unawaited(
      Future.sync(() => open(url)).then((opened) {
        if (!opened) failed();
      }, onError: (Object _) => failed()),
    );
  }

  /// The link at a span the user clicked: the whole `[words](address)` for
  /// a link with words, the address itself for a bare one.
  _LinkSpot? _spotOf(MarkdownSpan span) {
    final text = controller.text;
    final url = span.kind.url ?? '';
    if (span.kind.type == SpanType.link) {
      return _LinkSpot(text, span.range, url, words: '', bare: true);
    }
    final pair = MarkdownEdit.linkAt(text, span.range.location);
    if (pair == null) return null;
    return _LinkSpot(
      text,
      pair.whole,
      url,
      words: _plainWords(pair.content),
      bare: false,
      content: pair.content,
    );
  }

  /// The link at the selection: the one it is in, a bare address it is in,
  /// or null.
  _LinkSpot? _spotAt(TextSelection sel) {
    final c = controller;
    final from = sel.start, to = sel.end;
    final pair = MarkdownEdit.linkAt(c.text, from);
    if (pair != null && to <= pair.content.end) {
      return _LinkSpot(
        c.text,
        pair.whole,
        pair.kind.url ?? '',
        words: _plainWords(pair.content),
        bare: false,
        content: pair.content,
      );
    }
    for (final span in c.spans) {
      if (span.kind.type != SpanType.link) continue;
      final r = span.range;
      if (r.location <= from && to <= r.end) {
        return _LinkSpot(c.text, r, span.kind.url ?? '', words: '', bare: true);
      }
    }
    return null;
  }

  /// The words of a part of the text with no marks, on one line.
  String _plainWords(Utf16Range range) {
    final c = controller;
    final hidden = <int>{
      for (final s in c.spans)
        if (s.kind.type == SpanType.syntax)
          for (var i = s.range.location; i < s.range.end; i++) i,
    };
    final out = StringBuffer();
    for (var i = range.location; i < range.end && i < c.text.length; i++) {
      if (!hidden.contains(i)) out.write(c.text[i]);
    }
    return _oneLine(out.toString());
  }

  /// Newlines and brackets become spaces, runs of spaces one, ends trimmed:
  /// the words of a link are on one line.
  static String _oneLine(String s) =>
      s.replaceAll(RegExp(r'[\s\[\]]+'), ' ').trim();

  void _showBubble(MarkdownSpan span) {
    final spot = _spotOf(span);
    if (spot == null) return;
    setState(() => _bubble = spot);
    _bubblePortal.show();
  }

  void _closeBubble() {
    if (_bubble == null) return;
    _bubble = null;
    if (_bubblePortal.isShowing) _bubblePortal.hide();
    if (mounted) setState(() {});
  }

  /// The bubble goes when the text changes or the caret leaves its link.
  void _checkBubble() {
    final spot = _bubble;
    if (spot == null) return;
    final c = controller;
    final sel = c.selection;
    final r = spot.range;
    if (c.text != spot.text ||
        !sel.isValid ||
        sel.start < r.location ||
        sel.end > r.end) {
      _closeBubble();
    }
  }

  /// The first line of the link of the bubble, and where the field is in
  /// the window.
  ({Rect line, Offset origin})? _bubblePlace() {
    final editable = _editable;
    final box = _fieldKey.currentContext?.findRenderObject();
    final spot = _bubble;
    if (editable == null || box is! RenderBox || spot == null) return null;
    final at = spot.content ?? spot.range;
    final boxes = editable.getBoxesForSelection(
      TextSelection(baseOffset: at.location, extentOffset: at.end),
    );
    if (boxes.isEmpty) return null;
    final rect = boxes.first.toRect();
    final from = editable.localToGlobal(rect.topLeft, ancestor: box);
    return (line: from & rect.size, origin: box.localToGlobal(Offset.zero));
  }

  /// Opens the link window for the selection, or for `spot` (Edit of the
  /// bubble). Save puts in the link; Cancel puts the selection back.
  Future<void> _editLink([_LinkSpot? spot]) async {
    final c = controller;
    var saved = c.selection;
    if (!saved.isValid || saved.end > c.text.length) {
      saved = TextSelection.collapsed(offset: c.text.length);
    }
    final before = c.text;
    final target = spot ?? _spotAt(saved);
    final words =
        target?.words ??
        _plainWords(Utf16Range(saved.start, saved.end - saved.start));
    _closeBubble();
    final input = await showLinkDialog(
      context,
      words: words,
      address: target?.address ?? '',
    );
    if (!mounted) return;
    _focus.requestFocus();
    if (c.text != before) {
      // The owner changed the text while the window was open (it saves when
      // the box loses the keyboard). The places are gone: no change.
      return;
    }
    c.selection = saved;
    if (input == null) return;
    c.apply(_linkEdit(before, saved, target, words, input));
  }

  /// The change Save of the link window makes.
  TextEdit? _linkEdit(
    String text,
    TextSelection sel,
    _LinkSpot? target,
    String oldWords,
    LinkInput input,
  ) {
    final address = linkTarget(input.address);
    if (address == null) return null;
    final words = _oneLine(input.words);
    TextEdit replace(Utf16Range range, String shown) {
      final link = '[${shown.isEmpty ? address : shown}]($address)';
      return TextEdit(
        range: range,
        replacement: link,
        selection: Utf16Range(range.location + link.length, 0),
      );
    }

    final range = Utf16Range(sel.start, sel.end - sel.start);
    if (target == null) {
      // Same words as selected: the words keep their formats.
      if (range.length > 0 && words == oldWords) {
        return MarkdownEdit.setLink(address, text, range);
      }
      return replace(range, words);
    }
    if (target.bare) {
      if (words.isEmpty) {
        return TextEdit(
          range: target.range,
          replacement: address,
          selection: Utf16Range(target.range.location + address.length, 0),
        );
      }
      return replace(target.range, words);
    }
    if (words == oldWords) {
      return MarkdownEdit.setLink(
        address,
        text,
        Utf16Range(target.content!.location, 0),
      );
    }
    return replace(target.range, words);
  }

  /// Makes a mention where a task or a note is dropped.
  void _drop(DragTargetDetails<String> details) {
    final raw = details.data;
    final id = raw.startsWith(DragPayload.taskPrefix)
        ? raw.substring(DragPayload.taskPrefix.length)
        : DragPayload.noteId(raw);
    final editable = _editable;
    if (id == null || editable == null) return;
    controller.dropItem(
      id,
      editable.getPositionForPoint(details.offset).offset,
    );
  }

  Future<void> _addImage() async {
    final pick = _pickImages;
    if (pick == null) return;
    final c = controller;
    final List<PickedImage> items;
    try {
      items = await pick();
    } on Object {
      c.services.notify('Grove could not open the file window.');
      return;
    }
    if (!mounted) return;
    c.importImages(items);
  }

  // Build

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    final c = controller;
    final look = EditorStyle(theme, size: widget.fontSize);
    c.style = look;
    c.showMarks = c.services.showMarks();
    final ids = c.imageIds;
    final canPlan = c.plannerLine() != null;
    // A press of a mouse outside a text takes the keyboard away from it, and
    // the owner of the text then saves it and may change it. The buttons of
    // the editor work on the text, so a press on them is a press in the
    // text (the Mac app does the same: GroveTextView.swift).
    return TextFieldTapRegion(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 6,
        children: [
          EditorToolbar(
            controller: c,
            onImage: _pickImages == null ? null : _addImage,
            onLink: () => unawaited(_editLink()),
            before: _focus.requestFocus,
          ),
          if (ids.isNotEmpty)
            ImageStrip(ids: ids, controller: c, services: c.services),
          OverlayPortal(
            controller: _portal,
            overlayChildBuilder: (context) => _MentionLayer(
              link: _link,
              controller: c,
              theme: theme,
              caret: _listPlace,
            ),
            child: OverlayPortal(
              controller: _bubblePortal,
              overlayChildBuilder: (context) => _BubbleLayer(
                link: _link,
                theme: theme,
                repaint: c,
                caret: _bubblePlace,
                bubble: _bubbleOf(),
              ),
              child: CompositedTransformTarget(
                link: _link,
                child: _field(theme, look),
              ),
            ),
          ),
          if (canPlan) _PlannerButton(theme: theme, onTap: c.addToPlanner),
        ],
      ),
    );
  }

  /// The bubble of the open link, with its buttons. Null when it is shut.
  Widget? _bubbleOf() {
    final spot = _bubble;
    if (spot == null) return null;
    final canOpen = _openLink != null && webLink(spot.address) != null;
    return LinkBubble(
      theme: GroveTheme.of(context),
      address: spot.address,
      onClose: _closeBubble,
      onOpen: canOpen
          ? () {
              _closeBubble();
              _open(spot.address);
            }
          : null,
      onEdit: () => unawaited(_editLink(spot)),
      onRemove: spot.bare
          ? null
          : () {
              _closeBubble();
              controller.apply(
                MarkdownEdit.removeLink(
                  controller.text,
                  Utf16Range(spot.content!.location, 0),
                ),
              );
            },
    );
  }

  /// The line of the `[[` in the box of the field, and where that box is
  /// in the window. Null when the field is not on the screen.
  ({Rect line, Offset origin})? _listPlace() {
    final editable = _editable;
    final box = _fieldKey.currentContext?.findRenderObject();
    final open = controller.mentions.value;
    if (editable == null || box is! RenderBox || open == null) return null;
    final at = open.location.clamp(0, controller.text.length);
    final rect = editable.getLocalRectForCaret(TextPosition(offset: at));
    final from = editable.localToGlobal(rect.topLeft, ancestor: box);
    return (line: from & rect.size, origin: box.localToGlobal(Offset.zero));
  }

  Widget _field(GroveTheme theme, EditorStyle look) {
    final c = controller;
    final base = look.base;
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) =>
          details.data.startsWith(DragPayload.taskPrefix) ||
          DragPayload.noteId(details.data) != null,
      onAcceptWithDetails: _drop,
      builder: (context, candidates, _) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        // A click under the last line still gives the text the keyboard.
        onTap: () {
          _focus.requestFocus();
          c.selection = TextSelection.collapsed(offset: c.text.length);
        },
        child: ConstrainedBox(
          key: _fieldKey,
          constraints: BoxConstraints(minHeight: widget.minHeight),
          child: Align(
            alignment: Alignment.topLeft,
            heightFactor: 1,
            child: Listener(
              onPointerDown: _pointerDown,
              onPointerUp: _pointerUp,
              child: Focus(
                canRequestFocus: false,
                skipTraversal: true,
                onKeyEvent: _key,
                child: Semantics(
                  label: widget.label ?? widget.placeholder,
                  child: Stack(
                    children: [
                      if (c.text.isEmpty && widget.placeholder.isNotEmpty)
                        IgnorePointer(
                          child: ExcludeSemantics(
                            child: Text(
                              widget.placeholder,
                              style: base.copyWith(color: theme.muted),
                            ),
                          ),
                        ),
                      Actions(
                        actions: {
                          ExtendSelectionByCharacterIntent: _StepOverMarks(c),
                          CopySelectionTextIntent: RichCopyAction(c),
                          PasteTextIntent: RichPasteAction(c),
                        },
                        child: TextField(
                          controller: c,
                          focusNode: _focus,
                          autofocus: widget.autofocus,
                          maxLines: null,
                          style: base,
                          strutStyle: look.strut,
                          cursorColor: theme.accent,
                          keyboardType: TextInputType.multiline,
                          textInputAction: TextInputAction.newline,
                          textCapitalization: TextCapitalization.sentences,
                          // A text with marks is not prose. The keyboard must not
                          // change `[[` or `- [ ]`.
                          autocorrect: false,
                          smartDashesType: SmartDashesType.disabled,
                          smartQuotesType: SmartQuotesType.disabled,
                          contextMenuBuilder: _menu,
                          decoration: null,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The menu of the text, with "Make task" and "Add to planner" when the
  /// line can do it. Copy, Cut and Paste do what the keys do.
  Widget _menu(BuildContext context, EditableTextState state) {
    final c = controller;
    void run(VoidCallback action) {
      ContextMenuController.removeAny();
      action();
    }

    const toolbar = SelectionChangedCause.toolbar;
    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: state.contextMenuAnchors,
      buttonItems: [
        for (final item in state.contextMenuButtonItems)
          if (item.onPressed == null)
            item
          else
            switch (item.type) {
              ContextMenuButtonType.copy => item.copyWith(
                onPressed: () => RichClipboard.copy(state, c, toolbar),
              ),
              ContextMenuButtonType.cut => item.copyWith(
                onPressed: () =>
                    RichClipboard.copy(state, c, toolbar, cut: true),
              ),
              ContextMenuButtonType.paste => item.copyWith(
                onPressed: () => RichClipboard.paste(state, c, toolbar),
              ),
              _ => item,
            },
        if (c.canMakeTask)
          ContextMenuButtonItem(
            label: 'Make task',
            onPressed: () => run(c.makeTask),
          ),
        if (c.plannerLine() != null)
          ContextMenuButtonItem(
            label: 'Add to planner',
            onPressed: () => run(c.addToPlanner),
          ),
      ],
    );
  }
}

/// An arrow key, with or without Shift, steps over hidden marks and line
/// marks: one key is one letter that shows. With "Show marks" on, the field
/// does it as always.
/// Word and line moves need nothing here: the controller puts a caret that
/// lands in hidden marks on its one place.
class _StepOverMarks extends ContextAction<ExtendSelectionByCharacterIntent> {
  _StepOverMarks(this.controller);

  final MarkdownController controller;

  @override
  bool isEnabled(
    ExtendSelectionByCharacterIntent intent, [
    BuildContext? context,
  ]) => callingAction?.isEnabled(intent) ?? true;

  @override
  Object? invoke(
    ExtendSelectionByCharacterIntent intent, [
    BuildContext? context,
  ]) {
    final c = controller;
    final selection = c.selection;
    final fallback = callingAction;
    if (!selection.isValid || !c.hasSkippedPlaces) {
      return fallback is ContextAction<ExtendSelectionByCharacterIntent>
          ? fallback.invoke(intent, context)
          : fallback?.invoke(intent);
    }
    final next = c.moveByCharacter(
      selection,
      forward: intent.forward,
      collapse: intent.collapseSelection,
    );
    // Through the field, so it shows the caret on the screen.
    final field = context?.findAncestorStateOfType<EditableTextState>();
    if (field != null) {
      field.userUpdateTextEditingValue(
        c.value.copyWith(selection: next),
        SelectionChangedCause.keyboard,
      );
    } else {
      c.selection = next;
    }
    return null;
  }
}

/// "Add to planner", under a line with an `@date`.
class _PlannerButton extends StatelessWidget {
  const _PlannerButton({required this.theme, required this.onTap});

  final GroveTheme theme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    button: true,
    label: 'Add to planner',
    onTap: onTap,
    excludeSemantics: true,
    child: MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: theme.accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 5,
              children: [
                Icon(
                  Icons.event_available_outlined,
                  size: 13,
                  color: theme.accent,
                ),
                Text(
                  'Add to planner',
                  style: theme
                      .body(11, weight: FontWeight.w600)
                      .copyWith(color: theme.accent),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// One tool of the row above an editor: its icon and name, how wide it is,
/// what it does, and whether the caret is in its format.
class ToolSpec {
  const ToolSpec({
    required this.id,
    required this.icon,
    required this.label,
    this.tip,
    this.width = EditorToolbar.buttonWidth,
    this.action,
    this.active,
    this.enabled = true,
    this.button,
    this.rows,
  });

  final String id;
  final IconData icon;

  /// The plain name: what a screen reader says, and the row in "…".
  final String label;

  /// The tooltip. The label when null.
  final String? tip;

  /// The width of the tool in the row.
  final double width;
  final VoidCallback? action;

  /// True when the caret is in the format of the tool, false when not. Null
  /// for a tool that is not a switch.
  final bool? active;
  final bool enabled;

  /// Builds a tool that is more than one plain button (Text size,
  /// Highlight). The context is the one of the tool.
  final WidgetBuilder? button;

  /// The rows of the tool in the "…" menu. One row with its icon and label
  /// when null.
  final List<ToolRow>? rows;
}

/// One row of a menu of the toolbar.
class ToolRow {
  const ToolRow({
    required this.label,
    required this.action,
    this.icon,
    this.swatch,
    this.checked = false,
    this.enabled = true,
  });

  final String label;
  final VoidCallback action;
  final IconData? icon;

  /// A dot of this colour in place of the icon.
  final Color? swatch;

  /// The row has a tick: its format is on.
  final bool checked;
  final bool enabled;
}

/// The row of tools above an editor. When the box is wide enough every tool
/// shows, in groups. Else a short row of the most used tools shows, and a
/// "…" button holds the others. The tools of the format at the caret light
/// up.
class EditorToolbar extends StatelessWidget {
  const EditorToolbar({
    super.key,
    required this.controller,
    this.onImage,
    this.onLink,
    this.before,
  });

  final MarkdownController controller;

  /// Null when the app cannot pick a picture. The button is then not there.
  final VoidCallback? onImage;

  /// Makes a link of the selection. Null: the Link tool is not there.
  final VoidCallback? onLink;

  /// Runs before each button, to give the text the keyboard.
  final VoidCallback? before;

  static const buttonWidth = 26.0;
  static const _gap = 2.0;

  /// The line between two groups, with room on each side.
  static const _separatorWidth = 7.0;
  static const _textSizeWidth = 60.0;
  static const _arrowWidth = 14.0;

  /// The colour the Highlight button gives: the last one picked from its
  /// menu. It is the same in every box and lasts while the app runs.
  static var lastHighlight = HighlightColor.yellow;

  /// The tools a box too narrow for every tool shows first. More tools
  /// join them while there is room.
  static const priority = [
    'undo',
    'textSize',
    'bold',
    'italic',
    'underline',
    'highlight',
    'bullet',
    'checklist',
    'link',
  ];

  static const _sizes = [
    'Normal text',
    'Big heading',
    'Medium heading',
    'Small heading',
  ];
  static const _shortSizes = ['Normal', 'Big', 'Medium', 'Small'];

  static String _colourName(HighlightColor c) =>
      c.name[0].toUpperCase() + c.name.substring(1);

  static Color _swatch(HighlightColor c, GroveTheme theme) =>
      TaskPalette.color(c.name) ?? theme.accent;

  /// Runs a tool: the text gets the keyboard first.
  void _run(VoidCallback action) {
    before?.call();
    action();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([controller, controller.undoState]),
    builder: (context, _) =>
        LayoutBuilder(builder: (context, box) => _row(context, box.maxWidth)),
  );

  Widget _row(BuildContext context, double room) {
    final theme = GroveTheme.of(context);
    final groups = _groups(theme, controller.activeAt());
    final all = [for (final g in groups) ...g];
    double width(List<double> parts) => parts.isEmpty
        ? 0
        : parts.reduce((a, b) => a + b) + _gap * (parts.length - 1);
    final filled = [
      for (final g in groups)
        if (g.isNotEmpty) g,
    ];
    final wide = width([
      for (var i = 0; i < filled.length; i++) ...[
        if (i > 0) _separatorWidth,
        for (final t in filled[i]) t.width,
      ],
    ]);
    if (wide <= room) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        spacing: _gap,
        children: [
          for (var i = 0; i < filled.length; i++) ...[
            if (i > 0) _separator(theme),
            for (final t in filled[i]) _tool(theme, t),
          ],
        ],
      );
    }
    // Too narrow for the group lines: the short row first, then the other
    // tools in order, as many as fit beside "…". They show in the order of
    // the wide row. When every tool fits, there is no "…".
    final ranked = [
      for (final id in priority) ...all.where((t) => t.id == id),
      for (final t in all)
        if (!priority.contains(t.id)) t,
    ];
    final picked = <ToolSpec>{};
    for (final t in ranked) {
      final last = picked.length + 1 == ranked.length;
      final next = [
        for (final s in picked) s.width,
        t.width,
        if (!last) buttonWidth,
      ];
      if (width(next) > room) break;
      picked.add(t);
    }
    final shown = [
      for (final t in all)
        if (picked.contains(t)) t,
    ];
    final rest = [
      for (final t in all)
        if (!picked.contains(t)) t,
    ];
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: _gap,
      children: [
        for (final t in shown) _tool(theme, t),
        if (rest.isNotEmpty)
          Builder(
            builder: (context) => _ToolButton(
              theme: theme,
              icon: Icons.more_horiz,
              label: 'More',
              tip: 'More tools',
              onTap: () => _menu(context, [
                for (final t in rest)
                  ...t.rows ??
                      [
                        ToolRow(
                          label: t.label,
                          icon: t.icon,
                          checked: t.active ?? false,
                          enabled: t.enabled,
                          action: t.action ?? () {},
                        ),
                      ],
              ]),
            ),
          ),
      ],
    );
  }

  Widget _separator(GroveTheme theme) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 3),
    child: SizedBox(width: 1, height: 14, child: ColoredBox(color: theme.line)),
  );

  Widget _tool(GroveTheme theme, ToolSpec t) {
    final button = t.button;
    if (button != null) {
      return SizedBox(
        width: t.width,
        child: Builder(builder: button),
      );
    }
    return _ToolButton(
      theme: theme,
      icon: t.icon,
      label: t.label,
      tip: t.tip ?? t.label,
      width: t.width,
      active: t.active,
      enabled: t.enabled,
      onTap: () => _run(t.action ?? () {}),
    );
  }

  /// Every tool, in the groups of the wide row.
  List<List<ToolSpec>> _groups(GroveTheme theme, ActiveFormats on) {
    final apple =
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.iOS;
    final mod = apple ? '⌘' : 'Ctrl+';
    final c = controller;
    final undo = c.undoState.value;
    ToolSpec inline(
      String id,
      IconData icon,
      String label,
      InlineFormat f, {
      String? key,
    }) => ToolSpec(
      id: id,
      icon: icon,
      label: label,
      tip: key == null ? label : '$label  $mod$key',
      active: on.has(f),
      action: () => c.toggleInline(f),
    );
    ToolSpec line(
      String id,
      IconData icon,
      String label,
      EditorFormat f,
      PrefixKind kind,
    ) => ToolSpec(
      id: id,
      icon: icon,
      label: label,
      active: on.line == kind,
      action: () => c.format(f),
    );
    final sizeRows = [
      for (var level = 0; level < _sizes.length; level++)
        ToolRow(
          label: _sizes[level],
          icon: Icons.format_size,
          checked: on.heading == level,
          action: () => c.setHeading(level),
        ),
    ];
    final highlighted = on.has(InlineFormat.highlight);
    final colourRows = [
      for (final colour in HighlightColor.values)
        ToolRow(
          label: _colourName(colour),
          swatch: _swatch(colour, theme),
          checked: highlighted && on.highlight == colour,
          action: () {
            lastHighlight = colour;
            // Words already in this colour stay as they are.
            if (highlighted && on.highlight == colour) return;
            c.toggleInline(InlineFormat.highlight, color: colour);
          },
        ),
      ToolRow(
        label: 'No highlight',
        icon: Icons.format_color_reset,
        enabled: highlighted,
        action: () {
          if (!highlighted) return;
          c.toggleInline(
            InlineFormat.highlight,
            color: on.highlight ?? HighlightColor.yellow,
          );
        },
      ),
    ];
    void highlight() =>
        c.toggleInline(InlineFormat.highlight, color: lastHighlight);
    return [
      [
        ToolSpec(
          id: 'undo',
          icon: Icons.undo,
          label: 'Undo',
          tip: 'Undo  ${mod}Z',
          enabled: undo.canUndo,
          action: c.undo,
        ),
        ToolSpec(
          id: 'redo',
          icon: Icons.redo,
          label: 'Redo',
          tip: apple ? 'Redo  ⇧⌘Z' : 'Redo  Ctrl+Y',
          enabled: undo.canRedo,
          action: c.redo,
        ),
      ],
      [
        ToolSpec(
          id: 'textSize',
          icon: Icons.format_size,
          label: 'Text size',
          width: _textSizeWidth,
          rows: sizeRows,
          button: (context) => _ToolButton(
            theme: theme,
            icon: Icons.format_size,
            label: 'Text size',
            tip: 'Text size',
            value: _sizes[on.heading],
            width: _textSizeWidth,
            onTap: () => _menu(context, sizeRows),
            content: (color) => Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    _shortSizes[on.heading],
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    style: theme
                        .body(11, weight: FontWeight.w600)
                        .copyWith(color: color),
                  ),
                ),
                Icon(Icons.arrow_drop_down, size: 14, color: color),
              ],
            ),
          ),
        ),
      ],
      [
        inline('bold', Icons.format_bold, 'Bold', InlineFormat.bold, key: 'B'),
        inline(
          'italic',
          Icons.format_italic,
          'Italic',
          InlineFormat.italic,
          key: 'I',
        ),
        inline(
          'underline',
          Icons.format_underlined,
          'Underline',
          InlineFormat.underline,
        ),
        inline(
          'strike',
          Icons.format_strikethrough,
          'Strike',
          InlineFormat.strike,
        ),
        ToolSpec(
          id: 'highlight',
          icon: Icons.border_color,
          label: 'Highlight',
          width: buttonWidth + _arrowWidth,
          active: highlighted,
          action: highlight,
          rows: [
            ToolRow(
              label: 'Highlight',
              icon: Icons.border_color,
              checked: highlighted,
              action: highlight,
            ),
            ...colourRows,
          ],
          button: (context) => Row(
            children: [
              _ToolButton(
                theme: theme,
                icon: Icons.border_color,
                label: 'Highlight',
                tip: 'Highlight',
                active: highlighted,
                onTap: () => _run(highlight),
                content: (color) => Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  spacing: 1,
                  children: [
                    Icon(Icons.border_color, size: 13, color: color),
                    SizedBox(
                      width: 13,
                      height: 3,
                      child: ColoredBox(color: _swatch(lastHighlight, theme)),
                    ),
                  ],
                ),
              ),
              _ToolButton(
                theme: theme,
                icon: Icons.arrow_drop_down,
                label: 'Highlight colour',
                tip: 'Highlight colour',
                width: _arrowWidth,
                onTap: () => _menu(context, colourRows),
              ),
            ],
          ),
        ),
        inline('code', Icons.code, 'Code', InlineFormat.code, key: 'E'),
      ],
      [
        line(
          'bullet',
          Icons.format_list_bulleted,
          'Bullet list',
          EditorFormat.bullet,
          PrefixKind.bullet,
        ),
        line(
          'numbered',
          Icons.format_list_numbered,
          'Numbered list',
          EditorFormat.numbered,
          PrefixKind.numbered,
        ),
        line(
          'checklist',
          Icons.checklist,
          'Checklist',
          EditorFormat.checklist,
          PrefixKind.checklist,
        ),
        line(
          'quote',
          Icons.format_quote,
          'Quote',
          EditorFormat.quote,
          PrefixKind.quote,
        ),
        ToolSpec(
          id: 'indentIn',
          icon: Icons.format_indent_increase,
          label: 'Indent in',
          tip: 'Indent in  Tab',
          action: () => c.indent(),
        ),
        ToolSpec(
          id: 'indentOut',
          icon: Icons.format_indent_decrease,
          label: 'Indent out',
          tip: apple ? 'Indent out  ⇧Tab' : 'Indent out  Shift+Tab',
          action: () => c.indent(outdent: true),
        ),
      ],
      [
        if (onLink case final link?)
          ToolSpec(
            id: 'link',
            icon: Icons.link,
            label: 'Link',
            tip: 'Link  ${mod}K',
            active: on.link,
            action: link,
          ),
        ToolSpec(
          id: 'mention',
          icon: Icons.alternate_email,
          label: 'Mention',
          tip: 'Mention a task, event or note',
          action: c.startMention,
        ),
        if (onImage case final image?)
          ToolSpec(
            id: 'image',
            icon: Icons.image_outlined,
            label: 'Add an image',
            action: image,
          ),
        ToolSpec(
          id: 'divider',
          icon: Icons.horizontal_rule,
          label: 'Divider',
          action: c.insertDivider,
        ),
        ToolSpec(
          id: 'clear',
          icon: Icons.format_clear,
          label: 'Clear format',
          action: c.clearFormat,
        ),
      ],
    ];
  }

  /// Opens a menu under the tool of `context`. The text keeps the keyboard
  /// while it is open, so its owner does not save and load it again, and the
  /// selection is put back before a row runs.
  void _menu(BuildContext context, List<ToolRow> rows) {
    final theme = GroveTheme.of(context);
    final button = context.findRenderObject()! as RenderBox;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final below = Rect.fromPoints(
      button.localToGlobal(button.size.bottomLeft(Offset.zero)),
      button.localToGlobal(button.size.bottomRight(const Offset(0, 4))),
    );
    final saved = controller.selection;
    void run(ToolRow row) => _run(() {
      final c = controller;
      if (saved.isValid && saved.end <= c.text.length && c.selection != saved) {
        c.selection = saved;
      }
      row.action();
    });
    unawaited(
      showMenu<void>(
        context: context,
        position: RelativeRect.fromRect(below, Offset.zero & overlay.size),
        requestFocus: false,
        items: [
          for (final row in rows)
            PopupMenuItem<void>(
              height: 34,
              padding: EdgeInsets.zero,
              enabled: row.enabled,
              onTap: () => run(row),
              // A click on a row is a click in the text: it keeps the
              // keyboard.
              child: TextFieldTapRegion(
                child: SizedBox(
                  width: double.infinity,
                  height: 34,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      spacing: 10,
                      children: [
                        SizedBox(
                          width: 16,
                          child: row.checked
                              ? Icon(Icons.check, size: 16, color: theme.accent)
                              : null,
                        ),
                        if (row.swatch case final swatch?)
                          SizedBox.square(
                            dimension: 16,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: swatch,
                                shape: BoxShape.circle,
                              ),
                            ),
                          )
                        else
                          Icon(row.icon, size: 16, color: theme.muted),
                        Text(row.label),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.theme,
    required this.icon,
    required this.label,
    required this.tip,
    required this.onTap,
    this.width = EditorToolbar.buttonWidth,
    this.active,
    this.enabled = true,
    this.value,
    this.content,
  });

  final GroveTheme theme;
  final IconData icon;
  final String label;
  final String tip;
  final VoidCallback onTap;
  final double width;

  /// On or off, for a tool that is a switch. Null for the others.
  final bool? active;

  /// A grey tool does nothing.
  final bool enabled;

  /// What a screen reader says after the label, like the size of the text.
  final String? value;

  /// What the button shows in the colour given, in place of its icon.
  final Widget Function(Color color)? content;

  @override
  Widget build(BuildContext context) {
    final on = active ?? false;
    final color = !enabled
        ? theme.muted.withValues(alpha: 0.35)
        : on
        ? theme.accent
        : theme.muted;
    final tap = enabled ? onTap : null;
    return Tooltip(
      message: tip,
      excludeFromSemantics: true,
      child: Semantics(
        container: true,
        button: true,
        label: label,
        value: value,
        toggled: active,
        enabled: enabled,
        onTap: tap,
        excludeSemantics: true,
        child: MouseRegion(
          cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: tap,
            child: SizedBox(
              width: width,
              height: 24,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: on ? theme.accent.withValues(alpha: 0.16) : null,
                  borderRadius: BorderRadius.circular(5),
                ),
                child:
                    content?.call(color) ?? Icon(icon, size: 15, color: color),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Small pictures of the images in a text. The text itself shows only the
/// name of each image.
class ImageStrip extends StatelessWidget {
  const ImageStrip({
    super.key,
    required this.ids,
    required this.controller,
    required this.services,
  });

  final List<String> ids;
  final MarkdownController controller;
  final EditorServices services;

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    return ValueListenableBuilder<String?>(
      valueListenable: controller.previewImage,
      builder: (context, preview, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 6,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              spacing: 8,
              children: [for (final id in ids) _thumb(theme, id)],
            ),
          ),
          if (preview != null) _preview(theme, preview),
        ],
      ),
    );
  }

  Widget _thumb(GroveTheme theme, String id) {
    final data = services.loadImage(id);
    return SizedBox(
      key: ValueKey('image-$id'),
      width: 72,
      height: 54,
      child: Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => controller.previewImage.value =
                controller.previewImage.value == id ? null : id,
            child: DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: theme.line),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: ColoredBox(
                  color: theme.surface2,
                  child: data == null
                      ? Icon(
                          Icons.broken_image_outlined,
                          size: 18,
                          color: theme.muted,
                        )
                      : _picture(data, BoxFit.cover, theme),
                ),
              ),
            ),
          ),
          Positioned(
            top: 1,
            right: 1,
            child: _RemoveButton(
              onTap: () {
                if (controller.previewImage.value == id) {
                  controller.previewImage.value = null;
                }
                controller.removeImage(id);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _preview(GroveTheme theme, String id) {
    final data = services.loadImage(id);
    return GestureDetector(
      key: const ValueKey('image-preview'),
      onTap: () => controller.previewImage.value = null,
      child: data == null
          ? Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'This image is gone.',
                style: theme.body(12).copyWith(color: theme.muted),
              ),
            )
          : ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520, maxHeight: 420),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: _picture(data, BoxFit.contain, theme),
              ),
            ),
    );
  }

  Widget _picture(Uint8List data, BoxFit fit, GroveTheme theme) => Image.memory(
    data,
    fit: fit,
    gaplessPlayback: true,
    errorBuilder: (context, error, stack) =>
        Icon(Icons.broken_image_outlined, size: 18, color: theme.muted),
  );
}

class _RemoveButton extends StatelessWidget {
  const _RemoveButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'Remove this image',
    excludeFromSemantics: true,
    child: Semantics(
      container: true,
      button: true,
      label: 'Remove this image',
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.all(2),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Color(0x99000000),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.close, size: 13, color: Color(0xFFFFFFFF)),
          ),
        ),
      ),
    ),
  );
}

/// The `[[` list, under the place where the `[[` is.
class _MentionLayer extends StatelessWidget {
  const _MentionLayer({
    required this.link,
    required this.controller,
    required this.theme,
    required this.caret,
  });

  final LayerLink link;
  final MarkdownController controller;
  final GroveTheme theme;
  final ({Rect line, Offset origin})? Function() caret;

  @override
  Widget build(BuildContext context) {
    // The parts of the window the list must keep out of: the bars of a
    // phone and its keyboard.
    final media = MediaQuery.of(context);
    final keyboard = media.viewInsets.bottom;
    final safe = media.padding.copyWith(
      bottom: keyboard > media.padding.bottom ? keyboard : media.padding.bottom,
    );
    return CompositedTransformFollower(
      link: link,
      showWhenUnlinked: false,
      child: ValueListenableBuilder<MentionList?>(
        valueListenable: controller.mentions,
        builder: (context, open, _) {
          if (open == null) return const SizedBox();
          return UnderCaret(
            caret: caret,
            repaint: controller,
            safe: safe,
            child: MentionListView(
              theme: theme,
              list: open,
              onPick: controller.accept,
            ),
          );
        },
      ),
    );
  }
}

/// The bubble of a link, under the first line of the link.
class _BubbleLayer extends StatelessWidget {
  const _BubbleLayer({
    required this.link,
    required this.theme,
    required this.repaint,
    required this.caret,
    required this.bubble,
  });

  final LayerLink link;
  final GroveTheme theme;
  final Listenable repaint;
  final ({Rect line, Offset origin})? Function() caret;
  final Widget? bubble;

  @override
  Widget build(BuildContext context) {
    final bubble = this.bubble;
    if (bubble == null) return const SizedBox();
    final media = MediaQuery.of(context);
    final keyboard = media.viewInsets.bottom;
    final safe = media.padding.copyWith(
      bottom: keyboard > media.padding.bottom ? keyboard : media.padding.bottom,
    );
    return CompositedTransformFollower(
      link: link,
      showWhenUnlinked: false,
      child: UnderCaret(
        caret: caret,
        repaint: repaint,
        safe: safe,
        child: bubble,
      ),
    );
  }
}

/// A link of the text: where it is, its address and the words that show.
/// `range` is the whole `[words](address)`, or the bare address; `content`
/// is the place of the words (null for a bare address). `text` is the text
/// it was found in.
class _LinkSpot {
  const _LinkSpot(
    this.text,
    this.range,
    this.address, {
    required this.words,
    required this.bare,
    this.content,
  });

  final String text;
  final Utf16Range range;
  final String address;
  final String words;
  final bool bare;
  final Utf16Range? content;
}

/// Puts the list under the line of the `[[`. It reads the place when it
/// paints, after the text has its new layout. The list goes above the line
/// when there is no room under it, and stays inside the window.
///
/// Its own box starts at the top left of the field. The list may stand above
/// or left of that box, so the box does not cut it and does not keep clicks
/// from it.
class UnderCaret extends SingleChildRenderObjectWidget {
  const UnderCaret({
    super.key,
    required this.caret,
    required this.repaint,
    required this.safe,
    super.child,
  });

  final ({Rect line, Offset origin})? Function() caret;

  /// The list is placed again each time this tells.
  final Listenable repaint;
  final EdgeInsets safe;

  static const gap = 4.0;
  static const edge = 8.0;

  /// Where a list of size `list` goes, from the top left of the field.
  /// `line` is the line of the `[[` in the field, `origin` is where the field
  /// is in the window.
  static Offset place({
    required Rect line,
    required Offset origin,
    required Size list,
    required Size window,
    EdgeInsets safe = EdgeInsets.zero,
  }) {
    final left = safe.left + edge;
    final right = window.width - safe.right - edge;
    final top = safe.top + edge;
    final bottom = window.height - safe.bottom - edge;
    var x = origin.dx + line.left;
    if (x + list.width > right) x = right - list.width;
    if (x < left) x = left;
    final under = origin.dy + line.bottom + gap;
    final over = origin.dy + line.top - gap - list.height;
    var y = under;
    if (under + list.height > bottom) {
      if (over >= top) {
        y = over;
      } else {
        // No room on either side. The side with more room, and all of the
        // list in the window: it then covers the line.
        final below = bottom - under;
        final above = origin.dy + line.top - gap - top;
        y = below >= above ? bottom - list.height : top;
        if (y < top) y = top;
      }
    }
    return Offset(
      (x - origin.dx).roundToDouble(),
      (y - origin.dy).roundToDouble(),
    );
  }

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderUnderCaret(caret, repaint, safe);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderObject renderObject,
  ) {
    (renderObject as _RenderUnderCaret)
      ..caret = caret
      ..repaint = repaint
      ..safe = safe
      ..markNeedsPaint();
  }
}

class _RenderUnderCaret extends RenderShiftedBox {
  _RenderUnderCaret(this.caret, this._repaint, this._safe) : super(null);

  ({Rect line, Offset origin})? Function() caret;

  Listenable _repaint;
  set repaint(Listenable value) {
    if (identical(value, _repaint)) return;
    if (attached) _repaint.removeListener(markNeedsPaint);
    _repaint = value;
    if (attached) _repaint.addListener(markNeedsPaint);
  }

  EdgeInsets _safe;
  set safe(EdgeInsets value) {
    if (value == _safe) return;
    _safe = value;
    markNeedsPaint();
  }

  /// False when the place of the `[[` is not known: nothing is painted and
  /// nothing can be clicked.
  bool _shown = false;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _repaint.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _repaint.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void performLayout() {
    size = constraints.biggest;
    child?.layout(constraints.loosen(), parentUsesSize: true);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    final place = child == null ? null : caret();
    if (child == null || place == null) {
      _shown = false;
      return;
    }
    final at = UnderCaret.place(
      line: place.line,
      origin: place.origin,
      list: child.size,
      window: size,
      safe: _safe,
    );
    (child.parentData! as BoxParentData).offset = at;
    _shown = true;
    context.paintChild(child, offset + at);
  }

  // No look at its own size: the list may stand outside of it.
  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) =>
      _shown && hitTestChildren(result, position: position);
}

/// The rows of the `[[` list.
class MentionListView extends StatelessWidget {
  const MentionListView({
    super.key,
    required this.theme,
    required this.list,
    required this.onPick,
  });

  final GroveTheme theme;
  final MentionList list;
  final ValueChanged<MentionSuggestion> onPick;

  static IconData icon(ItemType type) => switch (type) {
    ItemType.task => Icons.check_circle_outline,
    ItemType.note => Icons.sticky_note_2_outlined,
    ItemType.event => Icons.calendar_month_outlined,
  };

  @override
  Widget build(BuildContext context) => TextFieldTapRegion(
    child: Material(
      type: MaterialType.transparency,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.solidSurface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: theme.line),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 14,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: SizedBox(
          width: RichTextField.listWidth,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (i, item) in list.items.indexed)
                  _row(item, selected: i == list.selected),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _row(MentionSuggestion item, {required bool selected}) => Semantics(
    container: true,
    button: true,
    selected: selected,
    label: '${item.kind}: ${item.title}',
    onTap: () => onPick(item),
    excludeSemantics: true,
    child: MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        key: ValueKey('mention-${item.id}'),
        behavior: HitTestBehavior.opaque,
        onTap: () => onPick(item),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: selected ? theme.accent.withValues(alpha: 0.14) : null,
            borderRadius: BorderRadius.circular(6),
          ),
          child: SizedBox(
            height: RichTextField.listRow,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                spacing: 8,
                children: [
                  Icon(icon(item.ref.type), size: 14, color: theme.muted),
                  Expanded(
                    child: Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.body(12).copyWith(color: theme.ink),
                    ),
                  ),
                  Text(
                    item.kind,
                    style: theme.body(10).copyWith(color: theme.muted),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
