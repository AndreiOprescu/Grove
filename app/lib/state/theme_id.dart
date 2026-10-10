/// The four looks of the app. Saved as `appearance.theme`.
enum ThemeId {
  grove,
  minimal,
  futuristic,
  vintage;

  static const ThemeId initial = ThemeId.grove;

  String get id => name;

  /// The theme after this one. The last wraps around to the first.
  ThemeId get next => values[(index + 1) % values.length];

  /// The theme named by saved text. Unknown or missing text is [initial].
  static ThemeId fromSaved(String? saved) {
    for (final t in values) {
      if (t.name == saved) return t;
    }
    return initial;
  }
}

/// Light or dark, chosen apart from the theme. System follows the device.
/// Saved as `appearance.mode`.
enum AppearanceMode {
  system('System'),
  light('Light'),
  dark('Dark');

  const AppearanceMode(this.label);

  final String label;

  String get id => name;

  /// The mode named by saved text. Unknown or missing text is [system].
  static AppearanceMode fromSaved(String? saved) {
    for (final m in values) {
      if (m.name == saved) return m;
    }
    return system;
  }
}
