import 'dart:typed_data';

import '../core/model/day_key.dart';
import '../core/model/ids.dart';
import 'database.dart';

/// An image stored in the database.
class StoredImage {
  const StoredImage({
    required this.id,
    required this.mime,
    required this.data,
    required this.width,
    required this.height,
    required this.createdAt,
  });

  final String id;
  final String mime;
  final Uint8List data;
  final int width;
  final int height;
  final String createdAt;

  @override
  bool operator ==(Object other) =>
      other is StoredImage &&
      other.id == id &&
      other.mime == mime &&
      sameList(other.data, data) &&
      other.width == width &&
      other.height == height &&
      other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(id, mime, data.length, width, height);
}

/// Images that task bodies, notes and event notes point at with `![alt](grove-image:ID)`.
/// They live in the database so the daily backup and the export carry them.
class AttachmentRepo {
  AttachmentRepo(this.db);

  final Database db;

  /// Stores an image that is already checked and shrunk. The UI layer does that
  /// part, because it needs the platform's image tools.
  StoredImage add({
    required String mime,
    required Uint8List data,
    required int width,
    required int height,
  }) {
    final image = StoredImage(
      id: newId(),
      mime: mime,
      data: data,
      width: width,
      height: height,
      createdAt: Stamp.now(),
    );
    db.execute(
      'INSERT INTO attachments (id, mime, data, width, height, created_at) '
      'VALUES (?, ?, ?, ?, ?, ?)',
      [image.id, mime, data, width, height, image.createdAt],
    );
    return image;
  }

  StoredImage? get(String id) => db.queryOne(
    'SELECT id, mime, data, width, height, created_at FROM attachments '
    'WHERE id = ?',
    [id],
    (r) => StoredImage(
      id: r.text(0),
      mime: r.text(1),
      data: r.blob(2),
      width: r.asInt(3),
      height: r.asInt(4),
      createdAt: r.text(5),
    ),
  );

  void delete(String id) =>
      db.execute('DELETE FROM attachments WHERE id = ?', [id]);

  int count() =>
      db.queryOne('SELECT COUNT(*) FROM attachments', const [], (r) {
        return r.asInt(0);
      }) ??
      0;

  /// Deletes images that no task body, note or event note uses any more.
  /// An image must be at least [olderThanMinutes] old, so a picture pasted a
  /// moment ago (text not saved yet) or brought back by undo is never lost.
  /// Returns how many were deleted.
  int sweepOrphans({int olderThanMinutes = 24 * 60, DateTime? now}) {
    final cutoff = Stamp.fromDate(
      (now ?? DateTime.now()).subtract(Duration(minutes: olderThanMinutes)),
    );
    final before = count();
    db.execute(
      'DELETE FROM attachments WHERE created_at < ? '
      "AND NOT EXISTS (SELECT 1 FROM tasks WHERE instr(notes, 'grove-image:' || attachments.id) > 0) "
      "AND NOT EXISTS (SELECT 1 FROM notes WHERE instr(body, 'grove-image:' || attachments.id) > 0) "
      "AND NOT EXISTS (SELECT 1 FROM events WHERE instr(notes, 'grove-image:' || attachments.id) > 0)",
      [cutoff],
    );
    return before - count();
  }
}
