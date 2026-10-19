import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../state/state.dart';

/// Asks GitHub for the newest release of Grove. No package: the HTTP client
/// of Dart. GitHub answers 60 questions an hour to one address with no
/// login; Grove asks a few times a day.
class GitHubReleaseSource implements ReleaseSource {
  GitHubReleaseSource({Uri? url, this.timeout = const Duration(seconds: 10)})
    : url = url ?? UpdateRules.latestUrl;

  final Uri url;
  final Duration timeout;

  @override
  Future<ReleaseInfo?> latest() async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client.getUrl(url).timeout(timeout);
      // GitHub turns away a question with no name of the app.
      request.headers
        ..set(HttpHeaders.userAgentHeader, 'Grove/${GroveCore.version}')
        ..set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      final response = await request.close().timeout(timeout);
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(timeout);
      // No release yet.
      if (response.statusCode == HttpStatus.notFound) return null;
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('GitHub answered ${response.statusCode}', uri: url);
      }
      final json = jsonDecode(body);
      if (json is! Map<String, Object?>) {
        throw const FormatException('The answer of GitHub is not a release');
      }
      return ReleaseInfo.fromGitHub(json);
    } finally {
      client.close(force: true);
    }
  }
}

/// Checks for a newer Grove at start and every few hours while Grove stays
/// open. The store does nothing when the setting is off.
class UpdateSchedule {
  UpdateSchedule(this.store, {this.every = const Duration(hours: 6)});

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
    unawaited(store.checkForUpdates());
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
