import '../screen.dart';

/// The panels that can open on the left of the Today and Planner screens. One
/// at a time. The choice is saved as text in `shell.leftPane`; empty text
/// means closed.
enum LeftPane {
  notes('Notes', 'note.text'),
  tasks('Tasks', 'checklist'),
  goals('Goals', 'target');

  const LeftPane(this.title, this.icon);

  final String title;

  /// The SF Symbol name on the Mac. The screens map it to an icon.
  final String icon;

  String get id => name;

  static const storageKey = 'shell.leftPane';

  /// How wide the panel is on the Planner screen.
  static const plannerWidth = 320.0;

  /// The tooltip of the button: it names the action the next click does.
  String tooltip({required bool isOpen}) =>
      isOpen ? 'Hide ${title.toLowerCase()}' : 'Show ${title.toLowerCase()}';

  String get help => tooltip(isOpen: false);

  /// The panel after a click on [tapped]: the same one closes, any other one
  /// replaces the open one.
  static LeftPane? toggled({
    required LeftPane? current,
    required LeftPane tapped,
  }) => current == tapped ? null : tapped;

  /// The panel for saved text. Null for empty or unknown text.
  static LeftPane? fromSaved(String? saved) {
    for (final p in values) {
      if (p.name == saved) return p;
    }
    return null;
  }

  static String savedText(LeftPane? pane) => pane?.name ?? '';

  /// The panels only show on the Today and Planner screens.
  static bool isAvailable(Screen screen) =>
      screen == Screen.today || screen == Screen.planner;
}
