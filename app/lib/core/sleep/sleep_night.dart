import 'dart:convert';

import '../model/day_key.dart';
import 'activity.dart';

/// What one device says about one night: when its use stopped and started.
class NightPart {
  const NightPart({required this.asleep, required this.woke});

  final WallTime asleep;
  final WallTime woke;

  @override
  bool operator ==(Object other) =>
      other is NightPart && other.asleep == asleep && other.woke == woke;

  @override
  int get hashCode => Object.hash(asleep, woke);

  @override
  String toString() => 'NightPart($asleep – $woke)';
}

/// One night of sleep, from the parts of each device.
class SleepNight {
  const SleepNight({
    required this.night,
    required this.asleep,
    required this.woke,
    required this.sources,
    required this.parts,
  });

  /// The evening day: the night of the 5th runs into the 6th.
  final DayKey night;
  final WallTime asleep;
  final WallTime woke;

  /// The parts [asleep] and [woke] come from, sorted.
  final List<String> sources;

  /// Every part stored for this night, by device name. Unknown names are kept.
  final Map<String, NightPart> parts;

  /// Minutes asleep.
  int get length => SleepNightRules.minutesBetween(asleep, woke);

  @override
  bool operator ==(Object other) =>
      other is SleepNight &&
      other.night == night &&
      other.asleep == asleep &&
      other.woke == woke &&
      _sameList(other.sources, sources) &&
      _sameMap(other.parts, parts);

  @override
  int get hashCode => Object.hash(
    night,
    asleep,
    woke,
    Object.hashAll(sources),
    Object.hashAllUnordered(
      parts.entries.map((e) => Object.hash(e.key, e.value)),
    ),
  );

  @override
  String toString() => 'SleepNight($night, $asleep – $woke, $sources)';
}

