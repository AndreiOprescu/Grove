import '../model/day_key.dart';

/// The weather of a day, in a few kinds. Open-Meteo gives a WMO code
/// (https://open-meteo.com/en/docs, "WMO Weather interpretation codes").
enum WeatherCondition {
  clear('☀️', 'Clear'),
  mostlyClear('🌤️', 'Mostly clear'),
  partlyCloudy('⛅', 'Partly cloudy'),
  cloudy('☁️', 'Cloudy'),
  fog('🌫️', 'Fog'),
  drizzle('🌦️', 'Drizzle'),
  rain('🌧️', 'Rain'),
  snow('🌨️', 'Snow'),
  thunder('⛈️', 'Thunderstorm');

  const WeatherCondition(this.emoji, this.words);

  final String emoji;
  final String words;

  /// The kind of a WMO code. A code that is not in the list counts as
  /// cloudy.
  static WeatherCondition fromCode(int code) => switch (code) {
    0 => clear,
    1 => mostlyClear,
    2 => partlyCloudy,
    3 => cloudy,
    45 || 48 => fog,
    51 || 53 || 55 || 56 || 57 => drizzle,
    61 || 63 || 65 || 66 || 67 || 80 || 81 || 82 => rain,
    71 || 73 || 75 || 77 || 85 || 86 => snow,
    95 || 96 || 99 => thunder,
    _ => cloudy,
  };
}

/// How the temperatures show. Grove keeps them in °C.
enum TemperatureUnit {
  celsius('°C'),
  fahrenheit('°F');

  const TemperatureUnit(this.symbol);

  final String symbol;

  /// The saved name of a unit. °C for no name or an unknown one.
  static TemperatureUnit fromSaved(String? name) =>
      name == fahrenheit.name ? fahrenheit : celsius;

  /// [celsius] in this unit, to the whole degree.
  int whole(double celsius) => switch (this) {
    TemperatureUnit.celsius => celsius.round(),
    TemperatureUnit.fahrenheit => (celsius * 9 / 5 + 32).round(),
  };
}

/// The weather of one day: its main kind, and the temperature at 9am and
/// at 9pm, in °C (owner's choice of 2026-10-20). Null for an hour the
/// forecast does not have.
class DayWeather {
  const DayWeather({
    required this.day,
    required this.condition,
    this.morning,
    this.evening,
  });

  final DayKey day;
  final WeatherCondition condition;

  /// At 9am.
  final double? morning;

  /// At 9pm.
  final double? evening;

  Map<String, Object?> toJson() => {
    'day': day.string,
    'condition': condition.name,
    'morning': morning,
    'evening': evening,
  };

