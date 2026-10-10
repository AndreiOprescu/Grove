import '../core/model/link.dart';
import 'database.dart';

class SearchHit {
  const SearchHit({
    required this.ref,
    required this.title,
    required this.snippet,
  });

  final ItemRef ref;
  final String title;
  final String snippet;

  @override
  bool operator ==(Object other) =>
      other is SearchHit &&
      other.ref == ref &&
      other.title == title &&
      other.snippet == snippet;

  @override
  int get hashCode => Object.hash(ref, title, snippet);
}

/// Full-text search over tasks, events and notes (SQLite FTS5).
class SearchIndex {
  SearchIndex(this.db);

  final Database db;

  /// Letters, digits and accent marks make a word. Everything else splits words.
  static final _splitter = RegExp(r'[^\p{L}\p{N}\p{M}]+', unicode: true);

  void upsert(ItemType type, String id, String title, String body) {
    remove(type, id);
    db.execute(
      'INSERT INTO search (item_type, item_id, title, body) VALUES (?, ?, ?, ?)',
      [type.name, id, title, body],
    );
  }

  void remove(ItemType type, String id) => db.execute(
    'DELETE FROM search WHERE item_type = ? AND item_id = ?',
    [type.name, id],
  );

  /// Every word is a prefix match; all words must match. An empty query returns nothing.
  List<SearchHit> search(String query, {Set<ItemType>? types, int limit = 30}) {
    final tokens = query.split(_splitter).where((t) => t.isNotEmpty).toList();
    if (tokens.isEmpty) return const [];
    final match = tokens.map((t) => '"$t"*').join(' ');
    final names = ItemType.values.asNameMap();
    final rows = db.query(
      "SELECT item_type, item_id, title, snippet(search, 3, '', '', '…', 10) "
      'FROM search WHERE search MATCH ? ORDER BY rank LIMIT ?',
      [match, limit * 3],
      (r) {
        final type = names[r.text(0)];
        return type == null
            ? null
            : SearchHit(
                ref: ItemRef(type, r.text(1)),
                title: r.text(2),
                snippet: r.text(3),
              );
      },
    );
    return rows
        .whereType<SearchHit>()
        .where((h) => types?.contains(h.ref.type) ?? true)
        .take(limit)
        .toList();
  }
}
