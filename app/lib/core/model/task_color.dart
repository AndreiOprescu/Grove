/// The colour a task can have: one of eight names, or "" for none.
/// The app turns each name into a real colour. Names are stored, so a theme
/// change never breaks them.
abstract final class TaskColor {
  static const names = [
    'red',
    'orange',
    'yellow',
    'green',
    'teal',
    'blue',
    'purple',
    'pink',
  ];

  static bool isValid(String name) => name.isEmpty || names.contains(name);
}