  /// Null for a damaged entry.
  static DayWeather? fromJson(Object? json) {
    if (json is! Map) return null;
    final day = DayKey.parse('${json['day']}');
    final condition = WeatherCondition.values
        .where((c) => c.name == json['condition'])
        .firstOrNull;
    if (day == null || condition == null) return null;
    final morning = json['morning'], evening = json['evening'];
    return DayWeather(
      day: day,
      condition: condition,
      morning: morning is num ? morning.toDouble() : null,
      evening: evening is num ? evening.toDouble() : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is DayWeather &&
      other.day == day &&
      other.condition == condition &&
      other.morning == morning &&
      other.evening == evening;

  @override
  int get hashCode => Object.hash(day, condition, morning, evening);
}

/// A town picked in Settings.
class WeatherPlace {
  const WeatherPlace({
    required this.name,
    required this.latitude,
    required this.longitude,
    this.region = '',
  });

  final String name;

  /// The region and the country, for two towns with one name.
  final String region;
  final double latitude;
  final double longitude;

  /// "Paris, Île-de-France, France".
  String get label => region.isEmpty ? name : '$name, $region';

  Map<String, Object?> toJson() => {
    'name': name,
    'region': region,
    'latitude': latitude,
    'longitude': longitude,
  };

  /// Null for a damaged entry.
  static WeatherPlace? fromJson(Object? json) {
    if (json is! Map) return null;
    final name = json['name'], lat = json['latitude'], lon = json['longitude'];
    if (name is! String || lat is! num || lon is! num) return null;
    final region = json['region'];
    return WeatherPlace(
      name: name,
      region: region is String ? region : '',
      latitude: lat.toDouble(),
      longitude: lon.toDouble(),
    );
  }

  /// A place from the town search of Open-Meteo. Null for an entry with no
  /// name or no position.
  static WeatherPlace? fromSearch(Object? json) {
    if (json is! Map) return null;
    final name = json['name'], lat = json['latitude'], lon = json['longitude'];
    if (name is! String || lat is! num || lon is! num) return null;
    // "Bucharest, Romania", not "Bucharest, Bucharest, Romania".
    final parts = <String>[
      for (final k in ['admin1', 'country'])
        if (json[k] is String &&
            (json[k] as String).isNotEmpty &&
            json[k] != name)
          json[k] as String,
    ];
    return WeatherPlace(
      name: name,
      region: parts.join(', '),
      latitude: lat.toDouble(),
      longitude: lon.toDouble(),
    );
  }
}

/// The forecast Grove keeps between two questions to Open-Meteo.
class WeatherForecast {
  const WeatherForecast({
    required this.placeKey,
    required this.fetched,
    required this.days,
  });

  /// [WeatherRules.placeKey] of the place it is for.
  final String placeKey;

  /// When Open-Meteo gave it, in UTC.
  final DateTime fetched;
  final Map<DayKey, DayWeather> days;

  Map<String, Object?> toJson() => {
    'place': placeKey,
    'fetched': fetched.toUtc().toIso8601String(),
    'days': [for (final d in days.values) d.toJson()],
  };

  /// Null for a damaged entry.
  static WeatherForecast? fromJson(Object? json) {
    if (json is! Map) return null;
    final place = json['place'], fetched = json['fetched'];
    final list = json['days'];
    if (place is! String || fetched is! String || list is! List) return null;
    final at = DateTime.tryParse(fetched);
    if (at == null) return null;
    return WeatherForecast(
      placeKey: place,
      fetched: at.toUtc(),
      days: {for (final d in list.map(DayWeather.fromJson).nonNulls) d.day: d},
    );
  }
}

/// Where the forecast comes from. The app asks Open-Meteo
/// (`services/weather_check.dart`); a test gives a fake.
abstract interface class WeatherSource {
  /// The weather of the next days at a position. Throws when the question
  /// does not get an answer.
  Future<Map<DayKey, DayWeather>> forecast(double latitude, double longitude);

  /// The towns with this name. Throws when the question does not get an
  /// answer.
  Future<List<WeatherPlace>> search(String name);
}

/// Why Grove has no position of this device.
enum LocationProblem {
  off('Location is off on this device. Turn it on, or pick a town.'),
  denied('Grove may not use your location. Allow it, or pick a town.'),
  failed('Grove could not find your location. Pick a town.');

  const LocationProblem(this.words);

  /// The words Settings shows.
  final String words;
}

/// A position of this device, or why there is none.
class LocationAnswer {
  const LocationAnswer.at(double this.latitude, double this.longitude)
    : problem = null;
  const LocationAnswer.problem(LocationProblem this.problem)
    : latitude = null,
      longitude = null;

  final double? latitude;
  final double? longitude;
  final LocationProblem? problem;
}

/// The position of this device. The app asks the system
/// (`services/weather_check.dart`); a test gives a fake.
abstract interface class LocationSource {
  /// Asks for leave the first time. Never throws.
  Future<LocationAnswer> here();
}

abstract final class WeatherRules {
  /// Grove asks for a new forecast at most this often.
  static const refreshEvery = Duration(hours: 1);

  /// Open-Meteo gives at most 16 days.
  static const forecastDays = 16;

  /// The hours of the two temperatures.
  static const morningHour = 9;
  static const eveningHour = 21;

  /// The key of the place of a forecast: `here` for the position of this
  /// device, the position of a picked town otherwise.
  static String placeKey(WeatherPlace? place) => place == null
      ? 'here'
      : '${place.latitude.toStringAsFixed(2)},'
            '${place.longitude.toStringAsFixed(2)}';

  /// A position to two places: about one kilometre. Grove sends no more
  /// than that.
  static String coordinate(double value) => value.toStringAsFixed(2);

  static Uri forecastUrl(double latitude, double longitude) =>
      Uri.https('api.open-meteo.com', '/v1/forecast', {
        'latitude': coordinate(latitude),
        'longitude': coordinate(longitude),
        'daily': 'weather_code',
        'hourly': 'temperature_2m',
        'timezone': 'auto',
        'forecast_days': '$forecastDays',
      });

  static Uri searchUrl(String name) => Uri.https(
    'geocoding-api.open-meteo.com',
    '/v1/search',
    {'name': name.trim(), 'count': '8', 'language': 'en', 'format': 'json'},
  );

  /// The days of an answer of `/v1/forecast`. The times are in the zone of
  /// the place (`timezone=auto`). Throws [FormatException] for an answer
  /// with no days.
  static Map<DayKey, DayWeather> parseForecast(Map<String, Object?> json) {
    final daily = json['daily'], hourly = json['hourly'];
    if (daily is! Map || hourly is! Map) {
      throw const FormatException('The answer of Open-Meteo has no days');
    }
    final dayTimes = daily['time'], codes = daily['weather_code'];
    if (dayTimes is! List || codes is! List) {
      throw const FormatException('The answer of Open-Meteo has no days');
    }
    final temps = <String, double>{};
    final hours = hourly['time'], values = hourly['temperature_2m'];
    if (hours is List && values is List) {
      for (var i = 0; i < hours.length && i < values.length; i++) {
        final h = hours[i], v = values[i];
        if (h is String && v is num) temps[h] = v.toDouble();
      }
    }
    String at(DayKey day, int hour) =>
        '${day.string}T${hour.toString().padLeft(2, '0')}:00';
    final out = <DayKey, DayWeather>{};
    for (var i = 0; i < dayTimes.length && i < codes.length; i++) {
      final day = DayKey.parse('${dayTimes[i]}');
      final code = codes[i];
      if (day == null || code is! num) continue;
      out[day] = DayWeather(
        day: day,
        condition: WeatherCondition.fromCode(code.toInt()),
        morning: temps[at(day, morningHour)],
        evening: temps[at(day, eveningHour)],
      );
    }
    return out;
  }

  /// The towns of an answer of `/v1/search`. No `results` means no town.
  static List<WeatherPlace> parseSearch(Map<String, Object?> json) {
    final results = json['results'];
    if (results is! List) return const [];
    return results.map(WeatherPlace.fromSearch).nonNulls.toList();
  }

  /// True while [fetched] is less than [refreshEvery] old. A clock that went
  /// back counts as old.
  static bool isFresh(DateTime fetched, DateTime now) {
    final age = now.toUtc().difference(fetched.toUtc());
    return !age.isNegative && age < refreshEvery;
  }

  static String _degrees(double? celsius, TemperatureUnit unit) =>
      celsius == null ? '–' : '${unit.whole(celsius)}°';

  /// The label of a day: "🌧️ 9° → 14°", 9am then 9pm.
  static String label(DayWeather w, TemperatureUnit unit) {
    if (w.morning == null && w.evening == null) return w.condition.emoji;
    return '${w.condition.emoji} ${_degrees(w.morning, unit)} → '
        '${_degrees(w.evening, unit)}';
  }

  /// The words of the label: "Rain · 9am 9° · 9pm 14°".
  static String words(DayWeather w, TemperatureUnit unit) =>
      '${w.condition.words} · 9am ${_degrees(w.morning, unit)} · '
      '9pm ${_degrees(w.evening, unit)}';
}
