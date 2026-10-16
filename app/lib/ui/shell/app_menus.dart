// Port of the `.commands` of Sources/Grove/GroveApp.swift: the File, Edit,
// View and Go menus. One list gives the menu bar of a Mac and the keys of
// the whole window on each system, so the two cannot differ.
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../theme/theme_spec.dart';
import 'shell_model.dart';
import 'top_buttons.dart';

/// What the menus do that the shell cannot do by itself. A copy of Grove
/// with no store gives none, and those lines are grey.
class ShellCommands {
  const ShellCommands({
    this.newTask,
    this.newNote,
    this.newEvent,
    this.palette,
    this.undo,
    this.redo,
    this.undoName,
    this.redoName,
    this.zoomIn,
    this.zoomOut,
    this.settings,
  });

  final VoidCallback? newTask;
  final VoidCallback? newNote;
  final VoidCallback? newEvent;

  /// Opens and closes the command palette.
  final VoidCallback? palette;

  /// null: there is nothing to undo, or to redo.
  final VoidCallback? undo;
  final VoidCallback? redo;

  /// What Undo would take back, for example "Add Task".
  final String? undoName;
  final String? redoName;

  /// The hours of the planner get higher, or lower.
  final VoidCallback? zoomIn;
  final VoidCallback? zoomOut;
  final VoidCallback? settings;
}

/// One thing in a menu.
sealed class ShellNode {
  const ShellNode();
}

/// A line between two parts of a menu.
class ShellDivider extends ShellNode {
  const ShellDivider();
}

/// A menu inside a menu.
class ShellSub extends ShellNode {
  const ShellSub(this.label, this.entries);

  final String label;
  final List<ShellEntry> entries;
}

/// One line of a menu that does something.
class ShellEntry extends ShellNode {
  const ShellEntry(
    this.label,
    this.run, {
    this.key,
    this.alt = false,
    this.shift = false,
    this.repeats = false,
    this.moreKeys = const [],
    this.checked,
  });

  final String label;

  /// null: the line is grey and its key does nothing.
  final VoidCallback? run;

  /// The key, pressed with Command (Ctrl on Windows and Android).
  final LogicalKeyboardKey? key;
  final bool alt;
  final bool shift;

  /// A key that is held down runs the line again and again.
  final bool repeats;

  /// Other keys that run the line, with Shift held or not: the + of a
  /// keyboard is = with Shift, and the number pad has its own keys. The menu
  /// shows [key] only.
  final List<LogicalKeyboardKey> moreKeys;

  /// A line that is on or off. null: it is not that kind of line.
  final bool? checked;

  /// The key on this system. null: the line has no key.
  SingleActivator? activator({bool? apple}) {
    final key = this.key;
    if (key == null) return null;
    final onApple = apple ?? KeyNames.apple;
    return SingleActivator(
      key,
      meta: onApple,
      control: !onApple,
      alt: alt,
      shift: shift,
      includeRepeats: repeats,
    );
  }

  /// True when `event` is the key of this line, or one of [moreKeys] with
  /// the same Command (Ctrl) and Alt.
  bool accepts(KeyEvent event, HardwareKeyboard keyboard, {bool? apple}) {
    final activator = this.activator(apple: apple);
    if (activator == null) return false;
    if (activator.accepts(event, keyboard)) return true;
    if (!moreKeys.contains(event.logicalKey)) return false;
    if (event is! KeyDownEvent && !(repeats && event is KeyRepeatEvent)) {
      return false;
    }
    final onApple = apple ?? KeyNames.apple;
    return keyboard.isMetaPressed == onApple &&
        keyboard.isControlPressed == !onApple &&
        keyboard.isAltPressed == alt;
  }

  /// The key the Mac way, like `⌥⌘N`. null: the line has no key.
  String? get shortcut {
    final key = this.key;
    if (key == null) return null;
    return '${alt ? '⌥' : ''}${shift ? '⇧' : ''}⌘${key.keyLabel}';
  }
}

