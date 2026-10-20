import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

// The update check in the store: Grove asks GitHub for the newest release,
// and the card shows it when it is newer than this copy (GroveCore.version).

void main() {
  group('UpdateStore', () {
    test('a newer release is shown', () async {
      final s = makeStore(releases: FakeReleases(release('99.0.0')));
      expect(s.availableUpdate, isNull);
      await s.checkForUpdates();
      expect(s.availableUpdate?.version, AppVersion.parse('99.0.0'));
      expect(s.currentVersion, AppVersion.parse(GroveCore.version));
    });

    test('the same or an older release is not shown', () async {
      final source = FakeReleases(release(GroveCore.version));
      final s = makeStore(releases: source);
      await s.checkForUpdates();
      expect(s.availableUpdate, isNull);
      source.release = release('0.0.1');
      await s.checkForUpdates();
      expect(s.availableUpdate, isNull);
    });

    test('Later hides the card until the next start', () async {
      final prefs = MemoryPrefs();
      final s = makeStore(
        prefs: prefs,
        releases: FakeReleases(release('99.0.0')),
      );
      await s.checkForUpdates();
      s.laterUpdate();
      expect(s.availableUpdate, isNull);
      // A check of the timer does not bring it back.
      await s.checkForUpdates();
      expect(s.availableUpdate, isNull);
      // A new start does.
      final next = makeStore(
        prefs: prefs,
        releases: FakeReleases(release('99.0.0')),
      );
      await next.checkForUpdates();
      expect(next.availableUpdate, isNotNull);
    });

    test('Skip hides this version for good, but not a newer one', () async {
      final prefs = MemoryPrefs();
      final source = FakeReleases(release('99.0.0'));
      final s = makeStore(prefs: prefs, releases: source);
      await s.checkForUpdates();
      s.skipUpdate();
      expect(s.availableUpdate, isNull);
      expect(prefs.getString('updates.skipped'), '99.0.0');
      final next = makeStore(prefs: prefs, releases: source);
      await next.checkForUpdates();
      expect(next.availableUpdate, isNull);
      source.release = release('99.1.0');
      await next.checkForUpdates();
      expect(next.availableUpdate?.version, AppVersion.parse('99.1.0'));
    });

    test('with the switch off, the timer does not ask GitHub', () async {
      final source = FakeReleases(release('99.0.0'));
      final s = makeStore(releases: source);
      expect(s.checksForUpdates, isTrue);
      s.checksForUpdates = false;
      expect(s.prefs.getBool('updates.check'), isFalse);
      await s.checkForUpdates();
      expect(source.asked, 0);
      expect(s.availableUpdate, isNull);
      // A check by hand still asks.
      await s.checkForUpdates(manual: true);
      expect(source.asked, 1);
      expect(s.availableUpdate, isNotNull);
    });

    test('a check by hand says what it found', () async {
      final source = FakeReleases();
      final s = makeStore(releases: source);
      expect(
        await s.checkForUpdates(manual: true),
        'Grove ${GroveCore.version} is the newest version.',
      );
      source.release = release('99.0.0');
      expect(await s.checkForUpdates(manual: true), 'Grove 99.0.0 is here.');
      source.fails = true;
      expect(
        await s.checkForUpdates(manual: true),
        'Grove could not reach GitHub. Try again later.',
      );
      // An error keeps the release found before.
      expect(s.availableUpdate, isNotNull);
    });

    test('a check by hand brings back a skipped or later version', () async {
      final s = makeStore(releases: FakeReleases(release('99.0.0')));
      await s.checkForUpdates();
      s.skipUpdate();
      await s.checkForUpdates(manual: true);
      expect(s.availableUpdate, isNotNull);
      s.laterUpdate();
      await s.checkForUpdates(manual: true);
      expect(s.availableUpdate, isNotNull);
    });

    test('an error of the timer says nothing', () async {
      final source = FakeReleases()..fails = true;
      final s = makeStore(releases: source);
      expect(await s.checkForUpdates(), isNull);
      expect(s.toast, isNull);
    });

    test('a copy with no source has no check', () async {
      final s = makeStore();
      expect(s.canCheckForUpdates, isFalse);
      expect(await s.checkForUpdates(manual: true), isNull);
      expect(s.availableUpdate, isNull);
    });
  });
}
