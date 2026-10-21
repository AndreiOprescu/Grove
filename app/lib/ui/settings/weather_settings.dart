// The "Weather" part of the Planner tab of Settings: the weather on or
// off, its place (this device or a town) and °C or °F. The window of the
// town search is here too.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:grove/state/state.dart' hide MotionRules;

import '../planner/planner_dialogs.dart';
import '../tasks/task_widgets.dart';
import '../theme/grove_theme.dart';
import '../theme/panel.dart';
import 'settings_parts.dart';

class WeatherSettings extends StatelessWidget {
  const WeatherSettings({super.key, required this.store});

  final AppStore store;

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    final on = store.showsWeather;
    final problem = store.weatherProblem;
    return SettingsSection(
      title: 'Weather',
      children: [
        SettingsSwitchRow(
          switchKey: const ValueKey('settings-weather-switch'),
          label: 'Show the weather',
          value: on,
          onChanged: (v) => store.showsWeather = v,
        ),
        if (on) ...[
          SettingsRow(
            label: 'Place',
            control: CardButton(
              key: const ValueKey('settings-weather-place'),
              label: store.weatherPlace?.label ?? 'My location',
              onTap: () => unawaited(showWeatherPlacePicker(context, store)),
            ),
          ),
          SettingsRow(
            label: 'Temperature',
            control: SizedBox(
              width: 120,
              child: Segments<TemperatureUnit>(
                value: store.temperatureUnit,
                values: TemperatureUnit.values,
                name: (u) => u.symbol,
                onPick: (u) => store.temperatureUnit = u,
                label: 'Temperature',
              ),
            ),
          ),
          if (problem != null)
            Text(
              problem.words,
              key: const ValueKey('settings-weather-problem'),
              style: theme.body(13).copyWith(color: theme.ink),
            ),
        ],
        const SettingsCaption(
          'Each day shows its weather and the temperature at 9am and 9pm. '
          'Weather data by Open-Meteo.com.',
        ),
      ],
    );
  }
}

/// The window that picks the place of the weather: "My location", or a
/// town found by its name.
Future<void> showWeatherPlacePicker(BuildContext context, AppStore store) =>
    showDialog<void>(
      context: context,
      builder: (context) => _PlacePicker(store: store),
    );

class _PlacePicker extends StatefulWidget {
  const _PlacePicker({required this.store});

  final AppStore store;

  @override
  State<_PlacePicker> createState() => _PlacePickerState();
}

class _PlacePickerState extends State<_PlacePicker> {
  final _text = TextEditingController();
  Timer? _wait;
  List<WeatherPlace> _found = const [];
  String? _message;

  /// The name of the newest search. An older answer that comes late is
  /// dropped.
  String _asked = '';

  @override
  void dispose() {
    _wait?.cancel();
    _text.dispose();
    super.dispose();
  }

  void _typed(String text) {
    _wait?.cancel();
    _wait = Timer(const Duration(milliseconds: 400), () => _search(text));
  }

  Future<void> _search(String text) async {
    _wait?.cancel();
    final name = text.trim();
    _asked = name;
    if (name.length < 2) {
      setState(() {
        _found = const [];
        _message = null;
      });
      return;
    }
    setState(() => _message = 'Searching…');
    try {
      final found = await widget.store.searchWeatherPlaces(name);
      if (!mounted || _asked != name) return;
      setState(() {
        _found = found;
        _message = found.isEmpty ? 'No town with this name.' : null;
      });
    } on Object {
      if (!mounted || _asked != name) return;
      setState(() {
        _found = const [];
        _message = 'Grove could not reach Open-Meteo. Try again later.';
      });
    }
  }

  void _pick(WeatherPlace? place) {
    widget.store.weatherPlace = place;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    final message = _message;
    return PlannerSheet(
      width: 380,
      children: [
        const ThemedHeading('Weather place', 18),
        Wrap(
          children: [
            CardButton(
              key: const ValueKey('weather-place-here'),
              label: 'Use my location',
              primary: widget.store.weatherPlace == null,
              onTap: () => _pick(null),
            ),
          ],
        ),
        GroveField(
          key: const ValueKey('weather-place-search'),
          controller: _text,
          placeholder: 'Search a town',
          boxed: true,
          autofocus: true,
          onChanged: _typed,
          onSubmitted: _search,
        ),
        if (message != null)
          Semantics(
            container: true,
            liveRegion: true,
            child: Text(
              message,
              key: const ValueKey('weather-place-message'),
              style: theme.body(12).copyWith(color: theme.muted),
            ),
          ),
        for (final (i, place) in _found.indexed)
          Semantics(
            container: true,
            button: true,
            label: place.label,
            onTap: () => _pick(place),
            excludeSemantics: true,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                key: ValueKey('weather-place-$i'),
                behavior: HitTestBehavior.opaque,
                onTap: () => _pick(place),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        place.name,
                        style: theme
                            .body(13, weight: FontWeight.w600)
                            .copyWith(color: theme.ink),
                      ),
                      if (place.region.isNotEmpty)
                        Text(
                          place.region,
                          style: theme.body(11).copyWith(color: theme.muted),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        dialogButtons([
          DialogButton(
            label: 'Cancel',
            onTap: () => Navigator.of(context).pop(),
          ),
        ]),
      ],
    );
  }
}
