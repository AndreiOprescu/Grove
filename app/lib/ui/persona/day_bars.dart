// "Your days" on the Persona screen: a bar each for the good, okay and rough
// days, from the moods of the daily notes, and a picker for today's mood.
import 'package:flutter/material.dart';
import 'package:grove/state/state.dart' hide MotionRules;

import '../calendar/month_view.dart' show moodTint;
import '../notes/day_panel.dart' show MoodPicker;
import '../tasks/task_widgets.dart' show Segments;
import '../theme/grove_theme.dart';
import '../theme/panel.dart';
import '../theme/symbols.dart';
import 'skill_bar.dart';

class DayBars extends StatelessWidget {
  const DayBars({super.key, required this.store});

  final AppStore store;

  /// Good first: the order a person reads the bars in.
  static const order = [Mood.sun, Mood.cloud, Mood.rain];

  /// The word of a mood beside its bar, and the start of its keys.
  static String word(Mood m) => switch (m) {
    Mood.sun => 'Good',
    Mood.cloud => 'Okay',
    Mood.rain => 'Rough',
  };

  static const emptyLine =
      'No days marked yet. Pick one below or in a daily note.';

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    final span = store.daySpan;
    final counts = store.dayCounts(span);
    final small = theme.body(12).copyWith(color: theme.muted);
    return Panel(
      key: const ValueKey('persona-days'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 12,
          children: [
            Row(
              spacing: 12,
              children: [
                const Expanded(child: ThemedHeading('Your days', 16)),
                SizedBox(
                  width: 170,
                  child: Segments<DaySpan>(
                    value: span,
                    values: DaySpan.values,
                    name: (s) => s.label,
                    label: 'Days to count',
                    onPick: store.setDaySpan,
                  ),
                ),
              ],
            ),
            for (final m in order) _row(theme, m, counts),
            if (counts.total == 0) Text(emptyLine, style: small),
            Wrap(
              spacing: 10,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('How was today?', style: small),
                MoodPicker.of(
                  selected: store.todayMood,
                  onPick: store.setTodayMood,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(GroveTheme theme, Mood m, DayCounts counts) {
    final name = word(m).toLowerCase();
    final n = counts.of(m);
    return Semantics(
      container: true,
      label: '${word(m)} days',
      value: '$n',
      excludeSemantics: true,
      child: Row(
        spacing: 10,
        children: [
          Icon(symbolIcon(m.symbol), size: 16, color: moodTint(m)),
          SizedBox(
            width: 56,
            child: Text(
              word(m),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.body(13).copyWith(color: theme.ink),
            ),
          ),
          Expanded(
            child: SkillBar(
              name: 'days-$name',
              fill: counts.fill(m),
              height: 10,
              color: moodTint(m),
            ),
          ),
          SizedBox(
            width: 32,
            child: Text(
              '$n',
              key: ValueKey('days-$name-count'),
              textAlign: TextAlign.right,
              style: theme
                  .body(13, weight: FontWeight.w600)
                  .copyWith(color: theme.ink),
            ),
          ),
        ],
      ),
    );
  }
}
