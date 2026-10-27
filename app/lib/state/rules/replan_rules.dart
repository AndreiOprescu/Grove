import 'dart:math';

import '../../core/model/day_key.dart';
import '../../core/planner/planner_math.dart';

/// The order of "Reorganise rest of day": tasks with a deadline first, then
/// goal blocks, then the other tasks.
enum ReplanGroup { deadline, goal, task }

/// One thing to put in the rest of the day: an open task of today, or one
/// open goal block.
class ReplanItem {
  const ReplanItem({
    required this.id,
    required this.title,
    required this.group,
    required this.base,
    this.blocks = const [],
  });

  /// The task id, or the event id of a goal block.
  final String id;
  final String title;
  final ReplanGroup group;

  /// The minutes of the whole thing: its open blocks of today, or the
  /// estimate of a task with no block.
  final int base;

  /// Its open blocks today, earliest first. A goal block has itself only.
  final List<Span> blocks;

  bool get isGoal => group == ReplanGroup.goal;

  @override
  String toString() => 'ReplanItem($id, $title)';
}

/// Where one item goes.
class ReplanStep {
  const ReplanStep({
    required this.item,
    required this.pct,
    required this.remaining,
    this.kept = const [],
    this.placedAt,
  });

  final ReplanItem item;

  /// How much of it is done, 0 to 100.
  final int pct;

  /// The minutes still to do, on the grid of 15. 0 when done.
  final int remaining;

  /// The worked part: the blocks (by event id) that stay before the start
  /// of the plan, as long as the share that is done. They become the
  /// record of the work.
  final List<Span> kept;

  /// The start of the block for the rest, or null.
  final int? placedAt;

  bool get done => pct >= 100;

  /// It did not fit before the sleep line.
  bool get overflow => !done && placedAt == null;

  @override
  String toString() => 'ReplanStep(${item.id}, $pct%, $placedAt)';
}

/// What the plan works from: the items, the time that is taken, now and the
/// sleep line (minutes of [day]).
class ReplanInput {
  const ReplanInput({
    required this.day,
    required this.items,
    required this.fixed,
    required this.now,
    required this.until,
  });

  final DayKey day;
  final List<ReplanItem> items;

  /// Everything else of the day that takes time.
  final List<Span> fixed;
  final int now;

  /// The sleep line of the day, or the end of the day.
  final int until;

  /// The start of the plan: now, up to the next step of 15 minutes.
  int get from =>
      (now + PlannerMath.step - 1) ~/ PlannerMath.step * PlannerMath.step;

  /// The end of the plan: the sleep line, or midnight when the sleep line
  /// is at or before the start.
  int get end => until <= from ? PlannerMath.dayEnd : until;
}

/// "Reorganise rest of day" (the button next to Timeline). Pure: no UI, no
/// database.
abstract final class ReplanRules {
  static int clampPct(int pct) => pct < 0 ? 0 : (pct > 100 ? 100 : pct);

  /// The minutes left of [base] when [pct] is done, rounded up to the grid
  /// of 15. A task of 60 minutes, 80% done: 12 minutes left, so 15.
  static int remaining(int base, int pct) {
    final p = clampPct(pct);
    if (p >= 100) return 0;
    return PlannerMath.blockLength((base * (100 - p) + 99) ~/ 100);
  }

