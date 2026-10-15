import '../model/persona.dart';

export '../model/persona.dart';

/// Where a skill (or the whole persona) stands: its level and how full the
/// bar of that level is.
class SkillLevel {
  const SkillLevel({
    required this.level,
    required this.into,
    required this.needed,
  });

  /// Level 1 is the start.
  final int level;

  /// The points reached inside this level.
  final int into;

  /// The points this level needs, from its start to the next level.
  final int needed;

  /// How full the bar is, 0 to 1.
  double get fill => needed == 0 ? 0 : into / needed;

  /// The level of a skill with [points]. Level L to L+1 needs 50 + 10·L
  /// points: 60, then 70, 80, ...
  static SkillLevel of(int points) => _of(points, 1);

  /// The level of the persona: the same curve on the points of all skills,
  /// with each step 4 times as big.
  static SkillLevel persona(int points) => _of(points, 4);

  static SkillLevel _of(int points, int scale) {
    var left = points < 0 ? 0 : points;
    var level = 1;
    while (true) {
      final need = (50 + 10 * level) * scale;
      if (left < need) {
        return SkillLevel(level: level, into: left, needed: need);
      }
      left -= need;
      level += 1;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is SkillLevel &&
      other.level == level &&
      other.into == into &&
      other.needed == needed;

  @override
  int get hashCode => Object.hash(level, into, needed);

  @override
  String toString() => 'SkillLevel($level, $into/$needed)';
}

/// The rules of the persona: the skills it starts with and how points are
/// paid.
abstract final class PersonaRules {
  /// The name when the user has not given one.
  static const defaultName = 'You';

  /// The key of the persona's name in the settings table.
  static const nameKey = 'persona.name';

  static const maxNameLength = 24;
  static const maxPoints = 999;

  /// The 8 skills that every Grove starts with. Fixed ids, so two devices
  /// have the same rows. The shared migration 10 writes them.
  static final List<SkillItem> builtins = [
    for (final (i, name) in const [
      'Strength',
      'Mind',
      'Social',
      'Focus',
      'Creativity',
      'Health',
      'Home',
      'Money',
    ].indexed)
      SkillItem(
        id: 'skill-${name.toLowerCase()}',
        name: name,
        sort: i + 1,
        builtin: true,
        createdAt: seedStamp,
      ),
  ];

  /// The time stamp of the built-in skills.
  static const seedStamp = '2026-10-15T00:00:00';

  /// The points of a goal block: [perHour] for each hour of the block,
  /// rounded to a whole number.
  static int blockPoints({required int perHour, required int minutes}) =>
      minutes <= 0 ? 0 : (perHour * minutes / 60).round();

  static int clampPoints(int points) => points.clamp(1, maxPoints);

  static String cleanName(String name) {
    final t = name.trim();
    return t.length > maxNameLength ? t.substring(0, maxNameLength) : t;
  }

  static String taskRewardId(String taskId, String skillId) =>
      'r:task:$taskId:$skillId';

  static String goalRewardId(String goalId, String skillId) =>
      'r:goal:$goalId:$skillId';

  static String earningId(
    EarningSource source,
    String sourceId,
    String skillId,
  ) => 'e:${source.code}:$sourceId:$skillId';
}

/// A skill that just reached a new level.
class LevelUp {
  const LevelUp({
    required this.skillId,
    required this.skillName,
    required this.level,
  });

  final String skillId;
  final String skillName;
  final int level;
}
