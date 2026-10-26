import 'day_key.dart';
import 'ids.dart';

enum NoteKind { note, daily, weekly }

class Note {
  Note({
    String? id,
    required this.title,
    this.body = '',
    this.kind = NoteKind.note,
    this.date,
    this.pinned = false,
    this.mood,
    this.notebookId,
    this.sectionId,
    this.sortOrder = 0,
    this.archivedAt,
    String? createdAt,
    String? updatedAt,
  }) : id = id ?? newId(),
       createdAt = createdAt ?? updatedAt ?? Stamp.now(),
       updatedAt = updatedAt ?? createdAt ?? Stamp.now();

  final String id;
  final String title;
  final String body;
  final NoteKind kind;

  /// Daily: the day. Weekly: the Monday.
  final DayKey? date;
  final bool pinned;

  /// Daily only, 1…3.
  final int? mood;

  /// The notebook the note is in, or null for none.
  final String? notebookId;

  /// The section of the notebook the note is in, or null for none.
  final String? sectionId;

  /// The place of the note in its notebook. Lower comes first.
  final double sortOrder;

  /// When the note was archived, or null. An archived note shows only in the
  /// archive.
  final String? archivedAt;
  final String createdAt;
  final String updatedAt;

  bool get archived => archivedAt != null;

  Note copyWith({
    String? id,
    String? title,
    String? body,
    NoteKind? kind,
    Object? date = keep,
    bool? pinned,
    Object? mood = keep,
    Object? notebookId = keep,
    Object? sectionId = keep,
    double? sortOrder,
    Object? archivedAt = keep,
    String? createdAt,
    String? updatedAt,
  }) => Note(
    id: id ?? this.id,
    title: title ?? this.title,
    body: body ?? this.body,
    kind: kind ?? this.kind,
    date: identical(date, keep) ? this.date : date as DayKey?,
    pinned: pinned ?? this.pinned,
    mood: identical(mood, keep) ? this.mood : mood as int?,
    notebookId: identical(notebookId, keep)
        ? this.notebookId
        : notebookId as String?,
    sectionId: identical(sectionId, keep)
        ? this.sectionId
        : sectionId as String?,
    sortOrder: sortOrder ?? this.sortOrder,
    archivedAt: identical(archivedAt, keep)
        ? this.archivedAt
        : archivedAt as String?,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  List<Object?> get _props => [
    id,
    title,
    body,
    kind,
    date,
    pinned,
    mood,
    notebookId,
    sectionId,
    sortOrder,
    archivedAt,
    createdAt,
    updatedAt,
  ];

  @override
  bool operator ==(Object other) =>
      other is Note && sameList(other._props, _props);

  @override
  int get hashCode => Object.hashAll(_props);
}
