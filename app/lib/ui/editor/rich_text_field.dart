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
import 'package:grove/core/parsing/markdown_spans.dart';
import 'package:grove/state/state.dart' hide MotionRules;

import '../theme/grove_theme.dart';
import 'editor_tools.dart';
import 'markdown_controller.dart';

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
  final _fieldKey = GlobalKey();

  /// The text the owner of the field knows.
  String _reported = '';
  bool _loading = false;

  /// Where the pointer went down, and the selection at that time. A click
  /// on a check box leaves the caret where it was.
  Offset? _downAt;
  TextSelection? _selectionAtDown;

  /// The link of the last click that went to the browser, and the time of
  /// that click. The second click of a double click opens nothing.
  String? _lastLink;
  Duration? _lastLinkAt;

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
          _linkClicked(span.kind.url ?? '', event.timeStamp);
        default:
          break;
      }
    });
  }

  /// A click or a tap on a web link opens the browser. The Mac app wants
  /// Command with the click; a phone has no such key, so here a plain click
  /// does it (Q-16 of `docs/questions.md`).
  void _linkClicked(String text, Duration at) {
    final open = _openLink;
    // Only `http` and `https`. Any other link does nothing.
    final url = webLink(text);
    if (open == null || url == null) return;
    final last = _lastLinkAt;
    if (_lastLink == text &&
        last != null &&
        (at - last).abs() < kDoubleTapTimeout) {
      return;
    }
    _lastLink = text;
    _lastLinkAt = at;
    final services = controller.services;
    void failed() => services.notify('Grove could not open the link.');
    unawaited(
      Future.sync(() => open(url)).then((opened) {
        if (!opened) failed();
      }, onError: (Object _) => failed()),
    );
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
            child: CompositedTransformTarget(
              link: _link,
              child: _field(theme, look),
            ),
          ),
          if (canPlan) _PlannerButton(theme: theme, onTap: c.addToPlanner),
        ],
      ),
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
  /// line can do it.
  Widget _menu(BuildContext context, EditableTextState state) {
    final c = controller;
    void run(VoidCallback action) {
      ContextMenuController.removeAny();
      action();
    }

    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: state.contextMenuAnchors,
      buttonItems: [
        ...state.contextMenuButtonItems,
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

/// An arrow key, with or without Shift, steps over hidden marks: one key is
/// one letter that shows. With "Show marks" on, the field does it as always.
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
    if (c.showMarks || !selection.isValid || c.hiddenRuns.isEmpty) {
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

/// The row of buttons above an editor: bold, italic, code, lists, heading,
/// quote, mention, image.
class EditorToolbar extends StatelessWidget {
  const EditorToolbar({
    super.key,
    required this.controller,
    this.onImage,
    this.before,
  });

  final MarkdownController controller;

  /// Null when the app cannot pick a picture. The button is then not there.
  final VoidCallback? onImage;

  /// Runs before each button, to give the text the keyboard.
  final VoidCallback? before;

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    final apple =
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.iOS;
    final mod = apple ? '⌘' : 'Ctrl+';
    Widget button(
      IconData icon,
      String name,
      VoidCallback action, {
      String? tip,
    }) => _ToolButton(
      theme: theme,
      icon: icon,
      label: name,
      tip: tip ?? name,
      onTap: () {
        before?.call();
        action();
      },
    );
    Widget format(IconData icon, String name, EditorFormat f, {String? key}) =>
        button(
          icon,
          name,
          () => controller.format(f),
          tip: key == null ? name : '$name  $mod$key',
        );
    final divider = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: SizedBox(
        width: 1,
        height: 14,
        child: ColoredBox(color: theme.line),
      ),
    );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        spacing: 2,
        children: [
          format(Icons.format_bold, 'Bold', EditorFormat.bold, key: 'B'),
          format(Icons.format_italic, 'Italic', EditorFormat.italic, key: 'I'),
          format(Icons.code, 'Code', EditorFormat.code, key: 'E'),
          divider,
          format(
            Icons.format_list_bulleted,
            'Bullet list',
            EditorFormat.bullet,
          ),
          format(
            Icons.format_list_numbered,
            'Numbered list',
            EditorFormat.numbered,
          ),
          format(Icons.checklist, 'Checklist', EditorFormat.checklist),
          divider,
          format(Icons.format_size, 'Heading', EditorFormat.heading),
          format(Icons.format_quote, 'Quote', EditorFormat.quote),
          divider,
          button(
            Icons.alternate_email,
            'Mention',
            controller.startMention,
            tip: 'Mention a task, event or note  [[',
          ),
          if (onImage != null)
            button(Icons.image_outlined, 'Add an image', onImage!),
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
  });

  final GroveTheme theme;
  final IconData icon;
  final String label;
  final String tip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tip,
    excludeFromSemantics: true,
    child: Semantics(
      container: true,
      button: true,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(
            width: 26,
            height: 24,
            child: Icon(icon, size: 15, color: theme.muted),
          ),
        ),
      ),
    ),
  );
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
