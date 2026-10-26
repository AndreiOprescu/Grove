import '../core/model/day_key.dart';
import '../core/model/notebook.dart';
import 'database.dart';

/// Notebooks and their sections (migration 14).
class NotebookRepo {
  NotebookRepo(this.db);

  final Database db;

  static const _cols = [
    'id',
    'name',
    'color',
    'sort_order',
    'created_at',
    'updated_at',
  ];
  static const _sectionCols = [
    'id',
    'notebook_id',
    'name',
    'sort_order',
    'created_at',
    'updated_at',
  ];
  static final _select = 'SELECT ${_cols.join(',')} FROM notebooks';
  static final _selectSection =
      'SELECT ${_sectionCols.join(',')} FROM notebook_sections';
  static const _order = 'ORDER BY sort_order, name COLLATE NOCASE, rowid';
  static final _upsert = _upsertOf('notebooks', _cols);
  static final _upsertSection = _upsertOf('notebook_sections', _sectionCols);

  static String _upsertOf(String table, List<String> cols) {
    final marks = List.filled(cols.length, '?').join(',');
    final sets = cols.skip(1).map((c) => '$c=excluded.$c').join(',');
    return 'INSERT INTO $table (${cols.join(',')}) VALUES ($marks) '
        'ON CONFLICT(${cols.first}) DO UPDATE SET $sets';
  }

  static Notebook _map(Row r) => Notebook(
    id: r.text(0),
    name: r.text(1),
    color: r.optText(2),
    sortOrder: r.asDouble(3),
    createdAt: r.text(4),
    updatedAt: r.text(5),
  );

  static NotebookSection _mapSection(Row r) => NotebookSection(
    id: r.text(0),
    notebookId: r.text(1),
    name: r.text(2),
    sortOrder: r.asDouble(3),
    createdAt: r.text(4),
    updatedAt: r.text(5),
  );

  // Notebooks

  /// In sidebar order: `sort_order`, then the name.
  List<Notebook> all() => db.query('$_select $_order', const [], _map);

  Notebook? get(String id) =>
      db.query('$_select WHERE id = ?', [id], _map).firstOrNull;

  /// Insert or update. `touch: false` keeps the edit time.
  void save(Notebook notebook, {bool touch = true}) {
    final b = touch ? notebook.copyWith(updatedAt: Stamp.now()) : notebook;
    db.execute(_upsert, [
      b.id,
      b.name,
      b.color,
      b.sortOrder,
      b.createdAt,
      b.updatedAt,
    ]);
  }

  /// Deletes the notebook and its sections. Its notes stay, in no notebook
  /// and no section.
  void delete(String id) {
    db.transaction(() {
      db.execute(
        'UPDATE notes SET notebook_id = NULL, section_id = NULL '
        'WHERE notebook_id = ?',
        [id],
      );
      db.execute('DELETE FROM notebook_sections WHERE notebook_id = ?', [id]);
      db.execute('DELETE FROM notebooks WHERE id = ?', [id]);
    });
  }

  /// Gives notebook `ids[i]` the order `i + 1`. Other notebooks keep theirs.
  void reorder(List<String> ids) => _renumber('notebooks', ids);

  // Sections

  /// The sections of one notebook, in order.
  List<NotebookSection> sections(String notebookId) => db.query(
    '$_selectSection WHERE notebook_id = ? $_order',
    [notebookId],
    _mapSection,
  );

  /// Every section of every notebook, in order.
  List<NotebookSection> allSections() =>
      db.query('$_selectSection $_order', const [], _mapSection);

  NotebookSection? section(String id) =>
      db.query('$_selectSection WHERE id = ?', [id], _mapSection).firstOrNull;

  /// Insert or update. Throws when the notebook does not exist (foreign key).
  void saveSection(NotebookSection section, {bool touch = true}) {
    final s = touch ? section.copyWith(updatedAt: Stamp.now()) : section;
    db.execute(_upsertSection, [
      s.id,
      s.notebookId,
      s.name,
      s.sortOrder,
      s.createdAt,
      s.updatedAt,
    ]);
  }

  /// Deletes the section. Its notes stay in the notebook, in no section.
  void deleteSection(String id) {
    db.transaction(() {
      db.execute('UPDATE notes SET section_id = NULL WHERE section_id = ?', [
        id,
      ]);
      db.execute('DELETE FROM notebook_sections WHERE id = ?', [id]);
    });
  }

  /// Gives section `ids[i]` the order `i + 1`.
  void reorderSections(List<String> ids) => _renumber('notebook_sections', ids);

  void _renumber(String table, List<String> ids) {
    if (ids.isEmpty) return;
    final now = Stamp.now();
    db.transaction(() {
      for (var i = 0; i < ids.length; i++) {
        db.execute(
          'UPDATE $table SET sort_order = ?, updated_at = ? WHERE id = ?',
          [i + 1, now, ids[i]],
        );
      }
    });
  }
}
