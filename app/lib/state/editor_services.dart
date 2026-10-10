import 'dart:typed_data';

import '../core/model/link.dart';

/// One row in the `[[` list.
class MentionSuggestion {
  const MentionSuggestion({
    required this.ref,
    required this.title,
    required this.kind,
  });

  final ItemRef ref;
  final String title;
  final String kind;

  String get id => ref.id;

  @override
  bool operator ==(Object other) =>
      other is MentionSuggestion &&
      other.ref == ref &&
      other.title == title &&
      other.kind == kind;

  @override
  int get hashCode => Object.hash(ref, title, kind);

  @override
  String toString() => 'MentionSuggestion($kind, $title)';
}

/// An image the editor wants to keep. The screen checks and shrinks it first.
typedef ImageToStore = ({String mime, Uint8List data, int width, int height});

/// What the editor needs from the rest of the app. Closures keep the editor
/// free of the store, so it can be shown with any data.
class EditorServices {
  EditorServices({
    this.suggest = _noSuggestions,
    this.isLive = _alwaysLive,
    this.title = _noTitle,
    this.open = _ignoreOpen,
    this.storeImage = _noStore,
    this.loadImage = _noImage,
    this.notify = _ignoreMessage,
    this.makeTask,
    this.addToPlanner,
  });

  /// Items that match what was typed after `[[`.
  final List<MentionSuggestion> Function(String query) suggest;

  /// False when the item a mention points at is gone.
  final bool Function(String id) isLive;

  /// The current title of an item.
  final String? Function(String id) title;

  /// Called when a mention is clicked.
  final void Function(String? id, String title) open;

  /// Stores an image and returns its id. Null when it cannot be stored.
  final String? Function(ImageToStore image) storeImage;
  final Uint8List? Function(String id) loadImage;
  final void Function(String message) notify;

  /// Makes a task from these words and returns its id. Null when this field
  /// cannot make tasks (only notes can).
  final String? Function(String words)? makeTask;

  /// Sends a line with an `@date` to the planner. Returns the text the line
  /// becomes. Null when it cannot go (only notes can).
  final String? Function(String line)? addToPlanner;

  static List<MentionSuggestion> _noSuggestions(String _) => const [];
  static bool _alwaysLive(String _) => true;
  static String? _noTitle(String _) => null;
  static void _ignoreOpen(String? _, String _) {}
  static String? _noStore(ImageToStore _) => null;
  static Uint8List? _noImage(String _) => null;
  static void _ignoreMessage(String _) {}
}
