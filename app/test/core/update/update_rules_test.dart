import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:grove/core/grove_core.dart';
import 'package:grove/core/update/update_rules.dart';

Map<String, Object?> gitHub({
  String tag = 'v1.2.0',
  bool draft = false,
  bool prerelease = false,
  List<String> files = const ['grove-macos.zip', 'grove-android.apk'],
}) => {
  'tag_name': tag,
  'html_url': 'https://github.com/AndreiOprescu/Grove/releases/tag/$tag',
  'body': 'Deadlines.',
  'draft': draft,
  'prerelease': prerelease,
  'assets': [
    for (final name in files)
      {
        'name': name,
        'browser_download_url':
            'https://github.com/AndreiOprescu/Grove/releases/download/$tag/$name',
      },
  ],
};

void main() {
  group('AppVersion', () {
    test('reads 1.2.3, v1.2.3 and 1.2.3+4', () {
      expect(AppVersion.parse('1.2.3'), const AppVersion(1, 2, 3));
      expect(AppVersion.parse('v1.2.3'), const AppVersion(1, 2, 3));
      expect(AppVersion.parse('1.2.3+4'), const AppVersion(1, 2, 3));
      expect(AppVersion.parse(' v1.2.3 '), const AppVersion(1, 2, 3));
      expect('${AppVersion.parse('v1.2.3')}', '1.2.3');
    });

    test('a test build or a bad name is no version', () {
      expect(AppVersion.parse('1.2.3-beta'), isNull);
      expect(AppVersion.parse('1.2'), isNull);
      expect(AppVersion.parse('latest'), isNull);
      expect(AppVersion.parse(''), isNull);
    });

    test('compares number by number', () {
      final v = AppVersion.parse;
      expect(v('1.10.0')! > v('1.9.0')!, isTrue);
      expect(v('2.0.0')! > v('1.99.99')!, isTrue);
      expect(v('1.0.1')! > v('1.0.0')!, isTrue);
      expect(v('1.0.0')! > v('1.0.0')!, isFalse);
      expect(v('1.0.0')! > v('1.0.1')!, isFalse);
    });

    test('the version of the app is the one in pubspec.yaml', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final line = RegExp(
        r'^version:\s*(\S+)',
        multiLine: true,
      ).firstMatch(pubspec)!;
      expect(AppVersion.parse(line.group(1)!), isNotNull);
      expect(
        AppVersion.parse(GroveCore.version),
        AppVersion.parse(line.group(1)!),
        reason: 'Change GroveCore.version with the version in pubspec.yaml',
      );
    });
  });

  group('ReleaseInfo.fromGitHub', () {
    test('reads the version, the page, the words and the files', () {
      final r = ReleaseInfo.fromGitHub(gitHub())!;
      expect(r.version, const AppVersion(1, 2, 0));
      expect(
        r.pageUrl,
        'https://github.com/AndreiOprescu/Grove/releases/tag/v1.2.0',
      );
      expect(r.notes, 'Deadlines.');
      expect(r.files.keys, ['grove-macos.zip', 'grove-android.apk']);
    });

    test('a draft, a test build or a bad tag is no release', () {
      expect(ReleaseInfo.fromGitHub(gitHub(draft: true)), isNull);
      expect(ReleaseInfo.fromGitHub(gitHub(prerelease: true)), isNull);
      expect(ReleaseInfo.fromGitHub(gitHub(tag: 'nightly')), isNull);
      expect(ReleaseInfo.fromGitHub(const {}), isNull);
    });

    test('a page that is not on GitHub is not kept', () {
      final json = gitHub()..['html_url'] = 'https://evil.example/x';
      expect(ReleaseInfo.fromGitHub(json), isNull);
    });

    test('a file that is not on GitHub is left out', () {
      final json = gitHub();
      (json['assets']! as List).add({
        'name': 'grove-windows.zip',
        'browser_download_url': 'http://evil.example/grove-windows.zip',
      });
      final r = ReleaseInfo.fromGitHub(json)!;
      expect(r.downloadFor(UpdatePlatform.windows), isNull);
    });
  });

  group('downloadFor', () {
    test('each system gets its own file', () {
      final r = ReleaseInfo.fromGitHub(
        gitHub(
          files: [
            'grove-macos.zip',
            'grove-windows.zip',
            'grove-android.apk',
            'grove-android.aab',
          ],
        ),
      )!;
      expect(r.downloadFor(UpdatePlatform.macos), endsWith('grove-macos.zip'));
      expect(
        r.downloadFor(UpdatePlatform.windows),
        endsWith('grove-windows.zip'),
      );
      expect(
        r.downloadFor(UpdatePlatform.android),
        endsWith('grove-android.apk'),
      );
      expect(r.downloadFor(UpdatePlatform.ios), isNull);
      expect(r.downloadFor(UpdatePlatform.other), isNull);
    });

    test('a release with no file for this system has none', () {
      final r = ReleaseInfo.fromGitHub(gitHub(files: ['grove-macos.zip']))!;
      expect(r.downloadFor(UpdatePlatform.windows), isNull);
    });
  });

  group('UpdateRules.isNew', () {
    final r = ReleaseInfo.fromGitHub(gitHub(tag: 'v1.2.0'))!;
    const v = AppVersion.new;

    test('only a newer version is new', () {
      expect(UpdateRules.isNew(r, current: v(1, 0, 0)), isTrue);
      expect(UpdateRules.isNew(r, current: v(1, 2, 0)), isFalse);
      expect(UpdateRules.isNew(r, current: v(1, 3, 0)), isFalse);
    });

    test('a skipped version is not new; a later one is', () {
      expect(
        UpdateRules.isNew(r, current: v(1, 0, 0), skipped: v(1, 2, 0)),
        isFalse,
      );
      expect(
        UpdateRules.isNew(r, current: v(1, 0, 0), skipped: v(1, 1, 0)),
        isTrue,
      );
    });
  });
}
