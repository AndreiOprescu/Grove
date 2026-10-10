// Port of Sources/Grove/Planner/StickyRules.swift: sizes and looks of the
// sticky notes above the grid.
import 'dart:convert';
import 'dart:math';

abstract final class StickyRules {
  /// The strip never grows taller than this. More notes scroll.
  static const maxHeight = 150.0;

  /// The strip when it is folded, or when no task waits.
  static const foldedHeight = 26.0;

  static const noteMinWidth = 110.0;
  static const spacing = 6.0;

  /// The height of the open strip for notes that need `content` points.
  static double stripHeight(double content) =>
      content <= 0 ? foldedHeight : min(content, maxHeight);

  /// How many notes sit side by side in a day that is `cellWidth` wide.
  static int columns(double cellWidth) =>
      max(1, ((cellWidth - spacing) / (noteMinWidth + spacing)).truncate());

  /// 0, 1 or 2: which of the three accent colours a note gets. The same id
  /// always gives the same colour.
  static int colorIndex(String id) => stableHash(id) % 3;

  /// A small turn in degrees, from -1.5 to 1.5. The same id always gives
  /// the same turn.
  static double tilt(String id) => ((stableHash(id) ~/ 3) % 7 - 3) * 0.5;

  /// FNV-1a, 32 bits, over the UTF-8 bytes. Dart's own `hashCode` can
  /// change from one run to the next.
  static int stableHash(String s) {
    var hash = 2166136261;
    for (final byte in utf8.encode(s)) {
      hash ^= byte;
      hash = (hash * 16777619) & 0xFFFFFFFF;
    }
    return hash;
  }
}
