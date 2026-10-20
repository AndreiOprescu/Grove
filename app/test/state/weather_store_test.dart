import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

// The weather in the store: Grove asks Open-Meteo for the forecast of the
// place of this device or of a picked town, keeps it, and gives the weather
// of each day from today on.

final today = DayKey.parse('2026-10-20')!;
const oslo = WeatherPlace(name: 'Oslo', latitude: 59.91, longitude: 10.75);

AppStore weatherStore({
  FakeWeather? weather,
  FakeLocation? location,
  Prefs? prefs,
  int minute = 8 * 60,
}) => makeStore(
  weather: weather ?? FakeWeather(from: today),
  location: location ?? FakeLocation(),
  prefs: prefs,
  clock: WallTime(day: today, minute: minute),
);

void main() {
  group('WeatherStore', () {
    test('no source: no weather and no setting', () async {
      final s = makeStore(clock: WallTime(day: today, minute: 0));
      expect(s.canShowWeather, isFalse);
      await s.refreshWeather();
      expect(s.weatherFor(today), isNull);
    });

    test('my location: the weather of each day from today on', () async {
      final weather = FakeWeather(from: today.adding(days: -1), count: 17);
      final location = FakeLocation();
      final s = weatherStore(weather: weather, location: location);
      expect(s.weatherFor(today), isNull);
      await s.refreshWeather();
      expect(location.asked, 1);
      expect(weather.asked, [(51.5072, -0.1276)]);
      expect(s.weatherFor(today)?.condition, WeatherCondition.rain);
      expect(s.weatherFor(today.adding(days: 15))?.evening, 14);
      // A day in the past, and a day after the forecast.
      expect(s.weatherFor(today.adding(days: -1)), isNull);
      expect(s.weatherFor(today.adding(days: 16)), isNull);
    });

    test('on by default, and off shows nothing', () async {
      final s = weatherStore();
      expect(s.showsWeather, isTrue);
      await s.refreshWeather();
      s.showsWeather = false;
      expect(s.weatherFor(today), isNull);
      expect(s.prefs.getBool('weather.on'), isFalse);
    });

    test('off asks nothing, and on again asks', () async {
      final weather = FakeWeather(from: today);
      final s = weatherStore(weather: weather)..showsWeather = false;
      await s.refreshWeather(force: true);
      expect(weather.asked, isEmpty);
      s.showsWeather = true;
      await pumpEventQueue();
      expect(weather.asked, hasLength(1));
      expect(s.weatherFor(today), isNotNull);
    });

    test('asks at most once an hour', () async {
      final weather = FakeWeather(from: today);
      final s = weatherStore(weather: weather);
      await s.refreshWeather();
      s.clockOverride = WallTime(day: today, minute: 8 * 60 + 59);
      await s.refreshWeather();
      expect(weather.asked, hasLength(1));
      s.clockOverride = WallTime(day: today, minute: 9 * 60);
      await s.refreshWeather();
      expect(weather.asked, hasLength(2));
      await s.refreshWeather(force: true);
      expect(weather.asked, hasLength(3));
    });

    test('a town: its position, and no question to the device', () async {
      final weather = FakeWeather(from: today);
      final location = FakeLocation();
      final s = weatherStore(weather: weather, location: location);
      s.weatherPlace = oslo;
      await pumpEventQueue();
      expect(location.asked, 0);
      expect(weather.asked, [(59.91, 10.75)]);
      expect(s.weatherPlace?.name, 'Oslo');
      expect(s.weatherFor(today), isNotNull);
    });

    test('a new place drops the old forecast', () async {
      final weather = FakeWeather(from: today);
      final s = weatherStore(weather: weather);
      await s.refreshWeather();
      weather.error = const SocketException('offline');
      s.weatherPlace = oslo;
      await pumpEventQueue();
      expect(s.weatherFor(today), isNull);
      // Back to my location: the old forecast of here is gone too.
      s.weatherPlace = null;
      await pumpEventQueue();
      expect(s.weatherFor(today), isNull);
    });

    test('an answer for the old place is dropped', () async {
      final weather = FakeWeather(from: today)..gate = Completer();
      final s = weatherStore(weather: weather);
      final asking = s.refreshWeather();
      await pumpEventQueue();
      s.prefs.set(
        'weather.place',
        '{"name":"Oslo","latitude":59.91,"longitude":10.75}',
      );
      weather.gate!.complete();
      await asking;
      expect(s.weatherFor(today), isNull);
    });

    test('no leave for the location: the problem, and no weather', () async {
      final location = FakeLocation(
        const LocationAnswer.problem(LocationProblem.denied),
      );
      final weather = FakeWeather(from: today);
      final s = weatherStore(weather: weather, location: location);
      await s.refreshWeather();
      expect(s.weatherProblem, LocationProblem.denied);
      expect(weather.asked, isEmpty);
      expect(s.weatherFor(today), isNull);
      // A town takes the problem away.
      s.weatherPlace = oslo;
      expect(s.weatherProblem, isNull);
    });

    test('no internet keeps the last forecast', () async {
      final weather = FakeWeather(from: today);
      final s = weatherStore(weather: weather);
      await s.refreshWeather();
      weather.error = const SocketException('offline');
      await s.refreshWeather(force: true);
      expect(s.weatherFor(today), isNotNull);
    });

    test('the forecast is kept for the next start', () async {
      final prefs = MemoryPrefs();
      final first = weatherStore(prefs: prefs);
      await first.refreshWeather();
      final weather = FakeWeather(from: today)
        ..error = const SocketException('offline');
      final next = weatherStore(prefs: prefs, weather: weather);
      expect(next.weatherFor(today)?.morning, 9);
      // Less than an hour old: no question.
      await next.refreshWeather();
      expect(weather.asked, isEmpty);
    });

    test('a damaged saved forecast or place counts as none', () {
      final prefs = MemoryPrefs({
        'weather.forecast': '{not json',
        'weather.place': '[1, 2]',
      });
      final s = weatherStore(prefs: prefs);
      expect(s.weatherFor(today), isNull);
      expect(s.weatherPlace, isNull);
    });

    test('°C by default, and °F is saved', () {
      final s = weatherStore();
      expect(s.temperatureUnit, TemperatureUnit.celsius);
      s.temperatureUnit = TemperatureUnit.fahrenheit;
      expect(s.prefs.getString('weather.unit'), 'fahrenheit');
    });

    test('the town search needs two letters', () async {
      final weather = FakeWeather(from: today, towns: const [oslo]);
      final s = weatherStore(weather: weather);
      expect(await s.searchWeatherPlaces(' o '), isEmpty);
      expect(await s.searchWeatherPlaces('Oslo'), [oslo]);
      expect(weather.searched, ['Oslo']);
    });
  });
}