class ShellMenu {
  const ShellMenu(this.title, this.nodes);

  final String title;
  final List<ShellNode> nodes;

  /// The lines that do something, also those of a menu inside.
  Iterable<ShellEntry> get entries sync* {
    for (final node in nodes) {
      switch (node) {
        case ShellEntry():
          yield node;
        case ShellSub():
          yield* node.entries;
        case ShellDivider():
          break;
      }
    }
  }
}

/// How much one "Zoom In" changes the height of an hour. Swift: 1.2.
const zoomStep = 1.2;

/// The menus of the Mac app, in the order of its menu bar.
List<ShellMenu> shellMenus(ShellModel model, ShellCommands commands) => [
  ShellMenu('File', [
    ShellEntry('New Task', commands.newTask, key: LogicalKeyboardKey.keyN),
    ShellEntry(
      'New Note',
      commands.newNote,
      key: LogicalKeyboardKey.keyN,
      alt: true,
    ),
    ShellEntry(
      'New Event',
      commands.newEvent,
      key: LogicalKeyboardKey.keyN,
      shift: true,
    ),
  ]),
  ShellMenu('Edit', [
    ShellEntry(
      commands.undoName == null ? 'Undo' : 'Undo ${commands.undoName}',
      commands.undo,
      key: LogicalKeyboardKey.keyZ,
      repeats: true,
    ),
    ShellEntry(
      commands.redoName == null ? 'Redo' : 'Redo ${commands.redoName}',
      commands.redo,
      key: LogicalKeyboardKey.keyZ,
      shift: true,
      repeats: true,
    ),
  ]),
  ShellMenu('View', [
    ShellEntry('Today', model.showToday, key: LogicalKeyboardKey.keyT),
    ShellEntry(
      'Planner',
      () => model.screen = Screen.planner,
      key: LogicalKeyboardKey.digit1,
    ),
    ShellEntry('Tasks', model.showTasks, key: LogicalKeyboardKey.digit2),
    ShellEntry('Notes Panel', () => model.showLeftPane(LeftPane.notes)),
    ShellEntry('Goals Panel', () => model.showLeftPane(LeftPane.goals)),
    ShellEntry(
      'Calendar',
      () => model.screen = Screen.calendar,
      key: LogicalKeyboardKey.digit3,
    ),
    ShellEntry(
      'Notes',
      () => model.screen = Screen.notes,
      key: LogicalKeyboardKey.digit4,
    ),
    ShellEntry(
      'Garden',
      () => model.screen = Screen.garden,
      key: LogicalKeyboardKey.digit5,
    ),
    ShellEntry(
      'Persona',
      () => model.screen = Screen.persona,
      key: LogicalKeyboardKey.digit6,
    ),
    const ShellDivider(),
    ShellEntry(
      'Zoom In',
      commands.zoomIn,
      key: LogicalKeyboardKey.equal,
      repeats: true,
      moreKeys: const [
        LogicalKeyboardKey.equal,
        LogicalKeyboardKey.add,
        LogicalKeyboardKey.numpadAdd,
      ],
    ),
    ShellEntry(
      'Zoom Out',
      commands.zoomOut,
      key: LogicalKeyboardKey.minus,
      repeats: true,
      moreKeys: const [
        LogicalKeyboardKey.minus,
        LogicalKeyboardKey.numpadSubtract,
      ],
    ),
    const ShellDivider(),
    ShellSub('Theme', [
      for (final spec in ThemeSpec.all)
        ShellEntry(
          spec.name,
          () => model.setTheme(spec.id),
          checked: model.themeId == spec.id,
        ),
    ]),
    ShellSub('Appearance', [
      for (final mode in AppearanceMode.values)
        ShellEntry(
          mode.label,
          () => model.setAppearance(mode),
          checked: model.appearance == mode,
        ),
    ]),
    ShellEntry(
      'Motion',
      () => model.setMotion(!model.motionSetting),
      checked: model.motionSetting,
    ),
  ]),
  ShellMenu('Go', [
    ShellEntry(
      'Command Palette',
      commands.palette,
      key: LogicalKeyboardKey.keyK,
    ),
  ]),
];

