import 'day_key.dart';
import 'ids.dart';

/// One area the persona grows in, with its own bar and level (Strength,
/// Mind, ...). A skill is never deleted, only hidden: its earnings stay.
class SkillItem {
  SkillItem({
    String? id,
    required this.name,
    this.sort = 0,
    this.hidden = false,
    this.builtin = false,
    String? createdAt,
    String? updatedAt,
  }) : id = id ?? newId(),
       createdAt = createdAt ?? updatedAt ?? Stamp.now(),
       updatedAt = updatedAt ?? createdAt ?? Stamp.now();

  final String id;
  final String name;
  final double sort;

  /// A hidden skill has no bar on the Persona screen and cannot be picked
  /// for a new reward. Its points still count.
  final bool hidden;

  /// One of the 8 skills that every Grove starts with.
  final bool builtin;
  final String createdAt;
  final String updatedAt;

  SkillItem copyWith({
    String? name,
    double? sort,
    bool? hidden,
    String? updatedAt,
  }) => SkillItem(
    id: id,
    name: name ?? this.name,
    sort: sort ?? this.sort,
    hidden: hidden ?? this.hidden,
    builtin: builtin,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  List<Object?> get _props => [
    id,
    name,
    sort,
    hidden,
    builtin,
    createdAt,
    updatedAt,
  ];

  @override
  bool operator ==(Object other) =>
      other is SkillItem && sameList(other._props, _props);

  @override
  int get hashCode => Object.hashAll(_props);
}

/// The setting on a task or a goal that says how many points one skill gets.
/// A task pays [points] when it is ticked done. A goal pays [points] per hour
/// of each goal block that is ticked done. Exactly one of [taskId] and
/// [goalId] is set.
class RewardItem {
  RewardItem({
    required this.id,
    this.taskId,
    this.goalId,
    required this.skillId,
    required this.points,
  }) : assert((taskId == null) != (goalId == null));

  final String id;
  final String? taskId;
  final String? goalId;
  final String skillId;
  final int points;

  RewardItem copyWith({int? points}) => RewardItem(
    id: id,
    taskId: taskId,
    goalId: goalId,
    skillId: skillId,
    points: points ?? this.points,
  );

  List<Object?> get _props => [id, taskId, goalId, skillId, points];

  @override
  bool operator ==(Object other) =>
      other is RewardItem && sameList(other._props, _props);

  @override
  int get hashCode => Object.hashAll(_props);
}

/// What was ticked done to pay an earning.
enum EarningSource {
  task('task'),
  goalBlock('goal_block');

  const EarningSource(this.code);

  /// The text in the database.
  final String code;

  static EarningSource fromCode(String code) =>
      values.firstWhere((s) => s.code == code, orElse: () => task);
}

/// One line of the log: points paid to a skill when a task or a goal block
/// was ticked done. Un-ticking takes it away. Changing the reward later does
/// not change it, and deleting the task keeps it.
class EarningItem {
  EarningItem({
    required this.id,
    required this.skillId,
    required this.points,
    required this.source,
    required this.sourceId,
    this.title = '',
    required this.earnedAt,
  });

  final String id;
  final String skillId;
  final int points;
  final EarningSource source;

  /// The id of the task or the goal block. It can point at a row that is
  /// gone.
  final String sourceId;

  /// The title of the task or the goal when it was ticked.
  final String title;
  final String earnedAt;

  List<Object?> get _props => [
    id,
    skillId,
    points,
    source,
    sourceId,
    title,
    earnedAt,
  ];

  @override
  bool operator ==(Object other) =>
      other is EarningItem && sameList(other._props, _props);

  @override
  int get hashCode => Object.hashAll(_props);
}
