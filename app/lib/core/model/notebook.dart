import 'day_key.dart';
import 'ids.dart';

/// A notebook: a named group of notes. A note is in one notebook or in none
/// (`Note.notebookId`).
class Notebook {
  Notebook({
    String? id,
    required this.name,
    this.color,
    this.sortOrder = 0,
    String? createdAt,
    String? updatedAt,
  }) : id = id ?? newId(),
       createdAt = createdAt ?? updatedAt ?? Stamp.now(),
       updatedAt = updatedAt ?? createdAt ?? Stamp.now();

  final String id;
  final String name;

  /// The name of a colour, or null for the plain look.
  final String? color;

  /// The place in the sidebar. Lower comes first.
  final double sortOrder;
  final String createdAt;
  final String updatedAt;

  Notebook copyWith({
    String? id,
    String? name,
    Object? color = keep,
    double? sortOrder,
    String? createdAt,
    String? updatedAt,
  }) => Notebook(
    id: id ?? this.id,
    name: name ?? this.name,
    color: identical(color, keep) ? this.color : color as String?,
    sortOrder: sortOrder ?? this.sortOrder,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  List<Object?> get _props => [
    id,
    name,
    color,
    sortOrder,
    createdAt,
    updatedAt,
  ];

  @override
  bool operator ==(Object other) =>
      other is Notebook && sameList(other._props, _props);

  @override
  int get hashCode => Object.hashAll(_props);

  @override
  String toString() => 'Notebook($name)';
}

/// A section inside a notebook. A note of the notebook is in one section or
/// in none (`Note.sectionId`).
class NotebookSection {
  NotebookSection({
    String? id,
    required this.notebookId,
    required this.name,
    this.sortOrder = 0,
    String? createdAt,
    String? updatedAt,
  }) : id = id ?? newId(),
       createdAt = createdAt ?? updatedAt ?? Stamp.now(),
       updatedAt = updatedAt ?? createdAt ?? Stamp.now();

  final String id;

  /// The notebook that this section is in.
  final String notebookId;
  final String name;

  /// The place in the notebook. Lower comes first.
  final double sortOrder;
  final String createdAt;
  final String updatedAt;

  NotebookSection copyWith({
    String? id,
    String? notebookId,
    String? name,
    double? sortOrder,
    String? createdAt,
    String? updatedAt,
  }) => NotebookSection(
    id: id ?? this.id,
    notebookId: notebookId ?? this.notebookId,
    name: name ?? this.name,
    sortOrder: sortOrder ?? this.sortOrder,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  List<Object?> get _props => [
    id,
    notebookId,
    name,
    sortOrder,
    createdAt,
    updatedAt,
  ];

  @override
  bool operator ==(Object other) =>
      other is NotebookSection && sameList(other._props, _props);

  @override
  int get hashCode => Object.hashAll(_props);

  @override
  String toString() => 'NotebookSection($name)';
}
