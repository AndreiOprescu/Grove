import '../model/day_key.dart';
import 'at_date.dart';

/// The things the command palette can do besides open an item.
enum PaletteCommandId {
  newTask,
  newNote,
  todayNote,
  goToday,
  goToDate,
  planMyDay,
  showPlanner,
  showCalendar,
  showNotes,
  showGarden,
  toggleTheme,
  toggleMotion,
}

class PaletteCommand {
  const PaletteCommand({
    required this.id,
    required this.title,
    required this.symbol,
    this.keywords = const [],
    this.shortcut,
  });

  final PaletteCommandId id;
  final String title;

  /// Extra words that find the command. The title words always count.
  final List<String> keywords;

  /// The Mac shortcut, like `⌘N`. The UI shows Ctrl on other systems.
  final String? shortcut;

  /// The icon name, as the Mac app's SF Symbol. The UI maps it to its own icon.
  final String symbol;
}

/// What the palette box means.
class PaletteParsed {
  const PaletteParsed({required this.commandsOnly, required this.text});

  /// The text started with `>`. Only commands show.
  final bool commandsOnly;
  final String text;

  @override
  bool operator ==(Object other) =>
      other is PaletteParsed &&
      other.commandsOnly == commandsOnly &&
      other.text == text;

  @override
  int get hashCode => Object.hash(commandsOnly, text);

  @override
  String toString() => 'PaletteParsed($commandsOnly, "$text")';
}

/// The text rules of the command palette (PLAN §5.5 item 11): what the box means, which
/// commands match, and whether the text is a day.
abstract final class PaletteRules {
  static PaletteParsed parse(String raw) {
    final trimmed = _trimSpaces(raw);
    if (!trimmed.startsWith('>')) {
      return PaletteParsed(commandsOnly: false, text: trimmed);
    }
    return PaletteParsed(
      commandsOnly: true,
      text: _trimSpaces(trimmed.substring(1)),
    );
  }

  // Commands.

  /// In the order the palette lists them.
  static const commands = [
    PaletteCommand(
      id: PaletteCommandId.newTask,
      title: 'New task',
      keywords: ['add', 'create'],
      shortcut: '⌘N',
      symbol: 'plus.circle',
    ),
    PaletteCommand(
      id: PaletteCommandId.newNote,
      title: 'New note',
      keywords: ['add', 'create', 'write'],
      shortcut: '⌥⌘N',
      symbol: 'square.and.pencil',
    ),
    PaletteCommand(
      id: PaletteCommandId.todayNote,
      title: "Today's note",
      keywords: ['daily', 'journal', 'diary'],
      symbol: 'note.text',
    ),
    PaletteCommand(
      id: PaletteCommandId.goToday,
      title: 'Go to today',
      keywords: ['now'],
      shortcut: '⌘T',
      symbol: 'sun.max',
    ),
    PaletteCommand(
      id: PaletteCommandId.goToDate,
      title: 'Go to date…',
      keywords: ['day', 'jump', 'calendar'],
      symbol: 'calendar',
    ),
    PaletteCommand(
      id: PaletteCommandId.planMyDay,
      title: 'Plan my day',
      keywords: ['fit', 'schedule', 'auto'],
      symbol: 'wand.and.stars',
    ),
    PaletteCommand(
      id: PaletteCommandId.showPlanner,
      title: 'Open planner',
      keywords: ['calendar', 'schedule', 'day'],
      shortcut: '⌘1',
      symbol: 'calendar.day.timeline.left',
    ),
    PaletteCommand(
      id: PaletteCommandId.showCalendar,
      title: 'Open calendar',
      keywords: ['month', 'schedule'],
      shortcut: '⌘3',
      symbol: 'calendar',
    ),
    PaletteCommand(
      id: PaletteCommandId.showNotes,
      title: 'Open notes',
      keywords: ['notebook'],
      shortcut: '⌘4',
      symbol: 'note.text',
    ),
    PaletteCommand(
      id: PaletteCommandId.showGarden,
      title: 'Open garden',
      keywords: ['grow', 'tree', 'leaf'],
      shortcut: '⌘5',
      symbol: 'leaf',
    ),
    PaletteCommand(
      id: PaletteCommandId.toggleTheme,
      title: 'Toggle theme',
      keywords: [
        'theme',
        'dark',
        'light',
        'colour',
        'color',
        'appearance',
        'look',
        'switch',
      ],
      symbol: 'paintpalette',
    ),
    PaletteCommand(
      id: PaletteCommandId.toggleMotion,
      title: 'Toggle motion',
      keywords: ['motion', 'animation', 'animate', 'reduce', 'calm'],
      symbol: 'wind',
    ),
  ];

  /// Every word typed must start a word of the title or of a keyword. Empty text matches all.
  static List<PaletteCommand> commandsMatching(String text) {
    final typed = _words(text);
    if (typed.isEmpty) return commands;
    return commands.where((c) {
      final pool = [..._words(c.title), ...c.keywords.expand(_words)];
      return typed.every((w) => pool.any((p) => p.startsWith(w)));
    }).toList();
  }

  static final _notWord = RegExp(r'[^\p{L}\p{M}\p{N}]+', unicode: true);

  static List<String> _words(String s) =>
      s.toLowerCase().split(_notWord).where((w) => w.isNotEmpty).toList();

  // Dates.

  static const _goToPrefixes = ['go to ', 'goto ', 'go '];

  /// "go to fri" gives "fri". Other text stays as it is.
  static String _withoutGoTo(String text) {
    final t = _trimSpaces(text);
    final lower = t.toLowerCase();
    for (final p in _goToPrefixes) {
      if (lower.startsWith(p)) return _trimSpaces(t.substring(p.length));
    }
    return t;
  }

  /// The day the whole text names, like `fri`, `tomorrow` or `go to oct 9`. A time after the
  /// day is ignored. Null when other words come with it: that text is a search.
  static DayKey? date(String text, {DayKey? today}) {
    final rest = _withoutGoTo(text);
    if (rest.isEmpty) return null;
    final line = '@$rest';
    final hit = AtDateParser.find(line, today: today ?? DayKey.today());
    if (hit == null || hit.day == null || hit.range.end != line.length) {
      return null;
    }
    return hit.day;
  }

  /// The text is "go to" and nothing after it: the palette asks which day.
  static bool asksForDay(String text) {
    final lower = _trimSpaces(text).toLowerCase();
    return lower == 'go to' || lower == 'goto';
  }

  static const _weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  /// "Go to today", "Go to tomorrow" or "Go to Friday".
  static String dayTitle(DayKey day, {DayKey? today}) {
    final now = today ?? DayKey.today();
    if (day == now) return 'Go to today';
    if (day == now.adding(days: 1)) return 'Go to tomorrow';
    return 'Go to ${_weekdays[day.weekdayIndex - 1]}';
  }

  /// "Fri 9 Oct"
  static String dayDetail(DayKey day) => AtDatePlanner.whenLabel(day);

  /// Trims spaces and tabs, like `trimmingCharacters(in: .whitespaces)`.
  static String _trimSpaces(String s) {
    var a = 0, b = s.length;
    while (a < b && isSpaceOrTab(s.codeUnitAt(a))) {
      a += 1;
    }
    while (b > a && isSpaceOrTab(s.codeUnitAt(b - 1))) {
      b -= 1;
    }
    return s.substring(a, b);
  }
}
