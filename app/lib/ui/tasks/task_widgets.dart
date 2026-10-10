// The small parts the Tasks panel, the Goals panel and the task inspector
// share: the chip, the text field, the menu, the pickers and the bar.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:grove/core/model/day_key.dart';
import 'package:grove/core/model/task_color.dart';
import 'package:grove/state/state.dart' hide MotionRules;

import '../theme/grove_theme.dart';
import '../theme/named_colors.dart';
import '../theme/panel.dart';
import 'task_format.dart';

/// Builds again each time the store changes.
class StoreBuilder extends StatefulWidget {
  const StoreBuilder({
    super.key,
    required this.store,
    required this.builder,
    this.onChange,
  });

  final AppStore store;
  final WidgetBuilder builder;

  /// Runs before each build that a store change causes.
  final VoidCallback? onChange;

  @override
  State<StoreBuilder> createState() => _StoreBuilderState();
}

class _StoreBuilderState extends State<StoreBuilder> {
  @override
  void initState() {
    super.initState();
    widget.store.addListener(_changed);
  }

  @override
  void didUpdateWidget(StoreBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      oldWidget.store.removeListener(_changed);
      widget.store.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.store.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    // A change can come in the middle of a frame. The work waits for its end.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _changed());
      return;
    }
    widget.onChange?.call();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}

/// A small rounded label.
class TaskChip extends StatelessWidget {
  const TaskChip(this.text, {super.key, this.icon, this.tint});

  final String text;
  final IconData? icon;

  /// The muted colour of the theme when null.
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    final colour = tint ?? theme.muted;
    return ThemedChip(
      tint: colour,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 3,
        children: [
          if (icon != null) Icon(icon, size: 10, color: colour),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme
                  .body(10, weight: FontWeight.w500)
                  .copyWith(color: colour),
            ),
          ),
        ],
      ),
    );
  }
}

/// A small button that is only an icon.
class IconTap extends StatelessWidget {
  const IconTap({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.size = 15,
    this.color,
    this.tip,
  });

  final IconData icon;

  /// What a screen reader says.
  final String label;

  /// null means the button is off.
  final VoidCallback? onTap;
  final double size;
  final Color? color;

  /// The text of the tooltip. `label` when null.
  final String? tip;

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    return Tooltip(
      message: tip ?? label,
      excludeFromSemantics: true,
      child: Semantics(
        container: true,
        button: true,
        enabled: onTap != null,
        label: label,
        onTap: onTap,
        excludeSemantics: true,
        child: MouseRegion(
          cursor: onTap == null
              ? SystemMouseCursors.basic
              : SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: Icon(icon, size: size, color: color ?? theme.muted),
            ),
          ),
        ),
      ),
    );
  }
}

/// A text button with no box.
class TextTap extends StatelessWidget {
  const TextTap({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    return Semantics(
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
          child: Text(
            label,
            style: theme.body(12).copyWith(color: theme.accent),
          ),
        ),
      ),
    );
  }
}

/// A text field in the look of the theme. Return calls `onSubmitted`. Esc
/// calls `onEscape`. `boxed` gives it a filled box whose border shows the
/// focus.
class GroveField extends StatefulWidget {
  const GroveField({
    super.key,
    required this.controller,
    required this.placeholder,
    this.focusNode,
    this.style,
    this.minLines = 1,
    this.maxLines = 1,
    this.maxLength,
    this.boxed = false,
    this.fill,
    this.radius = 8,
    this.padding = const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    this.leading,
    this.keepFocus = false,
    this.newlines = false,
    this.autofocus = false,
    this.onChanged,
    this.onSubmitted,
    this.onEscape,
    this.label,
  });

  final TextEditingController controller;
  final String placeholder;
  final FocusNode? focusNode;

  /// `theme.body(13)` in the ink colour when null.
  final TextStyle? style;
  final int minLines;
  final int maxLines;
  final int? maxLength;
  final bool boxed;

  /// The fill of the box. `surface2` when null.
  final Color? fill;
  final double radius;
  final EdgeInsets padding;

  /// Shown in front of the text, inside the box.
  final Widget? leading;

  /// Return leaves the focus in the field, for the next entry.
  final bool keepFocus;

  /// Return makes a new line. Without it, Return ends the text.
  final bool newlines;
  final bool autofocus;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onEscape;

  /// What a screen reader says. The placeholder when null.
  final String? label;

  @override
  State<GroveField> createState() => _GroveFieldState();
}

class _GroveFieldState extends State<GroveField> {
  FocusNode? _own;

  FocusNode get _focus => widget.focusNode ?? (_own ??= FocusNode());

  @override
  void initState() {
    super.initState();
    _focus.addListener(_focusChanged);
  }

