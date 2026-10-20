// The login and the sync card (cross-platform plan F11).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'auth_support.dart';

void main() {
  group('The words of the card', () {
    test('the time of the last sync', () {
      final now = DateTime(2026, 10, 11, 10);
      expect(
        SyncWords.when(DateTime(2026, 10, 11, 9, 5), now),
        'today at 09:05',
      );
      expect(
        SyncWords.when(DateTime(2026, 10, 9, 23, 40), now),
        'on 2026-10-09 at 23:40',
      );
    });

    test('the changes that wait', () {
      expect(SyncWords.waiting(0), isNull);
      expect(SyncWords.waiting(1), '1 change waits for the next sync.');
      expect(SyncWords.waiting(4), '4 changes wait for the next sync.');
    });
  });

  testWidgets('a build with no keys says that there is no sync', (
    tester,
  ) async {
    final store = makeStore(
      prefs: MemoryPrefs()..set('appearance.motion', false),
    );
    await pumpCard(tester, store);
    expect(find.textContaining('has no sync'), findsOneWidget);
    expect(find.byKey(SyncCard.emailKey), findsNothing);
    expect(find.byKey(SyncCard.sendKey), findsNothing);
  });

  testWidgets('the email, the code, then signed in', (tester) async {
    final world = World();
    final d = stillDevice(world);
    await pumpCard(tester, d.store);
    expect(find.byKey(SyncCard.emailKey), findsOneWidget);
    expect(find.byKey(SyncCard.codeKey), findsNothing);

    await signInWithCard(tester, d, me);
    expect(d.auth.sent, [me]);
    expect(d.store.isSignedIn, isTrue);
    expect(find.text('Signed in as $me'), findsOneWidget);
    expect(find.textContaining('Last sync'), findsOneWidget);
    expect(find.byKey(SyncCard.syncNowKey), findsOneWidget);
    expect(find.byKey(SyncCard.signOutKey), findsOneWidget);
    expect(find.byKey(SyncCard.errorKey), findsNothing);
  });

  testWidgets('a text that is not an address shows why, and sends nothing', (
    tester,
  ) async {
    final d = stillDevice(World());
    await pumpCard(tester, d.store);
    await tester.enterText(find.byType(EditableText), 'not an address');
    await tester.tap(find.byKey(SyncCard.sendKey));
    await tester.pumpAndSettle();
    expect(find.byKey(SyncCard.errorKey), findsOneWidget);
    expect(find.text('This is not an email address.'), findsOneWidget);
    expect(d.auth.sent, isEmpty);
    expect(find.byKey(SyncCard.codeKey), findsNothing);
  });

  testWidgets('a wrong code shows why, and "Use another address" goes back', (
    tester,
  ) async {
    final d = stillDevice(World());
    await pumpCard(tester, d.store);
    await tester.enterText(find.byType(EditableText), me);
    await tester.tap(find.byKey(SyncCard.sendKey));
    await tester.pumpAndSettle();
    expect(find.textContaining(me), findsOneWidget);

    await tester.enterText(find.byType(EditableText), '000000');
    await tester.tap(find.byKey(SyncCard.signInKey));
    await tester.pumpAndSettle();
    expect(d.store.isSignedIn, isFalse);
    expect(find.textContaining('wrong or too old'), findsOneWidget);

    await tester.tap(find.byKey(SyncCard.otherEmailKey));
    await tester.pumpAndSettle();
    expect(find.byKey(SyncCard.emailKey), findsOneWidget);
    expect(find.byKey(SyncCard.errorKey), findsNothing);
  });

  testWidgets('Enter in a field does the step', (tester) async {
    final d = stillDevice(World());
    await pumpCard(tester, d.store);
    await tester.enterText(find.byType(EditableText), me);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(d.auth.sent, [me]);
    await tester.enterText(find.byType(EditableText), d.auth.code);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
    expect(d.store.isSignedIn, isTrue);
  });

  testWidgets('"Sync now" sends a change, and an error shows in the card', (
    tester,
  ) async {
    final world = World();
    final d = stillDevice(world, signedIn: me);
    await pumpCard(tester, d.store);
    await settle(tester);
    final before = world.of(me).count;

    world.of(me).failure = const RemoteUnavailable('down');
    d.store.quickAdd('Buy milk');
    await tester.tap(find.byKey(SyncCard.syncNowKey));
    await settle(tester);
    expect(find.byKey(SyncCard.errorKey), findsOneWidget);
    expect(find.textContaining('No connection'), findsOneWidget);
    expect(world.of(me).count, before);

    world.of(me).failure = null;
    await tester.tap(find.byKey(SyncCard.syncNowKey));
    await settle(tester);
    expect(find.byKey(SyncCard.errorKey), findsNothing);
    expect(world.of(me).count, greaterThan(before));
    expect(find.textContaining('wait for the next sync'), findsNothing);
  });

  testWidgets('"Sign out" goes back to the email, and the data stays', (
    tester,
  ) async {
    final d = stillDevice(World(), signedIn: me);
    d.store.quickAdd('Buy milk');
    await pumpCard(tester, d.store);
    await settle(tester);
    await tester.tap(find.byKey(SyncCard.signOutKey));
    await settle(tester);
    expect(d.store.isSignedIn, isFalse);
    expect(find.byKey(SyncCard.emailKey), findsOneWidget);
    expect(titles(d.store), contains('Buy milk'));
  });

  group('The question of the first login', () {
    testWidgets('the card has the two answers, and no "Sync now"', (
      tester,
    ) async {
      final world = World();
      await fillAccount(world, me);
      final d = stillDevice(world);
      d.store.quickAdd('From the phone');
      await pumpCard(tester, d.store, size: questionSize);
      await signInWithCard(tester, d, me);

      expect(d.store.firstSyncQuestion, isTrue);
      expect(find.byKey(FirstSyncChoices.useAccountKey), findsOneWidget);
      expect(find.byKey(FirstSyncChoices.addDeviceKey), findsOneWidget);
      expect(find.byKey(SyncCard.syncNowKey), findsNothing);
      // No answer yet: nothing moved.
      expect(titles(d.store), {'From the phone'});

      await tester.tap(find.byKey(FirstSyncChoices.addDeviceKey));
      await settle(tester);
      expect(d.store.firstSyncQuestion, isFalse);
      expect(titles(d.store), {'From the phone', 'From the laptop'});
      expect(find.byKey(SyncCard.syncNowKey), findsOneWidget);
    });

    testWidgets('the gate opens the window, and an answer closes it', (
      tester,
    ) async {
      final world = World();
      await fillAccount(world, me);
      final d = stillDevice(world);
      d.store.quickAdd('From the phone');
      await pumpCard(tester, d.store, gate: true, size: const Size(700, 520));
      expect(find.byKey(const ValueKey('first-sync-dialog')), findsNothing);
      await signInWithCard(tester, d, me);

      final dialog = find.byKey(const ValueKey('first-sync-dialog'));
      expect(dialog, findsOneWidget);
      await tester.tap(
        find.descendant(
          of: dialog,
          matching: find.byKey(FirstSyncChoices.useAccountKey),
        ),
      );
      await settle(tester);
      expect(dialog, findsNothing);
      expect(d.store.firstSyncQuestion, isFalse);
      expect(titles(d.store), {'From the laptop'});
    });

    testWidgets(
      '"Not now" closes the window, and the card keeps the question',
      (tester) async {
        final world = World();
        await fillAccount(world, me);
        final d = stillDevice(world);
        d.store.quickAdd('From the phone');
        await pumpCard(tester, d.store, gate: true, size: const Size(700, 520));
        await signInWithCard(tester, d, me);
        final dialog = find.byKey(const ValueKey('first-sync-dialog'));
        await tester.tap(find.byKey(const ValueKey('first-sync-later')));
        await settle(tester);
        expect(dialog, findsNothing);
        expect(d.store.firstSyncQuestion, isTrue);
        expect(titles(d.store), {'From the phone'});
        expect(world.of(me).rows.length, 1);

        // A change of the store does not open the window a second time.
        d.store.quickAdd('One more');
        await settle(tester);
        expect(dialog, findsNothing);
        expect(find.byKey(FirstSyncChoices.addDeviceKey), findsOneWidget);
      },
    );

    testWidgets('no window when the account is empty', (tester) async {
      final d = stillDevice(World());
      d.store.quickAdd('From the phone');
      await pumpCard(tester, d.store, gate: true, size: const Size(700, 520));
      await signInWithCard(tester, d, me);
      expect(find.byKey(const ValueKey('first-sync-dialog')), findsNothing);
      expect(d.store.firstSyncQuestion, isFalse);
      expect(find.byKey(SyncCard.syncNowKey), findsOneWidget);
    });
  });
}
