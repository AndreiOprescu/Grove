import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:geolocator/geolocator.dart';

import '../core/model/day_key.dart';
import '../state/state.dart';

/// Asks Open-Meteo for the forecast and for towns. No key and no login.
/// Free for use that is not commercial; the data is under CC BY 4.0, so
/// Settings names Open-Meteo. No package: the HTTP client of Dart.
class OpenMeteoSource implements WeatherSource {
  OpenMeteoSource({this.timeout = const Duration(seconds: 10)});

  final Duration timeout;

  Future<Map<String, Object?>> _get(Uri url) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client.getUrl(url).timeout(timeout);
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'Grove/${GroveCore.version}',
      );
      final response = await request.close().timeout(timeout);
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(timeout);
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'Open-Meteo answered ${response.statusCode}',
          uri: url,
        );
      }
      final json = jsonDecode(body);
      if (json is! Map<String, Object?>) {
        throw const FormatException('The answer of Open-Meteo is not a map');
      }
      return json;
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<Map<DayKey, DayWeather>> forecast(
    double latitude,
    double longitude,
  ) async => WeatherRules.parseForecast(
    await _get(WeatherRules.forecastUrl(latitude, longitude)),
  );

  @override
  Future<List<WeatherPlace>> search(String name) async =>
      WeatherRules.parseSearch(await _get(WeatherRules.searchUrl(name)));
}

/// The position of this device from its system. Low accuracy is enough for
/// the weather: on Android it is the "approximate" position.
class DeviceLocationSource implements LocationSource {
  const DeviceLocationSource({this.timeout = const Duration(seconds: 15)});

  final Duration timeout;

  @override
  Future<LocationAnswer> here() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const LocationAnswer.problem(LocationProblem.off);
      }
      var leave = await Geolocator.checkPermission();
      if (leave == LocationPermission.denied) {
        leave = await Geolocator.requestPermission();
      }
      if (leave == LocationPermission.denied ||
          leave == LocationPermission.deniedForever) {
        return const LocationAnswer.problem(LocationProblem.denied);
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: timeout,
        ),
      );
      return LocationAnswer.at(position.latitude, position.longitude);
    } on Object {
      // A late answer, or a system with no location. The last known
      // position is good enough for the weather.
      try {
        final last = await Geolocator.getLastKnownPosition();
        if (last != null) {
          return LocationAnswer.at(last.latitude, last.longitude);
        }
      } on Object {
        // None either.
      }
      return const LocationAnswer.problem(LocationProblem.failed);
    }
  }
}

/// Asks for the forecast at start and every hour while Grove stays open.
/// The store does nothing when the setting is off or the forecast is new.
class WeatherSchedule {
  WeatherSchedule(this.store, {this.every = WeatherRules.refreshEvery});

  final AppStore store;
  final Duration every;
  Timer? _timer;

  void start() {
    if (_timer != null) return;
    _timer = Timer.periodic(every, (_) => check());
    check();
  }

  void check() {
    if (store.isDisposed) return;
    unawaited(store.refreshWeather());
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
