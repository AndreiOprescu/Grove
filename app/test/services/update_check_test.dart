import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// A small web server on this computer that answers like GitHub.
Future<HttpServer> fakeGitHub(
  int status,
  Object? body, {
  List<HttpHeaders>? seen,
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  addTearDown(() => server.close(force: true));
  server.listen((request) {
    seen?.add(request.headers);
    request.response
      ..statusCode = status
      ..write(body is String ? body : jsonEncode(body));
    request.response.close();
  });
  return server;
}

Uri at(HttpServer s) => Uri.parse('http://127.0.0.1:${s.port}/latest');

void main() {
  group('GitHubReleaseSource', () {
    test('reads the newest release, and says who asks', () async {
      final seen = <HttpHeaders>[];
      final server = await fakeGitHub(200, {
        'tag_name': 'v1.4.0',
        'html_url':
            'https://github.com/AndreiOprescu/Grove/releases/tag/v1.4.0',
        'assets': <Object>[],
      }, seen: seen);
      final r = await GitHubReleaseSource(url: at(server)).latest();
      expect('${r!.version}', '1.4.0');
      expect(seen.single.value('user-agent'), startsWith('Grove/'));
      expect(seen.single.value('accept'), 'application/vnd.github+json');
    });

    test('no release yet (404) is no release', () async {
      final server = await fakeGitHub(404, {'message': 'Not Found'});
      expect(await GitHubReleaseSource(url: at(server)).latest(), isNull);
    });

    test('another error or a broken answer throws', () async {
      final busy = await fakeGitHub(403, {'message': 'rate limit'});
      await expectLater(
        GitHubReleaseSource(url: at(busy)).latest(),
        throwsA(isA<HttpException>()),
      );
      final broken = await fakeGitHub(200, 'not json');
      await expectLater(
        GitHubReleaseSource(url: at(broken)).latest(),
        throwsA(isA<FormatException>()),
      );
    });

    test('the real address is the newest release of Grove', () {
      expect(
        '${GitHubReleaseSource().url}',
        'https://api.github.com/repos/AndreiOprescu/Grove/releases/latest',
      );
    });
  });

  group('UpdateSchedule', () {
    test('asks at start, and again when it checks', () async {
      final source = FakeReleases(release('99.0.0'));
      final store = AppStore(
        repos: Repos(Database.inMemory()),
        releaseSource: source,
      );
      addTearDown(store.dispose);
      final schedule = UpdateSchedule(store);
      addTearDown(schedule.dispose);
      schedule.start();
      await pumpEventQueue();
      expect(source.asked, 1);
      expect(store.availableUpdate, isNotNull);
      schedule.check();
      await pumpEventQueue();
      expect(source.asked, 2);
      expect(UpdateSchedule(store).every, const Duration(hours: 6));
    });
  });
}
