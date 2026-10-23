// The weather at the top of a day: the emoji of the kind of the day, and
// its lowest and highest temperature (`store_weather.dart`). The Planner
// week shows it under each date, the Today screen next to its date.
import 'package:flutter/material.dart';
import 'package:grove/core/model/day_key.dart';
import 'package:grove/state/state.dart' hide MotionRules;

import '../theme/grove_theme.dart';

class WeatherLabel extends StatelessWidget {
  const WeatherLabel({
    super.key,
    required this.store,
    required this.day,
    this.size = 11,
  });

  final AppStore store;
  final DayKey day;
  final double size;

  @override
  Widget build(BuildContext context) {
    final weather = store.weatherFor(day);
    if (weather == null) return const SizedBox.shrink();
    final theme = GroveTheme.of(context);
    final unit = store.temperatureUnit;
    final words = WeatherRules.words(weather, unit);
    return Tooltip(
      message: words,
      child: Semantics(
        container: true,
        label: 'Weather: $words',
        excludeSemantics: true,
        child: Text(
          WeatherRules.label(weather, unit),
          key: ValueKey('weather-${day.string}'),
          maxLines: 1,
          softWrap: false,
          style: theme.body(size).copyWith(color: theme.muted),
        ),
      ),
    );
  }
}
