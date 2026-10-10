/// How a day felt. It is saved in `notes.mood` of the daily note as 1, 2 or 3.
enum Mood {
  rain(1, 'cloud.rain', 'Rough day'),
  cloud(2, 'cloud.sun', 'Okay day'),
  sun(3, 'sun.max', 'Good day');

  const Mood(this.value, this.symbol, this.label);

  /// The number that is stored.
  final int value;

  /// The name of the picture (an SF Symbol name on the Mac).
  final String symbol;
  final String label;

  static Mood? fromValue(int? value) {
    for (final m in values) {
      if (m.value == value) return m;
    }
    return null;
  }
}