/// The line "Settings…" of the app menu of a Mac. It is not in a menu of
/// [shellMenus]; its key works on each system.
ShellEntry settingsEntry(ShellCommands commands) =>
    ShellEntry('Settings…', commands.settings, key: LogicalKeyboardKey.comma);

/// Every line with a key, in the order of the menus.
List<ShellEntry> shellKeys(ShellModel model, ShellCommands commands) => [
  for (final menu in shellMenus(model, commands))
    for (final entry in menu.entries)
      if (entry.key != null) entry,
  settingsEntry(commands),
];

/// Gives the keys of the menus to the whole window. It stands over the
/// navigator: the keys work wherever the focus is.
///
/// A text field that uses a key itself (Undo while typing) takes it first.
/// One key runs one line, the first that fits.
class ShellKeys extends StatelessWidget {
  const ShellKeys({
    super.key,
    required this.entries,
    required this.isFree,
    this.more,
    required this.child,
  });

  /// The lines, read when a key comes.
  final List<ShellEntry> Function() entries;

  /// False while a dialog or a menu is open: the keys of the window under
  /// it do nothing.
  final bool Function() isFree;

  /// More keys, tried after the lines.
  final Map<ShortcutActivator, VoidCallback>? more;

  final Widget child;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!isFree()) return KeyEventResult.ignored;
    final keyboard = HardwareKeyboard.instance;
    for (final entry in entries()) {
      if (!entry.accepts(event, keyboard)) continue;
      // A grey line keeps its key: the key does nothing else.
      entry.run?.call();
      return KeyEventResult.handled;
    }
    for (final MapEntry(key: activator, value: run)
        in (more ?? const {}).entries) {
      if (!activator.accepts(event, keyboard)) continue;
      run();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    onKeyEvent: _onKey,
    child: child,
  );
}

/// The menu bar of a Mac. On the other systems it shows nothing; the keys
/// come from [ShellKeys].
class ShellMenuBar extends StatefulWidget {
  const ShellMenuBar({
    super.key,
    required this.menus,
    required this.commands,
    required this.isFree,
    required this.child,
  });

  final List<ShellMenu> menus;
  final ShellCommands commands;

  /// See [ShellKeys.isFree]. A line picked with the mouse while a dialog is
  /// open does nothing too.
  final bool Function() isFree;
  final Widget child;

  /// True on the system that has a menu bar made by Flutter.
  static bool get isUsed =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

  /// What a line says in the menu. The system menu of Flutter has no check
  /// mark, so a line that is on starts with one.
  static String labelOf(ShellEntry entry) =>
      entry.checked == true ? '✓ ${entry.label}' : entry.label;

  @override
  State<ShellMenuBar> createState() => _ShellMenuBarState();
}

class _ShellMenuBarState extends State<ShellMenuBar> {
  /// The menu bar is sent to the system again only when a line changed.
  String? _madeFor;
  List<PlatformMenuItem> _made = const [];

  /// The newest lines by name. A line of the menu bar looks up what to do
  /// when it is picked, so an old menu never runs an old action.
  Map<String, ShellEntry> _byPath = const {};

  void _pick(String path) {
    if (!widget.isFree()) return;
    _byPath[path]?.run?.call();
  }

  PlatformMenuItem _item(String path, ShellEntry entry) {
    _byPath[path] = entry;
    return PlatformMenuItem(
      label: ShellMenuBar.labelOf(entry),
      shortcut: entry.activator(apple: true),
      onSelected: entry.run == null ? null : () => _pick(path),
    );
  }

