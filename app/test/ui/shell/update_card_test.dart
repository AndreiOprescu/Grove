// The card of a new Grove: it shows over every screen when GitHub has a
// newer version, and its buttons open the file, open the page, or hide it.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/ui/store_app.dart';

import '../planner/planner_support.dart';

const _card = ValueKey('update-card');
const _download = ValueKey('update-download');

ReleaseInfo _allFiles(String version) {
  const base = 'https://github.com/AndreiOprescu/Grove/releases/download';
  return ReleaseInfo(
    version: AppVersion.parse(version)!,
    pageUrl: 'https://github.com/AndreiOprescu/Grove/releases/tag/v$version',
    files: {
      for (final name in [
        'grove-macos.zip',
        'grove-windows.zip',
        'grove-android.apk',
      ])
        name: '$base/v$version/$name',
    },
  );
}

/// A store whose GitHub has 9.9.9, after the first check.
Future<AppStore> _storeWithUpdate() async {
  final store = makeStore(
    prefs: MemoryPrefs()..set('appearance.motion', false),
    releases: FakeReleases(_allFiles('9.9.9')),
  );
  await store.checkForUpdates();
  return store;
}

Future<List<Uri>> _pump(
  WidgetTester tester,
  AppStore store, {
  Size size = desktopSize,
  bool opens = true,
}) async {
  final opened = <Uri>[];
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    StoreApp(
      key: UniqueKey(),
      store: store,
      openLink: (url) async {
        opened.add(url);
        return opens;
      },
    ),
  );
  addTearDown(() => tester.pumpWidget(const SizedBox()));
  await tester.pumpAndSettle();
  return opened;
}

void main() {
  testWidgets('no card when GitHub has nothing newer', (tester) async {
    final store = makeStore(
      prefs: MemoryPrefs()..set('appearance.motion', false),
      releases: FakeReleases(_allFiles(GroveCore.version)),
    );
    await store.checkForUpdates();
    await _pump(tester, store);
    expect(find.byKey(_card), findsNothing);
  });

  testWidgets(
    'a newer Grove shows the card; Update opens the file of this '
    'device',
    (tester) async {
      final store = await _storeWithUpdate();
      final opened = await _pump(tester, store);
      expect(find.byKey(_card), findsOneWidget);
      expect(find.text('Grove 9.9.9 is here'), findsOneWidget);
      await tester.tap(find.byKey(_download));
      await tester.pumpAndSettle();
      final file = defaultTargetPlatform == TargetPlatform.windows
          ? 'grove-windows.zip'
          : 'grove-macos.zip';
      expect(opened.single.pathSegments.last, file);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.macOS,
      TargetPlatform.windows,
    }),
  );

  testWidgets("What's new opens the page of the release", (tester) async {
    final store = await _storeWithUpdate();
    final opened = await _pump(tester, store);
    await tester.tap(find.byKey(const ValueKey('update-notes')));
    await tester.pumpAndSettle();
    expect(
      opened.single.toString(),
      'https://github.com/AndreiOprescu/Grove/releases/tag/v9.9.9',
    );
  });

  testWidgets('a link that does not open says so', (tester) async {
    final store = await _storeWithUpdate();
    await _pump(tester, store, opens: false);
    await tester.tap(find.byKey(const ValueKey('update-notes')));
    await tester.pump();
    expect(store.toast, 'Grove could not open the link.');
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('Later hides the card', (tester) async {
    final store = await _storeWithUpdate();
    await _pump(tester, store);
    await tester.tap(find.byKey(const ValueKey('update-later')));
    await tester.pumpAndSettle();
    expect(find.byKey(_card), findsNothing);
    expect(store.prefs.getString('updates.skipped'), isNull);
  });

  testWidgets('Skip hides the card and keeps the version', (tester) async {
    final store = await _storeWithUpdate();
    await _pump(tester, store);
    await tester.tap(find.byKey(const ValueKey('update-skip')));
    await tester.pumpAndSettle();
    expect(find.byKey(_card), findsNothing);
    expect(store.prefs.getString('updates.skipped'), '9.9.9');
  });

  testWidgets('on a phone the card fits with a gutter of 16 points', (
    tester,
  ) async {
    final store = await _storeWithUpdate();
    final opened = await _pump(tester, store, size: phoneSize);
    await tester.tap(find.byKey(_download));
    await tester.pumpAndSettle();
    expect(opened.single.pathSegments.last, 'grove-android.apk');
    final box = tester.getRect(find.byKey(_card));
    expect(box.left, greaterThanOrEqualTo(16));
    expect(box.right, lessThanOrEqualTo(phoneSize.width - 16));
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('iOS has no file: no Update, only the page', (tester) async {
    final store = await _storeWithUpdate();
    await _pump(tester, store, size: phoneSize);
    expect(find.byKey(_card), findsOneWidget);
    expect(find.byKey(_download), findsNothing);
    expect(find.byKey(const ValueKey('update-notes')), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
}
