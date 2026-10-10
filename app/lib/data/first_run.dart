import 'dart:convert';

import '../core/model/day_key.dart';
import '../core/model/task.dart';
import 'repos.dart';

/// What a brand new Grove holds on first launch (PLAN §9): three lists and
/// three sample tasks for today. The flags live in the `settings` table, so
/// they travel in the export file and an import never seeds twice.
abstract final class FirstRun {
  static const doneKey = 'firstrun.done';
  static const dismissedKey = 'firstrun.welcomeDismissed';
  static const samplesKey = 'firstrun.sampleTaskIds';

  /// The titles of the three sample tasks, in the order they show.
  static const sampleTitles = [
    'Drag me onto the planner to give me a time',
    'Type [[ in a note to link a task, a note or an event',
    'Press ⌘K to find anything or run a command',
  ];

  /// Fills an empty database. Returns true when it did.
  /// A database that has any list, task, event or note is left alone, and so
  /// is one that was seeded before (the person may have emptied it on purpose).
  static bool seedIfNew(Repos r, {required DayKey today}) {
    if (r.settings.get(doneKey) != null) return false;
    final hasData =
        r.lists.all(includeArchived: true).isNotEmpty ||
        r.tasks.all().isNotEmpty ||
        r.events.all().isNotEmpty ||
        r.notes.all().isNotEmpty;
    r.settings.set(doneKey, '1');
    if (hasData) return false;

    const lists = [('Home', '🌿'), ('Work', '💼'), ('Personal', '✨')];
    for (final (i, (name, emoji)) in lists.indexed) {
      r.lists.save(ListItem(name: name, emoji: emoji, sort: i));
    }

    final ids = <String>[];
    for (final (i, title) in sampleTitles.indexed) {
      final t = TaskItem(
        title: title,
        bucket: TaskBucket.day,
        planDate: today,
        sort: i + 1,
      );
      r.tasks.save(t);
      ids.add(t.id);
    }
    r.settings.set(samplesKey, jsonEncode(ids));
    return true;
  }

  /// The welcome card shows while there are sample tasks and the person has
  /// not dismissed it.
  static bool welcomeVisible(Repos r) =>
      sampleTaskIds(r).isNotEmpty && r.settings.get(dismissedKey) == null;

  /// The ids of the sample tasks that "Remove samples" deletes.
  static List<String> sampleTaskIds(Repos r) {
    final text = r.settings.get(samplesKey);
    if (text == null) return [];
    try {
      final list = jsonDecode(text);
      if (list is! List || list.any((x) => x is! String)) return [];
      return list.cast<String>();
    } on FormatException {
      return [];
    }
  }

  /// Hides the card. The sample tasks stay.
  static void dismissWelcome(Repos r) => r.settings.set(dismissedKey, '1');

  /// Hides the card and forgets the sample ids (after "Remove samples").
  static void forgetSamples(Repos r) {
    r.settings.remove(samplesKey);
    r.settings.set(dismissedKey, '1');
  }
}
