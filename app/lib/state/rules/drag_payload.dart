/// Tasks, notes and goals are dragged as plain strings, so no custom file type is needed.
abstract final class DragPayload {
  static const taskPrefix = 'grove-task:';
  static String task(String id) => taskPrefix + id;

  static const notePrefix = 'grove-note:';
  static String note(String id) => notePrefix + id;

  /// The id in a dragged note, or null when the text is something else.
  static String? noteId(String raw) =>
      raw.startsWith(notePrefix) ? raw.substring(notePrefix.length) : null;

  static const goalPrefix = 'grove-goal:';
  static String goal(String id) => goalPrefix + id;

  /// The id in a dragged goal, or null when the text is something else (or has no id).
  static String? goalId(String raw) =>
      raw.startsWith(goalPrefix) && raw.length > goalPrefix.length
      ? raw.substring(goalPrefix.length)
      : null;
}
