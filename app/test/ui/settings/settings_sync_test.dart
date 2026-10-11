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
}
