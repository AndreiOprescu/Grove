// Port of Sources/Grove/Shared/CommandPalette.swift: ⌘K. Search tasks,
// events and notes, run commands, jump to a day (PLAN §5.5 item 11). Up and
// down choose a row. Return runs it. Esc closes. A `>` first keeps only
// the commands.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:grove/core/parsing/palette_rules.dart';
import 'package:grove/state/state.dart';

import '../tasks/task_widgets.dart' show WholeCenter;
import '../theme/grove_theme.dart';
import '../theme/panel.dart';
import '../theme/symbols.dart';
import 'shell_layout.dart';
import 'top_buttons.dart';

/// Shows the palette over `child` while the store says it is open. Swift:
/// the overlay of `RootView`, with a fade of 0.12 s.
class PaletteHost extends StatelessWidget {
  const PaletteHost({super.key, required this.store, required this.child});

  final AppStore store;
  final Widget child;

  static const fade = Duration(milliseconds: 120);

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      child,
      ListenableBuilder(
        listenable: store,
        builder: (context, _) => AnimatedSwitcher(
          duration: fade,
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeOut,
          child: store.paletteOpen
              ? CommandPalette(key: const ValueKey('palette'), store: store)
              : const SizedBox.shrink(),
        ),
      ),
    ],
  );
}

class CommandPalette extends StatefulWidget {
  const CommandPalette({super.key, required this.store});

  final AppStore store;

  /// The width of the box on a desktop window.
  static const width = 560.0;

  /// From the top of the window to the box.
  static const top = 90.0;

  /// One row, and the room it takes with the gap under it.
  static const rowHeight = 42.0;
  static const rowPitch = 44.0;
  static const listPadding = 8.0;

  /// The list is never higher than this.
  static const listHeight = 360.0;

  static const placeholder = 'Search, or type > for commands';
  static const nothingFound = 'Nothing found.';
  static const typeADay = 'Type a day, like fri, tomorrow or oct 9.';

  /// The field with its line, and the line of hints at the bottom.
  static const fieldHeight = 53.0;
  static const footerHeight = 28.0;

  /// How high the list of `rows` rows is. `most` is the room a small
  /// window leaves.
  static double heightFor(int rows, {double most = listHeight}) => math.max(
    rowPitch,
    math.min(rows * rowPitch + 2 * listPadding, math.min(most, listHeight)),
  );

