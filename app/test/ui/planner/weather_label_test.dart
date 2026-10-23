// The weather at the top of each day: under the dates of the Planner week,
// next to the date of the Today screen, and its part in Settings.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/ui/planner/weather_label.dart';

import '../settings/settings_support.dart';

const oslo = WeatherPlace(
  name: 'Oslo',
  region: 'Oslo, Norway',
  latitude: 59.91,
  longitude: 10.75,
);

/// A planner store on Wednesday with a forecast from Wednesday on.
Future<(AppStore, FakeWeather)> weatherStore({
  Screen screen = Screen.planner,
  List<WeatherPlace> towns = const [oslo],
}) async {
  final weather = FakeWeather(from: wednesday, towns: towns);
  final store = makeStore(
    prefs: MemoryPrefs()..set('appearance.motion', false),
    clock: WallTime(day: wednesday, minute: 10 * 60),
    weather: weather,
    location: FakeLocation(),
  );
  store
    ..selectedDay = wednesday
    ..screen = screen;
  await store.refreshWeather();
  return (store, weather);
}

Finder weatherOf(DayKey day) => keyed('weather-${day.string}');

String labelOf(WidgetTester tester, DayKey day) =>
    tester.widget<Text>(weatherOf(day)).data!;

void main() {
  group('Planner week', () {
    testWidgets('each day from today shows its weather', (tester) async {
      final (store, _) = await weatherStore();
      await pumpPlanner(tester, store);
      for (var i = 0; i < 5; i++) {
        final day = wednesday.adding(days: i);
        expect(
          find.descendant(
            of: keyed('day-header-${day.string}'),
            matching: weatherOf(day),
          ),
          findsOneWidget,
        );
        expect(labelOf(tester, day), '🌧️ 9° / 14°');
      }
      // Monday and Tuesday are past: no weather, and the dates stay in one
      // row.
      final monday = wednesday.adding(days: -2);
      expect(weatherOf(monday), findsNothing);
      expect(
        tester.getSize(keyed('day-header-${monday.string}')).height,
        tester.getSize(keyed('day-header-${wednesday.string}')).height,
      );
    });

    testWidgets('the words of the label for a screen reader', (tester) async {
      final (store, _) = await weatherStore();
      await pumpPlanner(tester, store);
      final label = find.ancestor(
        of: weatherOf(wednesday),
        matching: find.byType(WeatherLabel),
      );
      expect(
        find.descendant(of: label, matching: find.byType(Tooltip)),
        findsOneWidget,
      );
      expect(
        tester
            .widget<Tooltip>(
              find.descendant(of: label, matching: find.byType(Tooltip)),
            )
            .message,
        'Rain · low 9° · high 14°',
      );
    });

    testWidgets('no forecast: the dates are as before', (tester) async {
      final store = plannerStore();
      await pumpPlanner(tester, store);
      expect(find.byType(WeatherLabel), findsNothing);
      final (withWeather, _) = await weatherStore();
      await pumpPlanner(tester, withWeather);
      expect(
        find.byType(WeatherLabel),
        findsNWidgets(7),
        reason: 'one for each day of the week',
      );
    });
  });

  group('Today screen', () {
    testWidgets('the weather is next to the date', (tester) async {
      final (store, _) = await weatherStore(screen: Screen.today);
      await pumpPlanner(tester, store, size: const Size(1280, 720));
      expect(labelOf(tester, wednesday), '🌧️ 9° / 14°');
      final date = tester.getRect(keyed('spread-date'));
      final weather = tester.getRect(weatherOf(wednesday));
      expect(weather.left, greaterThan(date.right));
      expect(weather.center.dy, closeTo(date.center.dy, 4));
    });

    testWidgets('on a phone too', (tester) async {
      final (store, _) = await weatherStore(screen: Screen.today);
      await pumpPlanner(tester, store, size: phoneSize);
      expect(weatherOf(wednesday), findsOneWidget);
    });
  });

  group('Settings', () {
    testWidgets('no part with no weather source', (tester) async {
      await openSettings(tester, plannerStore(), tab: SettingsTab.planner);
      expect(keyed('settings-weather-switch'), findsNothing);
    });

    testWidgets('off takes the weather away', (tester) async {
      final (store, _) = await weatherStore();
      await openSettings(tester, store, tab: SettingsTab.planner);
      await tester.ensureVisible(keyed('settings-weather-switch'));
      await tester.tap(keyed('settings-weather-switch'));
      await tester.pumpAndSettle();
      expect(store.showsWeather, isFalse);
      expect(weatherOf(wednesday), findsNothing);
      expect(keyed('settings-weather-place'), findsNothing);
    });

    testWidgets('°F changes the label', (tester) async {
      final (store, _) = await weatherStore();
      await openSettings(tester, store, tab: SettingsTab.planner);
      await tester.ensureVisible(inSettings(find.text('°F')));
      await tester.tap(inSettings(find.text('°F')));
      await tester.pumpAndSettle();
      expect(store.temperatureUnit, TemperatureUnit.fahrenheit);
      expect(labelOf(tester, wednesday), '🌧️ 48° / 57°');
    });

    testWidgets('a town found by its name', (tester) async {
      final (store, weather) = await weatherStore();
      await openSettings(tester, store, tab: SettingsTab.planner);
      expect(
        inSettings(find.text('My location')),
        findsOneWidget,
        reason: 'the place by default',
      );
      await tester.ensureVisible(keyed('settings-weather-place'));
      await tester.tap(keyed('settings-weather-place'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: keyed('weather-place-search'),
          matching: find.byType(EditableText),
        ),
        'Oslo',
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(weather.searched, ['Oslo']);
      await tester.tap(keyed('weather-place-0'));
      await tester.pumpAndSettle();
      expect(store.weatherPlace?.name, 'Oslo');
      expect(weather.asked.last, (59.91, 10.75));
      expect(inSettings(find.text('Oslo, Oslo, Norway')), findsOneWidget);
    });

    testWidgets('the search says when it finds nothing', (tester) async {
      final (store, _) = await weatherStore(towns: const []);
      store.weatherPlace = oslo;
      await openSettings(tester, store, tab: SettingsTab.planner);
      await tester.ensureVisible(keyed('settings-weather-place'));
      await tester.tap(keyed('settings-weather-place'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: keyed('weather-place-search'),
          matching: find.byType(EditableText),
        ),
        'Nowhere',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('No town with this name.'), findsOneWidget);
      expect(keyed('weather-place-0'), findsNothing);
      // Back to the position of this device.
      await tester.tap(keyed('weather-place-here'));
      await tester.pumpAndSettle();
      expect(store.weatherPlace, isNull);
      expect(inSettings(find.text('My location')), findsOneWidget);
    });

    testWidgets('no internet in the search says so', (tester) async {
      final (store, weather) = await weatherStore();
      await openSettings(tester, store, tab: SettingsTab.planner);
      await tester.ensureVisible(keyed('settings-weather-place'));
      await tester.tap(keyed('settings-weather-place'));
      await tester.pumpAndSettle();
      weather.error = const FormatException('offline');
      await tester.enterText(
        find.descendant(
          of: keyed('weather-place-search'),
          matching: find.byType(EditableText),
        ),
        'Oslo',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(
        find.text('Grove could not reach Open-Meteo. Try again later.'),
        findsOneWidget,
      );
    });

    testWidgets('no leave for the location says so', (tester) async {
      final store = makeStore(
        prefs: MemoryPrefs()..set('appearance.motion', false),
        clock: WallTime(day: wednesday, minute: 10 * 60),
        weather: FakeWeather(from: wednesday),
        location: FakeLocation(
          const LocationAnswer.problem(LocationProblem.denied),
        ),
      )..selectedDay = wednesday;
      await store.refreshWeather();
      await openSettings(tester, store, tab: SettingsTab.planner);
      await tester.ensureVisible(keyed('settings-weather-problem'));
      expect(find.text(LocationProblem.denied.words), findsOneWidget);
    });
  });
}
