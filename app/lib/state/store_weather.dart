part of 'app_store.dart';

/// What the weather check holds in this run of the app.
class _WeatherState {
  /// The last forecast. Read from the settings at the first look.
  WeatherForecast? forecast;
  bool loaded = false;
  bool checking = false;

  /// Why the last check of "My location" found no position.
  LocationProblem? problem;
}

/// The weather at the top of each day of the Planner and of the Today
/// screen (owner's choice of 2026-10-20): the kind of the day and the
/// temperature at 9am and 9pm, from Open-Meteo. The place is the position
/// of this device, or a town picked in Settings. The settings and the last
/// forecast are of this device: they do not sync.
/// `services/weather_check.dart` asks at start and every hour.
extension AppStoreWeather on AppStore {
  static const _onKey = 'weather.on';
  static const _placeKey = 'weather.place';
  static const _unitKey = 'weather.unit';
  static const _forecastKey = 'weather.forecast';

  /// False in a copy with no [AppStore.weatherSource]: no weather and no
  /// setting.
  bool get canShowWeather => weatherSource != null;

  /// The setting "Show the weather". On by default.
  bool get showsWeather => prefs.getBool(_onKey) ?? true;
  set showsWeather(bool on) {
    prefs.set(_onKey, on);
    _changed();
    if (on) unawaited(refreshWeather());
  }

  /// The town picked in Settings. Null: the position of this device.
  WeatherPlace? get weatherPlace {
    final saved = prefs.getString(_placeKey);
    if (saved == null) return null;
    try {
      return WeatherPlace.fromJson(jsonDecode(saved));
    } on FormatException {
      return null;
    }
  }

  set weatherPlace(WeatherPlace? place) {
    prefs.set(_placeKey, place == null ? null : jsonEncode(place.toJson()));
    // The old forecast is of the old place.
    _setForecast(null);
    _weather.problem = null;
    _changed();
    unawaited(refreshWeather());
  }

  TemperatureUnit get temperatureUnit =>
      TemperatureUnit.fromSaved(prefs.getString(_unitKey));
  set temperatureUnit(TemperatureUnit unit) {
    prefs.set(_unitKey, unit.name);
    _changed();
  }

  /// Why "My location" gives no weather, or null.
  LocationProblem? get weatherProblem =>
      weatherPlace == null ? _weather.problem : null;

  WeatherForecast? get _forecast {
    if (!_weather.loaded) {
      _weather.loaded = true;
      final saved = prefs.getString(_forecastKey);
      if (saved != null) {
        try {
          _weather.forecast = WeatherForecast.fromJson(jsonDecode(saved));
        } on FormatException {
          _weather.forecast = null;
        }
      }
    }
    return _weather.forecast;
  }

  void _setForecast(WeatherForecast? forecast) {
    _weather
      ..loaded = true
      ..forecast = forecast;
    prefs.set(
      _forecastKey,
      forecast == null ? null : jsonEncode(forecast.toJson()),
    );
  }

  /// The weather of [day], or null: weather off, a day in the past, a day
  /// after the forecast, or no forecast of the place yet. The last
  /// forecast still shows when Grove cannot reach Open-Meteo.
  DayWeather? weatherFor(DayKey day) {
    if (!canShowWeather || !showsWeather) return null;
    if (day < clockToday) return null;
    final forecast = _forecast;
    if (forecast == null) return null;
    if (forecast.placeKey != WeatherRules.placeKey(weatherPlace)) return null;
    return forecast.days[day];
  }

  /// Asks Open-Meteo for the forecast. Nothing when the setting is off, or
  /// when the last forecast is less than an hour old (unless [force]). An
  /// error says nothing: the last forecast stays.
  Future<void> refreshWeather({bool force = false}) async {
    final source = weatherSource;
    if (source == null || !showsWeather || _weather.checking) return;
    final place = weatherPlace;
    final key = WeatherRules.placeKey(place);
    final last = _forecast;
    if (!force &&
        last != null &&
        last.placeKey == key &&
        WeatherRules.isFresh(last.fetched, clockNow())) {
      return;
    }
    _weather.checking = true;
    try {
      double latitude, longitude;
      if (place != null) {
        latitude = place.latitude;
        longitude = place.longitude;
      } else {
        final answer =
            await locationSource?.here() ??
            const LocationAnswer.problem(LocationProblem.failed);
        if (isDisposed) return;
        final problem = answer.problem;
        _weather.problem = problem;
        if (problem != null) {
          _changed();
          return;
        }
        latitude = answer.latitude!;
        longitude = answer.longitude!;
      }
      final days = await source.forecast(latitude, longitude);
      if (isDisposed) return;
      // The place changed while Open-Meteo answered.
      if (WeatherRules.placeKey(weatherPlace) != key) return;
      _setForecast(
        WeatherForecast(placeKey: key, fetched: clockNow().toUtc(), days: days),
      );
      _changed();
    } on Object {
      // No internet, or a bad answer. Keep the last forecast.
    } finally {
      _weather.checking = false;
    }
  }

  /// The towns with this name, for the town search of Settings. Throws when
  /// Grove cannot reach Open-Meteo.
  Future<List<WeatherPlace>> searchWeatherPlaces(String name) async {
    final source = weatherSource;
    if (source == null || name.trim().length < 2) return const [];
    return source.search(name);
  }
}