  /// Lines between two dividers are one group: the system draws the line.
  List<PlatformMenuItem> _groups(String path, List<ShellNode> nodes) {
    final groups = <List<PlatformMenuItem>>[[]];
    for (final (i, node) in nodes.indexed) {
      switch (node) {
        case ShellDivider():
          groups.add([]);
        case ShellEntry():
          groups.last.add(_item('$path/$i', node));
        case ShellSub():
          groups.last.add(
            PlatformMenu(
              label: node.label,
              menus: [
                for (final (j, entry) in node.entries.indexed)
                  _item('$path/$i/$j', entry),
              ],
            ),
          );
      }
    }
    return [
      for (final group in groups)
        if (group.isNotEmpty) PlatformMenuItemGroup(members: group),
    ];
  }

  static PlatformMenuItem _system(PlatformProvidedMenuItemType type) =>
      PlatformProvidedMenuItem(type: type);

  List<PlatformMenuItem> _build() {
    _byPath = {};
    return [
      PlatformMenu(
        label: 'Grove',
        menus: [
          PlatformMenuItemGroup(
            members: [_system(PlatformProvidedMenuItemType.about)],
          ),
          PlatformMenuItemGroup(
            members: [_item('app/settings', settingsEntry(widget.commands))],
          ),
          PlatformMenuItemGroup(
            members: [_system(PlatformProvidedMenuItemType.servicesSubmenu)],
          ),
          PlatformMenuItemGroup(
            members: [
              _system(PlatformProvidedMenuItemType.hide),
              _system(PlatformProvidedMenuItemType.hideOtherApplications),
              _system(PlatformProvidedMenuItemType.showAllApplications),
            ],
          ),
          PlatformMenuItemGroup(
            members: [_system(PlatformProvidedMenuItemType.quit)],
          ),
        ],
      ),
      for (final menu in widget.menus)
        PlatformMenu(
          label: menu.title,
          menus: [
            ..._groups(menu.title, menu.nodes),
            if (menu.title == 'View')
              PlatformMenuItemGroup(
                members: [
                  _system(PlatformProvidedMenuItemType.toggleFullScreen),
                ],
              ),
          ],
        ),
      PlatformMenu(
        label: 'Window',
        menus: [
          PlatformMenuItemGroup(
            members: [
              _system(PlatformProvidedMenuItemType.minimizeWindow),
              _system(PlatformProvidedMenuItemType.zoomWindow),
            ],
          ),
          PlatformMenuItemGroup(
            members: [
              _system(PlatformProvidedMenuItemType.arrangeWindowsInFront),
            ],
          ),
        ],
      ),
    ];
  }

  /// Everything of the menus that the system shows.
  String _signature() {
    final settings = settingsEntry(widget.commands);
    return [
      settings.run == null,
      for (final menu in widget.menus) ...[
        menu.title,
        for (final node in menu.nodes)
          switch (node) {
            ShellDivider() => '-',
            ShellEntry() => _sign(node),
            ShellSub() => [
              node.label,
              for (final entry in node.entries) _sign(entry),
            ].join(','),
          },
      ],
    ].join('|');
  }

  static String _sign(ShellEntry entry) =>
      '${ShellMenuBar.labelOf(entry)}:${entry.run == null ? 0 : 1}'
      ':${entry.shortcut}';

  @override
  Widget build(BuildContext context) {
    if (!ShellMenuBar.isUsed) return widget.child;
    final signature = _signature();
    if (signature != _madeFor) {
      _madeFor = signature;
      _made = _build();
    } else {
      // The same lines, with the actions of now.
      _refresh();
    }
    return PlatformMenuBar(menus: _made, child: widget.child);
  }

  void _refresh() {
    void put(String path, ShellEntry entry) => _byPath[path] = entry;
    put('app/settings', settingsEntry(widget.commands));
    for (final menu in widget.menus) {
      for (final (i, node) in menu.nodes.indexed) {
        switch (node) {
          case ShellEntry():
            put('${menu.title}/$i', node);
          case ShellSub():
            for (final (j, entry) in node.entries.indexed) {
              put('${menu.title}/$i/$j', entry);
            }
          case ShellDivider():
            break;
        }
      }
    }
  }
}