bool _sameList(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _sameMap(Map<String, NightPart> a, Map<String, NightPart> b) =>
    a.length == b.length && a.keys.every((k) => a[k] == b[k]);

/// A stretch of time, local.
class _Span {
  _Span(this.start, this.end);

  final DateTime start;
  final DateTime end;

  Duration get length => end.difference(start);
}

/// The rules of a sleep night. No device calls, no database.
///
/// A night is one row of the `settings` table, so it syncs with no table of
/// its own. Each device writes only its own part; the night is worked out
/// from all parts.
abstract final class SleepNightRules {
  /// A use shorter than this does not break a night (a glance at the clock).
  static const briefUse = Duration(minutes: 3);

  /// The shortest night.
  static const minGap = Duration(hours: 3);

  /// A night overlaps 18:00 on the evening day to 06:00 the next day.
  static const windowStart = 18 * 60;
  static const windowEnd = 24 * 60 + 6 * 60;

  /// "sleep.night."
  static const prefix = 'sleep.night.';

  /// Just after the last key ("/" comes after ".").
  static const prefixEnd = 'sleep.night/';

  /// "sleep.night.2026-10-05"
  static String key(DayKey night) => '$prefix${night.string}';

  /// The night of a key. Null for a key that names no real day.
  static DayKey? dayOf(String key) {
    if (!key.startsWith(prefix)) return null;
    return DayKey.parse(key.substring(prefix.length));
  }

  /// The night of a settings row, or null.
  static SleepNight? parse(String key, String value) {
    final night = dayOf(key);
    return night == null ? null : decode(night, value);
  }

  /// The same night always gives the same text: part names are sorted.
  static String encode(SleepNight n) {
    final names = n.parts.keys.toList()..sort();
    return jsonEncode({
      'v': 1,
      'asleep': n.asleep.string,
      'woke': n.woke.string,
      'source': n.sources.join('+'),
      'parts': {
        for (final name in names)
          name: {
            'a': n.parts[name]!.asleep.string,
            'w': n.parts[name]!.woke.string,
          },
      },
    });
  }

  /// Null for text that is not a night of version 1. A part that cannot be
  /// read is left out.
  static SleepNight? decode(DayKey night, String value) {
    final Object? data;
    try {
      data = jsonDecode(value);
    } on FormatException {
      return null;
    }
    if (data is! Map<String, Object?> || data['v'] != 1) return null;
    final asleep = _time(data['asleep']);
    final woke = _time(data['woke']);
    final source = data['source'];
    if (asleep == null || woke == null || source is! String) return null;
    final parts = <String, NightPart>{};
    final rawParts = data['parts'];
    if (rawParts is Map<String, Object?>) {
      for (final MapEntry(:key, :value) in rawParts.entries) {
        if (value is! Map<String, Object?>) continue;
        final a = _time(value['a']);
        final w = _time(value['w']);
        if (a != null && w != null) parts[key] = NightPart(asleep: a, woke: w);
      }
    }
    return SleepNight(
      night: night,
      asleep: asleep,
      woke: woke,
      sources: source.isEmpty ? const [] : source.split('+'),
      parts: parts,
    );
  }

  static WallTime? _time(Object? value) =>
      value is String ? WallTime.parse(value) : null;

  /// What this device says about [night], from its [events]. Null until the
  /// night is over: the device must have been used before and after it.
  ///
  /// - Only events from 12:00 on [night] to 14:00 the next day count.
  /// - A use under [briefUse] does not split a night.
  /// - A gap of [minGap] or more that overlaps 18:00 to 06:00 is a night.
  ///   The longest one wins.
  /// - The Mac hears events only while Grove runs. When the events hold
  ///   record signals, a gap counts only if Grove was listening all through
  ///   it: the last record signal at or before its start is a start, and no
  ///   record signal falls inside it or at its end.
  static NightPart? derivePart(
    List<ActivityEvent> events,
    DayKey night,
    DateTime now,
  ) {
    final from = night.date.add(const Duration(hours: 12));
    final to = DateTime(night.year, night.month, night.day + 1, 14);

    final indexed = events.indexed.toList()
      ..sort((a, b) {
        final byTime = a.$2.at.compareTo(b.$2.at);
        return byTime != 0 ? byTime : a.$1.compareTo(b.$1);
      });
    final sorted = [for (final (_, e) in indexed) e];
    final inRange = sorted
        .where((e) => !e.at.isBefore(from) && e.at.isBefore(to))
        .toList();

    final spans = <_Span>[];
    DateTime? open;
    var first = true;
    for (final e in inRange) {
      switch (e.signal) {
        case ActivitySignal.useStart:
          open ??= e.at;
        case ActivitySignal.useEnd:
          if (open != null) {
            spans.add(_Span(open, e.at));
            open = null;
          } else if (first) {
            spans.add(_Span(from, e.at));
          }
        case ActivitySignal.recordStop:
          if (open != null) {
            spans.add(_Span(open, e.at));
            open = null;
          }
        case ActivitySignal.recordStart:
          break;
      }
      first = false;
    }
    if (open != null && now.isAfter(open)) spans.add(_Span(open, now));

    final real = spans.where((s) => s.length >= briefUse).toList();
    final records = sorted
        .where(
          (e) =>
              e.signal == ActivitySignal.recordStart ||
              e.signal == ActivitySignal.recordStop,
        )
        .toList();

    final windowFrom = night.date.add(const Duration(hours: 18));
    final windowTo = DateTime(night.year, night.month, night.day + 1, 6);

    _Span? best;
    for (var i = 0; i + 1 < real.length; i++) {
      final gap = _Span(real[i].end, real[i + 1].start);
      if (gap.length < minGap) continue;
      if (!gap.start.isBefore(windowTo) || !gap.end.isAfter(windowFrom)) {
        continue;
      }
      if (!gap.end.isBefore(now)) continue;
      if (records.isNotEmpty && !_listened(records, gap)) continue;
      if (best == null || gap.length > best.length) best = gap;
    }
    if (best == null) return null;
    return NightPart(asleep: _wall(best.start), woke: _wall(best.end));
  }

  static bool _listened(List<ActivityEvent> records, _Span gap) {
    ActivityEvent? before;
    for (final r in records) {
      if (r.at.isAfter(gap.start)) {
        if (!r.at.isAfter(gap.end)) return false;
      } else {
        before = r;
      }
    }
    return before?.signal == ActivitySignal.recordStart;
  }

  static WallTime _wall(DateTime d) =>
      WallTime(day: DayKey.fromDate(d), minute: d.hour * 60 + d.minute);

  /// Minutes from [a] to [b], over days too.
  static int minutesBetween(WallTime a, WallTime b) =>
      a.day.daysUntil(b.day) * 1440 + b.minute - a.minute;

  /// Is this a night of [night]: asleep 18:00 to 06:00, and long enough?
  static bool _fits(DayKey night, WallTime asleep, WallTime woke) {
    final start = minutesBetween(WallTime(day: night, minute: 0), asleep);
    return start >= windowStart &&
        start <= windowEnd &&
        minutesBetween(asleep, woke) >= minGap.inMinutes;
  }

  /// The night from all [parts]: the time no device was used. When that is
  /// too short, the longest part that is a night on its own. Null when no
  /// part is.
  static SleepNight? combine(DayKey night, Map<String, NightPart> parts) {
    if (parts.isEmpty) return null;
    final names = parts.keys.toList()..sort();
    var asleep = parts[names.first]!.asleep;
    var woke = parts[names.first]!.woke;
    for (final name in names.skip(1)) {
      final p = parts[name]!;
      if (p.asleep.compareTo(asleep) > 0) asleep = p.asleep;
      if (p.woke.compareTo(woke) < 0) woke = p.woke;
    }
    if (_fits(night, asleep, woke)) {
      return SleepNight(
        night: night,
        asleep: asleep,
        woke: woke,
        sources: names,
        parts: Map.of(parts),
      );
    }

    String? bestName;
    for (final name in names) {
      final p = parts[name]!;
      if (!_fits(night, p.asleep, p.woke)) continue;
      final best = bestName == null ? null : parts[bestName]!;
      if (best == null ||
          minutesBetween(p.asleep, p.woke) >
              minutesBetween(best.asleep, best.woke)) {
        bestName = name;
      }
    }
    if (bestName == null) return null;
    final p = parts[bestName]!;
    return SleepNight(
      night: night,
      asleep: p.asleep,
      woke: p.woke,
      sources: [bestName],
      parts: Map.of(parts),
    );
  }

  /// The new row text after this device's [part] of [night], or null when
  /// the row should stay as it is. Only the part of [source] is replaced; a
  /// null [part] keeps the stored one. Text that cannot be read counts as no
  /// row.
  static String? merge(
    String? existingJson,
    DayKey night,
    String source,
    NightPart? part,
  ) {
    final stored = existingJson == null ? null : decode(night, existingJson);
    final parts = <String, NightPart>{...?stored?.parts};
    if (part != null) parts[source] = part;
    final combined = combine(night, parts);
    if (combined == null) return null;
    final json = encode(combined);
    return json == existingJson ? null : json;
  }
}
