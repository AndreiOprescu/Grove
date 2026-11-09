import 'day_key.dart';
import 'ids.dart';

/// Where a wait on a square stands.
enum WaitPhase { none, running, over }

/// A wait at one moment: its phase and the words for the map.
class SquareWait {
  const SquareWait(this.phase, this.label);

  static const none = SquareWait(WaitPhase.none, '');

  final WaitPhase phase;

  /// "3 days left", "4 h left", "Wait is over" or "1 day over".
  final String label;
}

/// One thing that must happen on a project's goal map. The squares it needs
/// first are joined to it by [SquareLink]s (ADR 0008).
class GoalSquare {
  GoalSquare({
    String? id,
    required this.goalId,
    required this.title,
    this.doneAt,
    this.waitMinutes,
    this.waitStartedAt,
    this.sort = 0,
    this.lengthMinutes,
    String? createdAt,
    String? updatedAt,
  }) : id = id ?? newId(),
       createdAt = createdAt ?? updatedAt ?? Stamp.now(),
       updatedAt = updatedAt ?? createdAt ?? Stamp.now();

  /// The id of a project's root square. It is the same on every device, so
  /// two devices that make the same project reach the same row.
  static String rootIdOf(String goalId) => 'root:$goalId';

  /// The id of the square made from a goal subtask, for the same reason.
  static String idFromSubtask(String subtaskId) => 'sq:$subtaskId';

  final String id;
  final String goalId;
  final String title;

  /// When it was ticked, or null for an open square.
  final String? doneAt;

  /// How long the wait is, or null for a square with no wait.
  final int? waitMinutes;

  /// When the user pressed "Start waiting", or null.
  final String? waitStartedAt;
  final double sort;

  /// How long the step takes, or null when the user did not say. When it is
  /// alone in its block, the block is this long.
  final int? lengthMinutes;
  final String createdAt;
  final String updatedAt;

  bool get isDone => doneAt != null;
  bool get isRoot => id == rootIdOf(goalId);
  bool get isWaiting => !isDone && waitStartedAt != null;

  /// The wait at [now]. It stays over until the user ticks the square. A
  /// start time that does not read counts as over, so the square still asks
  /// for a tick.
  SquareWait waitAt(DateTime now) {
    final started = waitStartedAt;
    if (started == null) return SquareWait.none;
    final from = DateTime.tryParse(started);
    if (from == null) return const SquareWait(WaitPhase.over, 'Wait is over');
    final end = from.add(Duration(minutes: waitMinutes ?? 0));
    final left = end.difference(now);
    if (left > Duration.zero) {
      return SquareWait(WaitPhase.running, _leftLabel(left));
    }
    return SquareWait(WaitPhase.over, _overLabel(-left));
  }

  static String _leftLabel(Duration left) {
    if (left >= const Duration(hours: 24)) {
      final days = (left.inMinutes / (24 * 60)).ceil();
      return days == 1 ? '1 day left' : '$days days left';
    }
    return '${(left.inMinutes / 60).ceil()} h left';
  }

  static String _overLabel(Duration over) {
    final days = over.inDays;
    if (days == 0) return 'Wait is over';
    return days == 1 ? '1 day over' : '$days days over';
  }

  GoalSquare copyWith({
    String? id,
    String? goalId,
    String? title,
    Object? doneAt = keep,
    Object? waitMinutes = keep,
    Object? waitStartedAt = keep,
    double? sort,
    Object? lengthMinutes = keep,
    String? createdAt,
    String? updatedAt,
  }) => GoalSquare(
    id: id ?? this.id,
    goalId: goalId ?? this.goalId,
    title: title ?? this.title,
    doneAt: identical(doneAt, keep) ? this.doneAt : doneAt as String?,
    waitMinutes: identical(waitMinutes, keep)
        ? this.waitMinutes
        : waitMinutes as int?,
    waitStartedAt: identical(waitStartedAt, keep)
        ? this.waitStartedAt
        : waitStartedAt as String?,
    sort: sort ?? this.sort,
    lengthMinutes: identical(lengthMinutes, keep)
        ? this.lengthMinutes
        : lengthMinutes as int?,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  List<Object?> get _props => [
    id,
    goalId,
    title,
    doneAt,
    waitMinutes,
    waitStartedAt,
    sort,
    lengthMinutes,
    createdAt,
    updatedAt,
  ];

  @override
  bool operator ==(Object other) =>
      other is GoalSquare && sameList(other._props, _props);

  @override
  int get hashCode => Object.hashAll(_props);
}

/// [childId] must be done before [parentId].
class SquareLink {
  const SquareLink({required this.childId, required this.parentId});

  final String childId;
  final String parentId;

  @override
  bool operator ==(Object other) =>
      other is SquareLink &&
      other.childId == childId &&
      other.parentId == parentId;

  @override
  int get hashCode => Object.hash(childId, parentId);

  @override
  String toString() => '$childId>$parentId';
}

/// [eventId] is a block that holds the square [squareId]. A square can need
/// many blocks, and a block can hold many squares.
class SquareBlock {
  const SquareBlock({required this.squareId, required this.eventId});

  final String squareId;
  final String eventId;

  @override
  bool operator ==(Object other) =>
      other is SquareBlock &&
      other.squareId == squareId &&
      other.eventId == eventId;

  @override
  int get hashCode => Object.hash(squareId, eventId);
}