  @override
  State<CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<CommandPalette> {
  late final _text = TextEditingController(text: widget.store.paletteText);
  final _focus = FocusNode(debugLabel: 'palette');
  final _scroll = ScrollController();
  int _selected = 0;

  /// The room for the list in this window, set when the box is drawn.
  double _room = CommandPalette.listHeight;

  AppStore get _store => widget.store;

  @override
  void initState() {
    super.initState();
    _store.addListener(_storeChanged);
    // `autofocus` does not take the keys from a thing that has them.
    _focus.requestFocus();
  }

  @override
  void dispose() {
    _store.removeListener(_storeChanged);
    _text.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _storeChanged() {
    if (!mounted) return;
    // "Go to date…" writes the text itself.
    if (_store.paletteText != _text.text) {
      _text.value = TextEditingValue(
        text: _store.paletteText,
        selection: TextSelection.collapsed(offset: _store.paletteText.length),
      );
      _selected = 0;
      if (_store.paletteOpen) _focus.requestFocus();
    }
    setState(() {});
  }

  void _typed(String text) {
    _selected = 0;
    if (_scroll.hasClients) _scroll.jumpTo(0);
    _store.paletteText = text;
  }

  // The key handlers read the rows and the choice when the key is pressed,
  // not when the box was drawn. Two quick presses can come before the next
  // draw.

  List<PaletteItem> get _rows => _store.paletteItems(_store.paletteText);

  void _move(int step) {
    final count = _rows.length;
    if (count == 0) return;
    setState(() {
      _selected = math.max(
        0,
        math.min(count - 1, math.min(_selected, count - 1) + step),
      );
    });
    _show(_selected, count);
  }

  /// Scrolls the list so that row `index` is in view.
  void _show(int index, int count) {
    if (!_scroll.hasClients) return;
    const pad = CommandPalette.listPadding;
    final top = pad + index * CommandPalette.rowPitch;
    final bottom = top + CommandPalette.rowHeight;
    final view = CommandPalette.heightFor(count, most: _room);
    final at = _scroll.offset;
    if (top - pad < at) {
      _scroll.jumpTo(top - pad);
    } else if (bottom + pad > at + view) {
      _scroll.jumpTo(bottom + pad - view);
    }
  }

  void _runChosen() {
    final rows = _rows;
    if (rows.isEmpty) return;
    _store.runPalette(rows[math.min(_selected, rows.length - 1)]);
  }

  void _close() => _store.paletteOpen = false;

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    final rows = _rows;
    final chosen = math.min(_selected, math.max(0, rows.length - 1));
    final media = MediaQuery.of(context);
    final window = media.size;
    final phone = ShellRules.layoutFor(window.width) == ShellLayout.phone;
    final top = phone ? 12.0 : CommandPalette.top;
    // The list ends over the keyboard of a phone and in a low window.
    _room =
        (window.height -
                media.padding.top -
                math.max(media.padding.bottom, media.viewInsets.bottom) -
                top -
                CommandPalette.fieldHeight -
                CommandPalette.footerHeight -
                12)
            .floorToDouble();
    final box = Panel(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _field(theme),
          ColoredBox(color: theme.line, child: const SizedBox(height: 1)),
          if (rows.isEmpty) _empty(theme) else _list(theme, rows, chosen),
          _footer(theme),
        ],
      ),
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        Semantics(
          label: 'Close search',
          button: true,
          onTap: _close,
          child: GestureDetector(
            key: const ValueKey('palette-scrim'),
            behavior: HitTestBehavior.opaque,
            onTap: _close,
            child: const ColoredBox(color: Color(0x47000000)), // black, 28%
          ),
        ),
        SafeArea(
          child: LayoutBuilder(
            builder: (context, limits) {
              final width = phone
                  ? limits.maxWidth - 24
                  : math.min(CommandPalette.width, limits.maxWidth - 24);
              return Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  // On a whole point, also in a window of an odd width.
                  padding: EdgeInsets.only(
                    left: ((limits.maxWidth - width) / 2).floorToDouble(),
                    top: top,
                  ),
                  child: SizedBox(
                    width: width,
                    // The shadow of the Mac app: black 25%, radius 24, 10
                    // down.
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(theme.radius),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x40000000),
                            blurRadius: 48,
                            offset: Offset(0, 10),
                          ),
                        ],
                      ),
                      // The keys stay in the box while it is open.
                      child: FocusScope(
                        child: Material(
                          type: MaterialType.transparency,
                          child: DefaultTextStyle(
                            style: theme.body(13).copyWith(color: theme.ink),
                            child: box,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // The box

  Widget _field(GroveTheme theme) {
    final style = theme.body(17).copyWith(color: theme.ink);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      // A fixed height, and each part in its middle on a whole point.
      child: SizedBox(
        height: 24,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 10,
          children: [
            WholeCenter(
              child: Icon(
                symbolIcon('magnifyingglass'),
                size: 18,
                color: theme.muted,
              ),
            ),
            Expanded(
              child: WholeCenter(
                child: CallbackShortcuts(
                  bindings: {
                    const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
                        _move(1),
                    const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
                        _move(-1),
                    const SingleActivator(LogicalKeyboardKey.escape): _close,
                  },
                  child: TextField(
                    key: const ValueKey('palette-field'),
                    controller: _text,
                    focusNode: _focus,
                    style: style,
                    cursorColor: theme.accent,
                    maxLines: 1,
                    autocorrect: false,
                    enableSuggestions: false,
                    textInputAction: TextInputAction.go,
                    decoration: InputDecoration.collapsed(
                      hintText: CommandPalette.placeholder,
                      hintStyle: style.copyWith(color: theme.muted),
                    ),
                    onChanged: _typed,
                    // The box stays open after "Go to date…": keep the keys.
                    onEditingComplete: () {},
                    onSubmitted: (_) => _runChosen(),
                    // A click in the box leaves the keys in the field.
                    onTapOutside: (_) {},
                  ),
                ),
              ),
            ),
            WholeCenter(
              child: ExcludeSemantics(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: theme.surface2,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    child: Text(
                      'esc',
                      style: theme
                          .body(10, weight: FontWeight.w600)
                          .copyWith(color: theme.muted),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // The rows

  Widget _empty(GroveTheme theme) => Padding(
    padding: const EdgeInsets.all(16),
    child: Text(
      PaletteRules.asksForDay(_store.paletteText)
          ? CommandPalette.typeADay
          : CommandPalette.nothingFound,
      key: const ValueKey('palette-empty'),
      style: theme.body(13).copyWith(color: theme.muted),
    ),
  );

  Widget _list(GroveTheme theme, List<PaletteItem> rows, int chosen) =>
      SizedBox(
        height: CommandPalette.heightFor(rows.length, most: _room),
        child: ListView.builder(
          key: const ValueKey('palette-list'),
          controller: _scroll,
          padding: const EdgeInsets.all(CommandPalette.listPadding),
          itemExtent: CommandPalette.rowPitch,
          itemCount: rows.length,
          itemBuilder: (context, i) => Align(
            alignment: Alignment.topCenter,
            child: _row(theme, rows[i], isChosen: i == chosen),
          ),
        ),
      );

  Widget _row(GroveTheme theme, PaletteItem item, {required bool isChosen}) {
    final key = item.shortcut;
    return Semantics(
      container: true,
      button: true,
      selected: isChosen,
      onTap: () => _store.runPalette(item),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          key: ValueKey('palette-row-${item.id}'),
          behavior: HitTestBehavior.opaque,
          onTap: () => _store.runPalette(item),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: isChosen ? theme.accent.withValues(alpha: 0.16) : null,
              borderRadius: BorderRadius.circular(9),
            ),
            child: SizedBox(
              height: CommandPalette.rowHeight,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 10,
                  children: [
                    SizedBox(
                      width: 20,
                      child: Icon(
                        symbolIcon(item.symbol),
                        size: 16,
                        color: item.done ? theme.muted : theme.accent,
                      ),
                    ),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          spacing: 1,
                          children: [
                            Text(
                              item.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme
                                  .body(14)
                                  .copyWith(
                                    color: item.done ? theme.muted : theme.ink,
                                    decoration: item.done
                                        ? TextDecoration.lineThrough
                                        : null,
                                    decorationColor: theme.muted,
                                  ),
                            ),
                            if (item.detail.isNotEmpty)
                              Text(
                                item.detail,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme
                                    .body(11)
                                    .copyWith(color: theme.muted),
                              ),
                          ],
                        ),
                      ),
                    ),
                    if (key != null)
                      WholeCenter(
                        child: Text(
                          KeyNames.of(key),
                          style: theme.body(11).copyWith(color: theme.muted),
                        ),
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

  Widget _footer(GroveTheme theme) => DecoratedBox(
    decoration: BoxDecoration(
      border: Border(top: BorderSide(color: theme.line)),
    ),
    child: Padding(
      // One point more at the top, for the line.
      padding: const EdgeInsets.fromLTRB(16, 9, 16, 8),
      child: DefaultTextStyle(
        style: theme.body(11).copyWith(color: theme.muted),
        child: const ExcludeSemantics(
          child: Row(
            spacing: 14,
            children: [Text('↑↓ choose'), Text('⏎ open'), Text('> commands')],
          ),
        ),
      ),
    ),
  );
}