  @override
  void didUpdateWidget(GroveField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      (oldWidget.focusNode ?? _own)?.removeListener(_focusChanged);
      _focus.addListener(_focusChanged);
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_focusChanged);
    _own?.dispose();
    super.dispose();
  }

  void _focusChanged() {
    if (mounted && widget.boxed) setState(() {});
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    final onEscape = widget.onEscape;
    if (onEscape != null &&
        event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      onEscape();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    final style = widget.style ?? theme.body(13).copyWith(color: theme.ink);
    final length = widget.maxLength;
    final field = Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _key,
      child: Semantics(
        label: widget.label,
        child: TextField(
          controller: widget.controller,
          focusNode: _focus,
          autofocus: widget.autofocus,
          minLines: widget.minLines,
          maxLines: widget.maxLines,
          style: style,
          cursorColor: theme.accent,
          keyboardType: widget.newlines
              ? TextInputType.multiline
              : TextInputType.text,
          textInputAction: widget.newlines
              ? TextInputAction.newline
              : TextInputAction.done,
          inputFormatters: [
            if (length != null) LengthLimitingTextInputFormatter(length),
          ],
          decoration: InputDecoration.collapsed(
            hintText: widget.placeholder,
            hintStyle: style.copyWith(
              color: theme.muted,
              decoration: TextDecoration.none,
            ),
          ),
          onChanged: widget.onChanged,
          onEditingComplete: widget.keepFocus ? () {} : null,
          onSubmitted: widget.onSubmitted,
        ),
      ),
    );
    if (!widget.boxed) return field;
    final focused = _focus.hasFocus;
    final leading = widget.leading;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: widget.fill ?? theme.surface2,
        borderRadius: BorderRadius.circular(widget.radius),
        border: Border.all(color: focused ? theme.accent : theme.line),
      ),
      child: Padding(
        padding: widget.padding,
        child: leading == null
            ? field
            : Row(
                spacing: 8,
                children: [
                  leading,
                  Expanded(child: field),
                ],
              ),
      ),
    );
  }
}

/// One line of a menu: a choice, a title or a divider.
class MenuLine {
  const MenuLine(this.label, this.action, {this.checked = false})
    : isDivider = false;

  /// A title above a group of choices. It cannot be picked.
  const MenuLine.title(this.label)
    : action = null,
      checked = false,
      isDivider = false;

  const MenuLine.divider()
    : label = '',
      action = null,
      checked = false,
      isDivider = true;

  final String label;
  final VoidCallback? action;

  /// Shows a check mark in front of the label.
  final bool checked;
  final bool isDivider;
}

/// Opens a menu at a place of the window and runs the choice.
Future<void> showGroveMenu(
  BuildContext context,
  Offset global,
  List<MenuLine> lines,
) async {
  final theme = GroveTheme.of(context);
  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  final action = await showMenu<VoidCallback>(
    context: context,
    color: theme.solidSurface,
    position: RelativeRect.fromRect(
      global & Size.zero,
      Offset.zero & overlay.size,
    ),
    items: [
      for (final line in lines)
        if (line.isDivider)
          const PopupMenuDivider(height: 9)
        else if (line.action == null)
          PopupMenuItem<VoidCallback>(
            enabled: false,
            height: 22,
            child: Text(
              line.label,
              style: theme
                  .body(11, weight: FontWeight.w600)
                  .copyWith(color: theme.muted),
            ),
          )
        else
          PopupMenuItem<VoidCallback>(
            value: line.action,
            height: 28,
            child: Text(
              line.checked ? '✓ ${line.label}' : line.label,
              style: theme.body(13).copyWith(color: theme.ink),
            ),
          ),
    ],
  );
  action?.call();
}

/// A value with a small arrow. A click opens the list of values.
class MenuPick<T> extends StatelessWidget {
  const MenuPick({
    super.key,
    required this.value,
    required this.values,
    required this.name,
    required this.onPick,
    required this.label,
  });

  final T value;
  final List<T> values;
  final String Function(T) name;
  final ValueChanged<T> onPick;

  /// What a screen reader says in front of the value.
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    void open() {
      final box = context.findRenderObject()! as RenderBox;
      showGroveMenu(context, box.localToGlobal(Offset(0, box.size.height)), [
        for (final v in values)
          MenuLine(name(v), () => onPick(v), checked: v == value),
      ]);
    }