  /// Each item in plan order with its new place. [pct] is how much of each
  /// is done, by item id (none = 0%).
  static List<ReplanStep> plan(ReplanInput input, Map<String, int> pct) {
    final from = input.from, until = input.end;
    int pctOf(ReplanItem i) => clampPct(pct[i.id] ?? 0);
    int firstStart(ReplanItem i) =>
        i.blocks.isEmpty ? PlannerMath.dayEnd : i.blocks.first.start;
    final items = [...input.items]
      ..sort((a, b) {
        final byGroup = a.group.index.compareTo(b.group.index);
        if (byGroup != 0) return byGroup;
        final byRest = remaining(
          a.base,
          pctOf(a),
        ).compareTo(remaining(b.base, pctOf(b)));
        if (byRest != 0) return byRest;
        final byStart = firstStart(a).compareTo(firstStart(b));
        if (byStart != 0) return byStart;
        final byTitle = a.title.compareTo(b.title);
        return byTitle != 0 ? byTitle : a.id.compareTo(b.id);
      });
    final busy = [...input.fixed];
    final placed = <String, int?>{};
    for (final i in items) {
      final p = pctOf(i);
      if (p >= 100) continue;
      final rest = remaining(i.base, p);
      final slot = PlannerMath.firstFreeSlot(
        length: rest,
        busy: busy,
        from: from,
        until: until,
        step: PlannerMath.step,
      );
      placed[i.id] = slot;
      if (slot != null) busy.add(Span(id: i.id, start: slot, end: slot + rest));
    }
    final kept = _records(
      [
        for (final i in items)
          // A task that does not fit goes back to the list with no block.
          if (placed.containsKey(i.id) && (placed[i.id] != null || i.isGoal)) i,
      ],
      pctOf,
      from,
      input.fixed,
    );
    return [
      for (final i in items)
        ReplanStep(
          item: i,
          pct: pctOf(i),
          remaining: remaining(i.base, pctOf(i)),
          kept: kept[i.id] ?? const [],
          placedAt: placed[i.id],
        ),
    ];
  }

  /// The worked part of each item that is part done: as many minutes as
  /// its percent says (`base - remaining`), all before [from]. Blocks that
  /// started before [from] keep their place, earliest first, cut to that
  /// length. When they are shorter (or none started), the worked part is
  /// one span that ends as late as it can by [from] in free time, so it
  /// does not lie on top of [fixed] or another worked part. With no free
  /// time for it, it ends at [from].
  static Map<String, List<Span>> _records(
    List<ReplanItem> items,
    int Function(ReplanItem) pctOf,
    int from,
    List<Span> fixed,
  ) {
    final out = <String, List<Span>>{};
    final taken = [...fixed];
    final later = <ReplanItem, int>{};
    for (final i in items) {
      final p = pctOf(i);
      if (p <= 0 || p >= 100 || i.blocks.isEmpty) continue;
      final worked = PlannerMath.blockLength(i.base - remaining(i.base, p));
      final started = [
        for (final b in i.blocks)
          if (b.start < from)
            Span(id: b.id, start: b.start, end: b.end < from ? b.end : from),
      ];
      if (started.fold(0, (sum, s) => sum + s.length) < worked) {
        later[i] = worked;
        continue;
      }
      var left = worked;
      final kept = <Span>[];
      for (final s in started) {
        if (left <= 0) break;
        final length = s.length < left ? s.length : left;
        kept.add(Span(id: s.id, start: s.start, end: s.start + length));
        left -= length;
      }
      out[i.id] = kept;
      taken.addAll(kept);
    }
    for (final MapEntry(key: i, value: worked) in later.entries) {
      if (from <= 0) continue;
      final id = i.blocks
          .firstWhere((b) => b.start < from, orElse: () => i.blocks.first)
          .id;
      final start = _freeBefore(from, worked, taken) ?? max(0, from - worked);
      final record = Span(id: id, start: start, end: min(start + worked, from));
      out[i.id] = [record];
      taken.add(record);
    }
    return out;
  }

  /// The latest start on the grid of 15 for [length] minutes that end by
  /// [end] with nothing of [busy] in the way, or null.
  static int? _freeBefore(int end, int length, List<Span> busy) {
    for (
      var s = (end - length) ~/ PlannerMath.step * PlannerMath.step;
      s >= 0;
      s -= PlannerMath.step
    ) {
      if (!busy.any((b) => b.start < s + length && b.end > s)) return s;
    }
    return null;
  }
}
