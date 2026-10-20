import '../core/model/link.dart';
import '../core/parsing/note_parser.dart';
import '../core/parsing/reference_parser.dart';
import 'database.dart';
import 'repos.dart';
import 'search_index.dart';

/// What a mention points at.
class RefTarget {
  const RefTarget(this.ref, this.title);

  final ItemRef ref;
  final String title;

  @override
  bool operator ==(Object other) =>
      other is RefTarget && other.ref == ref && other.title == title;

  @override
  int get hashCode => Object.hash(ref, title);
}

/// Turns `[[mentions]]` in a body into real links between tasks, notes and events.
class ReferenceIndexer {
  ReferenceIndexer({
    required this.db,
    required this.tasks,
    required this.notes,
    required this.events,
    required this.links,
    required this.search,
  });

  final Database db;
  final TaskRepo tasks;
  final NoteRepo notes;
  final EventRepo events;
  final LinkRepo links;
  final SearchIndex search;

  static final _types = ItemType.values.asNameMap();

  /// Finds what a mention points at.
  /// With an id, only that id counts: a deleted target stays unresolved and
  /// never moves to another item. Without an id, the exact title (any letter
  /// case) is used. A note wins over a task, a task over an event.
  RefTarget? resolve(Mention mention) =>
      resolveTitle(mention.title, id: mention.id);

  RefTarget? resolveTitle(String title, {String? id}) {
    if (id != null) return _target(id);
    if (notes.byTitle(title) case final n?) {
      return RefTarget(ItemRef(ItemType.note, n.id), n.title);
    }
    if (tasks.byTitle(title) case final t?) {
      return RefTarget(ItemRef(ItemType.task, t.id), t.title);
    }
    if (events.byTitle(title) case final e?) {
      return RefTarget(ItemRef(ItemType.event, e.id), e.title);
    }
    return null;
  }

  String? titleOf(ItemRef ref) {
    final t = _target(ref.id);
    return t != null && t.ref == ref ? t.title : null;
  }

  RefTarget? _target(String id) => db.queryOne<RefTarget?>(
    "SELECT 'task', id, title FROM tasks WHERE id = ? "
    "UNION ALL SELECT 'note', id, title FROM notes WHERE id = ? "
    "UNION ALL SELECT 'event', id, title FROM events WHERE id = ?",
    [id, id, id],
    (r) {
      final type = _types[r.text(0)];
      return type == null
          ? null
          : RefTarget(ItemRef(type, r.text(1)), r.text(2));
    },
  );

  /// The text with every resolvable mention written as `[[Current title|ID]]`,
  /// plus what the mentions point at. Mentions that cannot be resolved stay
  /// exactly as typed.
  ({String text, List<ItemRef> targets}) canonicalize(String text) {
    var out = text;
    final found = <ItemRef>[];
    for (final m in ReferenceParser.mentions(text).reversed) {
      final t = resolve(m);
      if (t == null) continue;
      out = out.replaceRange(
        m.start,
        m.end,
        ReferenceParser.mention(title: t.title, id: t.ref.id),
      );
      found.add(t.ref);
    }
    final seen = <ItemRef>{};
    return (text: out, targets: found.reversed.where(seen.add).toList());
  }

  /// Call after every save of a body. Replaces the item's parsed links and
  /// returns the canonical text, which the caller should store. Manual links
  /// are kept.
  String reindex(ItemRef src, String text) {
    final result = canonicalize(text);
    links.replaceParsed(src, result.targets);
    return result.text;
  }

  /// Rebuilds the links that other bodies make to [ref]. Call after [ref] was
  /// brought back (undo of a delete), because deleting an item also removes the
  /// link rows that point at it.
  void rebuildIncoming(ItemRef ref) {
    final args = ['|${ref.id}]]'];
    final found = [
      ...db.query(
        'SELECT id, notes FROM tasks WHERE instr(notes, ?) > 0',
        args,
        (r) => (ItemRef(ItemType.task, r.text(0)), r.text(1)),
      ),
      ...db.query(
        'SELECT id, body FROM notes WHERE instr(body, ?) > 0',
        args,
        (r) => (ItemRef(ItemType.note, r.text(0)), r.text(1)),
      ),
      ...db.query(
        'SELECT id, notes FROM events WHERE instr(notes, ?) > 0',
        args,
        (r) => (ItemRef(ItemType.event, r.text(0)), r.text(1)),
      ),
    ];
    for (final (src, text) in found) {
      reindex(src, text);
    }
  }

  /// Call after an item was renamed and saved. Rewrites the title inside every
  /// body that mentions it. The linking items keep their "last edited" time, so
  /// a rename does not reshuffle the notes list.
  void renamed(ItemRef ref, String newTitle) {
    String rewrite(String body) =>
        ReferenceParser.rewriting(body, id: ref.id, title: newTitle);
    db.transaction(() {
      for (final src in links.backlinks(ref)) {
        switch (src.type) {
          case ItemType.task:
            final t = tasks.get(src.id);
            if (t == null) continue;
            final body = rewrite(t.notes);
            if (body == t.notes) continue;
            db.execute('UPDATE tasks SET notes = ? WHERE id = ?', [body, t.id]);
            search.upsert(
              ItemType.task,
              t.id,
              t.title,
              TaskRepo.searchBody(t.copyWith(notes: body)),
            );
          case ItemType.note:
            final n = notes.get(src.id);
            if (n == null) continue;
            final body = rewrite(n.body);
            if (body == n.body) continue;
            db.execute('UPDATE notes SET body = ? WHERE id = ?', [body, n.id]);
            search.upsert(
              ItemType.note,
              n.id,
              n.title,
              ReferenceParser.searchText(NoteParser.withoutMarkers(body)),
            );
          case ItemType.event:
            final e = events.get(src.id);
            if (e == null) continue;
            final body = rewrite(e.notes);
            if (body == e.notes) continue;
            db.execute('UPDATE events SET notes = ? WHERE id = ?', [
              body,
              e.id,
            ]);
            search.upsert(
              ItemType.event,
              e.id,
              e.title,
              EventRepo.searchBody(e.copyWith(notes: body)),
            );
        }
      }
    });
  }
}