    return Semantics(
      container: true,
      button: true,
      label: label,
      value: name(value),
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
              padding: const EdgeInsets.fromLTRB(8, 3, 4, 3),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 2,
                children: [
                  Flexible(
                    child: Text(
                      name(value),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.body(12).copyWith(color: theme.ink),
                    ),
                  ),
                  Icon(Icons.unfold_more, size: 13, color: theme.muted),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Buttons side by side. One is chosen. They never take the keyboard
/// focus, so a name being typed beside them stays in its field.
class Segments<T> extends StatelessWidget {
  const Segments({
    super.key,
    required this.value,
    required this.values,
    required this.name,
    required this.onPick,
    required this.label,
    this.fill,
    this.chosenFill,
    this.tip,
  });

  final T value;
  final List<T> values;
  final String Function(T) name;
  final ValueChanged<T> onPick;

  /// What a screen reader says for the group.
  final String label;

  /// The colour of the box. `surface` when null.
  final Color? fill;

  /// The colour of the chosen button. `surface2` when null.
  final Color? chosenFill;
  final String Function(T)? tip;

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    Widget button(T v) {
      final chosen = v == value;
      void pick() {
        if (!chosen) onPick(v);
      }

      final inside = Semantics(
        container: true,
        button: true,
        selected: chosen,
        label: name(v),
        onTap: pick,
        excludeSemantics: true,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: pick,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: chosen ? (chosenFill ?? theme.surface2) : null,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  name(v),
                  maxLines: 1,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: theme
                      .body(11, weight: FontWeight.w600)
                      .copyWith(color: chosen ? theme.ink : theme.muted),
                ),
              ),
            ),
          ),
        ),
      );
      final text = tip?.call(v);
      return Expanded(
        child: text == null
            ? inside
            : Tooltip(message: text, excludeFromSemantics: true, child: inside),
      );
    }

    return Semantics(
      container: true,
      label: label,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: fill ?? theme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: theme.line),
        ),
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Row(spacing: 2, children: [for (final v in values) button(v)]),
        ),
      ),
    );
  }
}

/// "No colour", then the eight task colours. The chosen one has a ring.
class ColourDots extends StatelessWidget {
  const ColourDots({super.key, required this.current, required this.onPick});

  /// One of `TaskColor.names`, or "" for none.
  final String current;
  final ValueChanged<String> onPick;

  static String _capital(String name) =>
      name.isEmpty ? name : name[0].toUpperCase() + name.substring(1);

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    Widget dot(String name) {
      final chosen = current == name;
      return Tooltip(
        message: _capital(name),
        excludeFromSemantics: true,
        child: Semantics(
          container: true,
          button: true,
          selected: chosen,
          label: 'Colour $name',
          onTap: () => onPick(name),
          excludeSemantics: true,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              key: ValueKey('colour-$name'),
              behavior: HitTestBehavior.opaque,
              onTap: () => onPick(name),
              child: Container(
                width: 21,
                height: 21,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: chosen
                      ? Border.all(color: theme.ink, width: 2)
                      : null,
                ),
                child: SizedBox.square(
                  dimension: 15,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: TaskPalette.color(name) ?? theme.muted,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconTap(
          key: const ValueKey('colour-none'),
          icon: Icons.block,
          label: 'No colour',
          size: 15,
          color: current.isEmpty ? theme.ink : theme.muted,
          onTap: () => onPick(''),
        ),
        for (final name in TaskColor.names) dot(name),
      ],
    );
  }
}

/// A thin bar. The filled part is `fraction` of it.
class ProgressBar extends StatelessWidget {
  const ProgressBar({super.key, required this.fraction});

  final double fraction;

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    final part = fraction.clamp(0.0, 1.0);
    return Semantics(
      container: true,
      label: 'Progress',
      value: '${(part * 100).round()} percent',
      child: SizedBox(
        height: 6,
        child: DecoratedBox(
          decoration: ShapeDecoration(
            color: theme.surface2,
            shape: const StadiumBorder(),
          ),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: part,
            child: DecoratedBox(
              decoration: ShapeDecoration(
                color: theme.accent,
                shape: const StadiumBorder(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A small filled or plain button of a card.
class CardButton extends StatelessWidget {
  const CardButton({
    super.key,
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    return Semantics(
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
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: primary ? theme.accent : theme.surface,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: primary ? theme.accent : theme.line),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              child: Text(
                label,
                maxLines: 1,
                style: theme
                    .body(11, weight: FontWeight.w600)
                    .copyWith(color: primary ? theme.bg : theme.ink),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A day with a small calendar. A click opens the date picker.
class DayPick extends StatelessWidget {
  const DayPick({
    super.key,
    required this.day,
    required this.label,
    required this.onPick,
  });

  final DayKey day;

  /// What a screen reader says in front of the day.
  final String label;
  final ValueChanged<DayKey> onPick;

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    final text = TaskFormat.dateLabel(day);
    Future<void> open() async {
      final picked = await showDatePicker(
        context: context,
        initialDate: day.date,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100, 12, 31),
      );
      if (picked != null) onPick(DayKey.fromDate(picked));
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
              padding: const EdgeInsets.fromLTRB(8, 3, 6, 3),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 5,
                children: [
                  Text(text, style: theme.body(12).copyWith(color: theme.ink)),
                  Icon(
                    Icons.calendar_today_outlined,
                    size: 11,
                    color: theme.muted,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Does a store write after the frame in work. A widget that goes away, or
/// that gets a new task, uses this to save what the user typed: the store
/// must not change in the middle of a frame.
void writeLater(AppStore store, VoidCallback write) => scheduleMicrotask(() {
  if (!store.isDisposed) write();
});
