import 'package:flutter_test/flutter_test.dart';
import 'package:grove/core/model/day_key.dart';
import 'package:grove/core/weather/weather_rules.dart';

/// An answer of `/v1/forecast` for two days, with every hour of each day.
Map<String, Object?> openMeteo({
  List<String> days = const ['2026-10-20', '2026-10-21'],
  List<int> codes = const [61, 0],
  bool hours = true,
}) => {
  'daily': {'time': days, 'weather_code': codes},
  'hourly': {
    'time': [
      if (hours)
        for (final d in days)
          for (var h = 0; h < 24; h++)
            '${d}T${h.toString().padLeft(2, '0')}:00',
    ],
    'temperature_2m': [
      if (hours)
        for (var i = 0; i < days.length; i++)
          // 9am is 9.4 + 10 i, 9pm is 14.6 + 10 i.
          for (var h = 0; h < 24; h++)
            h == 9
                ? 9.4 + 10 * i
                : h == 21
                ? 14.6 + 10 * i
                : 0.0,
    ],
  },
};

void main() {
  final tuesday = DayKey.parse('2026-10-20')!;
  final wednesday = DayKey.parse('2026-10-21')!;

  group('WeatherCondition', () {
    test('each WMO code has its kind', () {
      const kinds = {
        0: WeatherCondition.clear,
        1: WeatherCondition.mostlyClear,
        2: WeatherCondition.partlyCloudy,
        3: WeatherCondition.cloudy,
        45: WeatherCondition.fog,
        48: WeatherCondition.fog,
        53: WeatherCondition.drizzle,
        57: WeatherCondition.drizzle,
        61: WeatherCondition.rain,
        67: WeatherCondition.rain,
        82: WeatherCondition.rain,
        73: WeatherCondition.snow,
        86: WeatherCondition.snow,
        95: WeatherCondition.thunder,
        99: WeatherCondition.thunder,
      };
      for (final MapEntry(key: code, value: kind) in kinds.entries) {
        expect(WeatherCondition.fromCode(code), kind, reason: '$code');
      }
    });

    test('an unknown code is cloudy', () {
      expect(WeatherCondition.fromCode(42), WeatherCondition.cloudy);
      expect(WeatherCondition.fromCode(-1), WeatherCondition.cloudy);
    });
  });

  group('TemperatureUnit', () {
    test('rounds to the whole degree, in °C or °F', () {
      expect(TemperatureUnit.celsius.whole(9.4), 9);
      expect(TemperatureUnit.celsius.whole(-2.6), -3);
      expect(TemperatureUnit.fahrenheit.whole(0), 32);
      expect(TemperatureUnit.fahrenheit.whole(14.6), 58);
    });

    test('°C for no saved name or an unknown one', () {
      expect(TemperatureUnit.fromSaved(null), TemperatureUnit.celsius);
      expect(TemperatureUnit.fromSaved('kelvin'), TemperatureUnit.celsius);
      expect(
        TemperatureUnit.fromSaved('fahrenheit'),
        TemperatureUnit.fahrenheit,
      );
    });
  });

  group('parseForecast', () {
    test('the kind of each day and its temperature at 9am and 9pm', () {
      final days = WeatherRules.parseForecast(openMeteo());
      expect(days.keys, [tuesday, wednesday]);
      expect(
        days[tuesday],
        DayWeather(
          day: tuesday,
          condition: WeatherCondition.rain,
          morning: 9.4,
          evening: 14.6,
        ),
      );
      expect(days[wednesday]!.condition, WeatherCondition.clear);
      expect(days[wednesday]!.morning, 19.4);
      expect(days[wednesday]!.evening, 24.6);
    });

    test('a day with no hours still has its kind', () {
      final days = WeatherRules.parseForecast(openMeteo(hours: false));
      expect(days[tuesday]!.condition, WeatherCondition.rain);
      expect(days[tuesday]!.morning, isNull);
      expect(days[tuesday]!.evening, isNull);
    });

    test('a bad day or code is left out', () {
      final days = WeatherRules.parseForecast({
        'daily': {
          'time': ['2026-10-20', 'soon', '2026-10-22'],
          'weather_code': [3, 3, null],
        },
        'hourly': <String, Object?>{},
      });
      expect(days.keys, [tuesday]);
    });

    test('an answer with no days throws', () {
      expect(
        () => WeatherRules.parseForecast({'error': true}),
        throwsFormatException,
      );
    });
  });

  group('parseSearch', () {
    test('each town with its region and country', () {
      final towns = WeatherRules.parseSearch({
        'results': [
          {
            'name': 'Paris',
            'latitude': 48.85341,
            'longitude': 2.3488,
            'admin1': 'Île-de-France',
            'country': 'France',
          },
          {'name': 'Paris', 'latitude': 33.66, 'longitude': -95.55},
          {
            'name': 'Bucharest',
            'latitude': 44.43,
            'longitude': 26.11,
            'admin1': 'Bucharest',
            'country': 'Romania',
          },
          {'name': 'No place'},
        ],
      });
      expect(towns.map((t) => t.label), [
        'Paris, Île-de-France, France',
        'Paris',
        'Bucharest, Romania',
      ]);
      expect(towns.first.latitude, 48.85341);
    });

    test('no results is no town', () {
      expect(WeatherRules.parseSearch({'generationtime_ms': 0.4}), isEmpty);
    });
  });

  group('the label', () {
    final rain = DayWeather(
      day: tuesday,
      condition: WeatherCondition.rain,
      morning: 9.4,
      evening: 14.6,
    );

    test('the emoji, then 9am, then 9pm', () {
      expect(WeatherRules.label(rain, TemperatureUnit.celsius), '🌧️ 9° → 15°');
      expect(
        WeatherRules.label(rain, TemperatureUnit.fahrenheit),
        '🌧️ 49° → 58°',
      );
    });

    test('a missing hour shows a dash, and no hours shows the emoji', () {
      final half = DayWeather(
        day: tuesday,
        condition: WeatherCondition.clear,
        evening: -1.2,
      );
      expect(WeatherRules.label(half, TemperatureUnit.celsius), '☀️ – → -1°');
      final none = DayWeather(day: tuesday, condition: WeatherCondition.fog);
      expect(WeatherRules.label(none, TemperatureUnit.celsius), '🌫️');
    });

    test('the words of the tooltip', () {
      expect(
        WeatherRules.words(rain, TemperatureUnit.celsius),
        'Rain · 9am 9° · 9pm 15°',
      );
    });
  });

  group('the questions', () {
    test('the forecast asks for 16 days at a position to two places', () {
      final url = WeatherRules.forecastUrl(51.507222, -0.1275);
      expect(url.host, 'api.open-meteo.com');
      expect(url.queryParameters, {
        'latitude': '51.51',
        'longitude': '-0.13',
        'daily': 'weather_code',
        'hourly': 'temperature_2m',
        'timezone': 'auto',
        'forecast_days': '16',
      });
    });

    test('the search asks for the name with no spaces around it', () {
      final url = WeatherRules.searchUrl('  New York ');
      expect(url.host, 'geocoding-api.open-meteo.com');
      expect(url.queryParameters['name'], 'New York');
    });

    test('the key of a place', () {
      expect(WeatherRules.placeKey(null), 'here');
      expect(
        WeatherRules.placeKey(
          const WeatherPlace(
            name: 'Oslo',
            latitude: 59.91273,
            longitude: 10.74609,
          ),
        ),
        '59.91,10.75',
      );
    });
  });

  test('a forecast is fresh for one hour', () {
    final at = DateTime.utc(2026, 10, 20, 8);
    expect(WeatherRules.isFresh(at, at), isTrue);
    expect(
      WeatherRules.isFresh(at, at.add(const Duration(minutes: 59))),
      isTrue,
    );
    expect(WeatherRules.isFresh(at, at.add(const Duration(hours: 1))), isFalse);
    // A clock that went back.
    expect(
      WeatherRules.isFresh(at, at.subtract(const Duration(minutes: 1))),
      isFalse,
    );
  });

  group('saved forms', () {
    test('a forecast comes back the same', () {
      final forecast = WeatherForecast(
        placeKey: 'here',
        fetched: DateTime.utc(2026, 10, 20, 8, 30),
        days: WeatherRules.parseForecast(openMeteo()),
      );
      final back = WeatherForecast.fromJson(forecast.toJson())!;
      expect(back.placeKey, 'here');
      expect(back.fetched, forecast.fetched);
      expect(back.days, forecast.days);
    });

    test('a damaged forecast or place is null', () {
      expect(WeatherForecast.fromJson('rain'), isNull);
      expect(
        WeatherForecast.fromJson({
          'place': 'here',
          'fetched': 'x',
          'days': <Object>[],
        }),
        isNull,
      );
      expect(WeatherPlace.fromJson({'name': 'Oslo'}), isNull);
    });

    test('a place comes back the same', () {
      const oslo = WeatherPlace(
        name: 'Oslo',
        region: 'Norway',
        latitude: 59.91,
        longitude: 10.75,
      );
      final back = WeatherPlace.fromJson(oslo.toJson())!;
      expect(
        (back.label, back.latitude, back.longitude),
        ('Oslo, Norway', 59.91, 10.75),
      );
    });
  });
}
