// The link of a rich text box: the window that makes or changes one (the
// Link tool, ⌘K or Ctrl+K), and the small bubble under a link that was
// clicked, with Open, Edit and Remove.
import 'package:flutter/material.dart';
import 'package:grove/core/parsing/markdown_edit.dart';

import '../planner/planner_dialogs.dart';
import '../theme/grove_theme.dart';
import '../theme/panel.dart';
import 'editor_tools.dart';

/// What the link window gives back: the words that show, and the address.
typedef LinkInput = ({String words, String address});

/// The address as the text keeps it, or null when it is not a web address
/// Grove may open (only `http` and `https`, Q-16). A bare host such as
/// `example.com` gets `https://`; it needs a dot, so a lone word is no
/// address.
String? linkTarget(String typed) {
  final t = typed.trim();
  // `mailto:` or `ftp://` is a scheme; `example.com:8080` is a host.
  final scheme = RegExp(
    r'^[a-z][a-z0-9+-]*:',
    caseSensitive: false,
  ).hasMatch(t);
  if (scheme && !RegExp(r'^https?://', caseSensitive: false).hasMatch(t)) {
    return null;
  }
  if (!scheme) {
    final host = t.split(RegExp('[/?#:]')).first;
    if (!host.contains('.') || host.startsWith('.') || host.endsWith('.')) {
      return null;
    }
  }
  final full = MarkdownEdit.linkAddress(t);
  return full != null && webLink(full) != null ? full : null;
}

/// The address short enough for the bubble: no `https://`, no `www.`, no
/// `/` at the end.
String shortAddress(String url) => url
    .replaceFirst(RegExp(r'^https?://', caseSensitive: false), '')
    .replaceFirst(RegExp(r'^www\.', caseSensitive: false), '')
    .replaceFirst(RegExp(r'/$'), '');

/// Opens the link window. Null when the person closed it with Cancel.
Future<LinkInput?> showLinkDialog(
  BuildContext context, {
  String words = '',
  String address = '',
}) => showDialog<LinkInput>(
  context: context,
  builder: (_) => LinkDialog(words: words, address: address),
);

/// The fields "Words" and "Web address", with Cancel and Save. Save is off
/// until the address is one Grove may open.
class LinkDialog extends StatefulWidget {
  const LinkDialog({super.key, this.words = '', this.address = ''});

  final String words;
  final String address;

  @override
  State<LinkDialog> createState() => _LinkDialogState();
}

class _LinkDialogState extends State<LinkDialog> {
  late final _words = TextEditingController(text: widget.words);
  late final _address = TextEditingController(text: widget.address);

  @override
  void initState() {
    super.initState();
    _address.addListener(_changed);
  }

  @override
  void dispose() {
    _words.dispose();
    _address.dispose();
    super.dispose();
  }

  void _changed() => setState(() {});

  bool get _ready => linkTarget(_address.text) != null;

  void _save() {
    if (!_ready) return;
    Navigator.of(context).pop((words: _words.text, address: _address.text));
  }

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    return PlannerSheet(
      key: const ValueKey('link-dialog'),
      width: 380,
      children: [
        ThemedHeading(widget.address.isEmpty ? 'Add link' : 'Edit link', 18),
        _field(
          theme,
          label: 'Words',
          key: 'link-words',
          controller: _words,
          hint: 'The words that show',
          // With words already there, the address is what is missing.
          autofocus: widget.words.isEmpty && widget.address.isEmpty,
        ),
        _field(
          theme,
          label: 'Web address',
          key: 'link-address',
          controller: _address,
          hint: 'example.com',
          autofocus: widget.words.isNotEmpty || widget.address.isNotEmpty,
        ),
        dialogButtons([
          DialogButton(
            label: 'Cancel',
            onTap: () => Navigator.of(context).pop(),
          ),
          DialogButton(
            label: 'Save',
            primary: true,
            onTap: _ready ? _save : null,
          ),
        ]),
      ],
    );
  }

  Widget _field(
    GroveTheme theme, {
    required String label,
    required String key,
    required TextEditingController controller,
    required String hint,
    required bool autofocus,
  }) {
    final style = theme.body(13).copyWith(color: theme.ink);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 4,
      children: [
        Text(label, style: theme.body(12).copyWith(color: theme.muted)),
        DecoratedBox(
          decoration: BoxDecoration(
            color: theme.surface2,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: theme.line),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: TextField(
              key: ValueKey(key),
              controller: controller,
              autofocus: autofocus,
              maxLines: 1,
              style: style,
              cursorColor: theme.accent,
              autocorrect: false,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration.collapsed(
                hintText: hint,
                hintStyle: style.copyWith(color: theme.muted),
              ),
              onSubmitted: (_) => _save(),
            ),
          ),
        ),
      ],
    );
  }
}

/// The bubble under a link that was clicked: the short address, then Open
/// (when Grove may open it), Edit, and Remove (for a link with its own
/// words). A click on it keeps the keyboard in the text; a click anywhere
/// else closes it.
class LinkBubble extends StatelessWidget {
  const LinkBubble({
    super.key,
    required this.theme,
    required this.address,
    required this.onClose,
    required this.onEdit,
    this.onOpen,
    this.onRemove,
  });

  final GroveTheme theme;
  final String address;
  final VoidCallback onClose;
  final VoidCallback onEdit;

  /// Null: no Open.
  final VoidCallback? onOpen;

  /// Null: no Remove.
  final VoidCallback? onRemove;

  static const maxAddressWidth = 220.0;

  @override
  Widget build(BuildContext context) => TextFieldTapRegion(
    child: TapRegion(
      onTapOutside: (_) => onClose(),
      child: Material(
        key: const ValueKey('link-bubble'),
        type: MaterialType.transparency,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: theme.solidSurface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: theme.line),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 14,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 6,
              children: [
                Icon(Icons.link, size: 14, color: theme.muted),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: maxAddressWidth),
                  child: Text(
                    shortAddress(address),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.body(12).copyWith(color: theme.muted),
                  ),
                ),
                if (onOpen case final open?) _button('Open', open),
                _button('Edit', onEdit),
                if (onRemove case final remove?) _button('Remove', remove),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _button(String label, VoidCallback onTap) => Semantics(
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
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Text(
            label,
            style: theme
                .body(12, weight: FontWeight.w600)
                .copyWith(color: theme.accent),
          ),
        ),
      ),
    ),
  );
}
