// The parts of the sync that the screens place (F10, asked by Track A): the
// sync card in Settings, the question of the first login over each screen,
// and the small sync mark in the top bar.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/ui/settings/sync_mark.dart';

import '../auth/auth_support.dart'
    show
        FirstSyncChoices,
        SyncCard,
        World,
        fillAccount,
        fixLastSync,
        idle,
        makeStore,
        me,
        settle,
        signInWithCard,
        stillDevice;
import 'settings_support.dart';

final _mark = find.byType(SyncMark);
final _markIcon = find.descendant(of: _mark, matching: find.byType(Icon));
final _dialog = find.byKey(const ValueKey('first-sync-dialog'));

void main() {
  testWidgets('a copy with no sync: the card says so, and no mark', (
    tester,
  ) async {
    final store = plannerStore();
    await openSettings(tester, store, tab: SettingsTab.sync);
    expect(inSettings(find.byType(SyncCard)), findsOneWidget);
    expect(
      inSettings(
        find.text(
          'This copy of Grove has no sync. Your data stays on this device.',
        ),
      ),
      findsOneWidget,
    );
    expect(_markIcon, findsNothing);
  });

  testWidgets('the login in Settings works, and the mark follows', (
    tester,
  ) async {
    final d = stillDevice(World());
    d.store.screen = Screen.planner;
    await pumpApp(tester, d.store);
    expect(_markIcon, findsOneWidget);
    expect(
      tester.getSemantics(_mark),
      matchesSemantics(
        label: 'Sync',
        tooltip: 'Not signed in.',
        isButton: true,
        hasSelectedState: true,
        hasTapAction: true,
      ),
    );
    expect(tester.widget<Icon>(_markIcon).icon, Icons.cloud_off_outlined);

    // A tap on the mark opens Settings on the Sync tab.
    await tester.tap(_mark);
    await tester.pumpAndSettle();
    expect(inSettings(find.byType(SyncCard)), findsOneWidget);

    await signInWithCard(tester, d, me);
    expect(d.store.syncStatus, SyncStatus.upToDate);
    expect(inSettings(find.byKey(SyncCard.syncNowKey)), findsOneWidget);
    expect(tester.widget<Icon>(_markIcon).icon, Icons.cloud_done_outlined);
  });

  testWidgets('the mark shows an error', (tester) async {
    final world = World();
    final d = stillDevice(world, signedIn: me);
    d.store.screen = Screen.planner;
    await idle(d.store);
    fixLastSync(d.store);
    world.of(me).failure = Exception('no network');
    d.store.quickAdd('One');
    await d.store.syncNow();
    await idle(d.store);
    expect(d.store.syncStatus, SyncStatus.error);
    await pumpApp(tester, d.store);
    expect(tester.widget<Icon>(_markIcon).icon, Icons.sync_problem);
    await settle(tester);
  });

  testWidgets('the question of the first login opens over the screens', (
    tester,
  ) async {
    final world = World();
    await fillAccount(world, me);
    final d = stillDevice(world);
    d.store
      ..screen = Screen.planner
      ..quickAdd('From the phone');
    await pumpApp(tester, d.store);
    await tester.tap(_mark);
    await tester.pumpAndSettle();
    expect(_dialog, findsNothing);
    await signInWithCard(tester, d, me);
    expect(_dialog, findsOneWidget);

    await tester.tap(
      find.descendant(
        of: _dialog,
        matching: find.byKey(FirstSyncChoices.useAccountKey),
      ),
    );
    await settle(tester);
    expect(_dialog, findsNothing);
    expect(d.store.firstSyncQuestion, isFalse);
    // Settings is still open under the question.
    expect(settingsView, findsOneWidget);
  });

  testWidgets('the question opens with no Settings window too', (tester) async {
    final world = World();
    await fillAccount(world, me);
    final d = stillDevice(world);
    d.store
      ..screen = Screen.garden
      ..quickAdd('From the phone');
    await pumpApp(tester, d.store);
    expect(_dialog, findsNothing);
    expect(await d.store.sendLoginLink(me), isTrue);
    expect(await d.store.verifyLoginCode(d.auth.code), isTrue);
    await settle(tester);
    expect(d.store.firstSyncQuestion, isTrue);
    expect(_dialog, findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('first-sync-later')));
    await settle(tester);
    expect(_dialog, findsNothing);
  });

  // Q-18 of `docs/questions.md`, the answer of the owner: Import is blocked
  // while the person is signed in to sync, and works when signed out.
  group('Import and the sync', () {
    const blocked =
        'Import is off while you are signed in to sync. Sign out first '
        '(Settings, Sync), then import.';
    final blockedLine = keyed('settings-import-blocked');
    final question = find.text('Replace everything in Grove?');

    /// The file of another Grove, with one task.
    String otherFile() {
      final other = makeStore();
      other.quickAdd('From the file');
      return other.exportData();
    }

    Set<String> titles(AppStore s) => {
      for (final t in s.repos.tasks.all()) t.title,
    };

    FakeFiles picks() =>
        FakeFiles()..picked = (name: 'old.json', text: otherFile());

    testWidgets('signed in: Import is blocked, and Grove says why', (
      tester,
    ) async {
      final d = stillDevice(World(), signedIn: me);
      d.store
        ..screen = Screen.planner
        ..quickAdd('Mine');
      await idle(d.store);
      final files = picks();
      await pumpApp(tester, d.store, files: files);
      await pressSettingsKey(tester);
      await showTab(tester, SettingsTab.data);
      expect(d.store.isSignedIn, isTrue);
      expect(tester.widget<Text>(blockedLine).data, blocked);

      // The button is there, grey, and a tap does nothing.
      expect(keyed('settings-import'), findsOneWidget);
      expect(
        tester.getSemantics(keyed('settings-import-off')),
        matchesSemantics(
          label: 'Import JSON…',
          isButton: true,
          hasEnabledState: true,
          isEnabled: false,
        ),
      );
      await tester.ensureVisible(keyed('settings-import'));
      await tester.pumpAndSettle();
      await tester.tap(keyed('settings-import'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(files.opened, 0);
      expect(question, findsNothing);
      expect(titles(d.store), {'Mine'});

      // Export is free.
      await tapIn(tester, keyed('settings-export'));
      expect(files.saved, hasLength(1));
      await settle(tester);
    });

    testWidgets('signed out: Import asks its question', (tester) async {
      final d = stillDevice(World());
      d.store
        ..screen = Screen.planner
        ..quickAdd('Mine');
      final files = picks();
      await pumpApp(tester, d.store, files: files);
      await pressSettingsKey(tester);
      await showTab(tester, SettingsTab.data);
      expect(d.store.syncStatus, SyncStatus.signedOut);
      expect(blockedLine, findsNothing);
      await tapIn(tester, keyed('settings-import'));
      expect(files.opened, 1);
      expect(question, findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      expect(titles(d.store), {'Mine'});
    });

    testWidgets('after a sign-out Import is free again', (tester) async {
      final d = stillDevice(World(), signedIn: me);
      d.store.screen = Screen.planner;
      await idle(d.store);
      final files = picks();
      await pumpApp(tester, d.store, files: files);
      await pressSettingsKey(tester);
      await showTab(tester, SettingsTab.data);
      expect(blockedLine, findsOneWidget);

      await d.store.signOut();
      await settle(tester);
      expect(d.store.isSignedIn, isFalse);
      expect(blockedLine, findsNothing);
      await tapIn(tester, keyed('settings-import'));
      expect(files.opened, 1);
      expect(question, findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await settle(tester);
    });

    testWidgets('a login while the file window is open: nothing is replaced', (
      tester,
    ) async {
      final d = stillDevice(World());
      d.store
        ..screen = Screen.planner
        ..quickAdd('Mine');
      final files = picks()
        ..whileOpen = () async {
          expect(await d.store.sendLoginLink(me), isTrue);
          expect(await d.store.verifyLoginCode(d.auth.code), isTrue);
        };
      await pumpApp(tester, d.store, files: files);
      await pressSettingsKey(tester);
      await showTab(tester, SettingsTab.data);
      await tapIn(tester, keyed('settings-import'));
      await settle(tester);
      expect(d.store.isSignedIn, isTrue);
      expect(files.opened, 1);
      expect(question, findsNothing);
      expect(
        tester.widget<Text>(keyed('settings-data-message')).data,
        'You are signed in to sync. Sign out first, then import. Nothing '
        'was changed.',
      );
      expect(titles(d.store), {'Mine'});
      expect(blockedLine, findsOneWidget);
    });
  });
}
