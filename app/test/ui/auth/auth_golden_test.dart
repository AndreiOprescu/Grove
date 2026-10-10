// Golden screenshots of the login and the sync card (milestone F11).
//
// Make the pictures again after a wanted change of the look:
//   cd app && flutter test --update-goldens test/ui/auth
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'auth_support.dart';

const _dialogSize = Size(560, 420);

final _card = find.byType(SyncCard);
final _dialog = find.byKey(const ValueKey('first-sync-dialog'));

Future<void> _shot(WidgetTester tester, String name, {Finder? within}) async {
  expect(textOffPixels(tester, within: within ?? _card), isEmpty);
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('goldens/$name.png'),
  );
}

/// A device that asks the question: it has a task, and the account has one.
Future<Device> _asked(World world) async {
  await fillAccount(world, me);
  final d = stillDevice(world);
  d.store.quickAdd('From the phone');
  await signIn(d, me);
  expect(d.store.firstSyncQuestion, isTrue);
  return d;
}

void main() {
  setUpAll(() async {
    TolerantGoldenComparator.install();
    await loadIconFont();
  });

  testWidgets('no sync in this build', (tester) async {
    await withRealShadows(() async {
      final store = makeStore(
        prefs: MemoryPrefs()..set('appearance.motion', false),
      );
      await pumpCard(tester, store);
      await _shot(tester, 'sync_off');
    });
  });

  testWidgets('the email step', (tester) async {
    await withRealShadows(() async {
      final d = stillDevice(World());
      await pumpCard(tester, d.store);
      await _shot(tester, 'sync_email');
    });
  });

  testWidgets('the email step with an error', (tester) async {
    await withRealShadows(() async {
      final d = stillDevice(World());
      await pumpCard(tester, d.store);
      await tester.enterText(find.byType(EditableText), 'me at example');
      await tester.tap(find.byKey(SyncCard.sendKey));
      await tester.pumpAndSettle();
      await _shot(tester, 'sync_email_error');
    });
  });

  testWidgets('the code step', (tester) async {
    await withRealShadows(() async {
      final d = stillDevice(World());
      await d.store.sendLoginLink(me);
      await pumpCard(tester, d.store);
      await tester.enterText(find.byType(EditableText), '123456');
      await tester.pumpAndSettle();
      await _shot(tester, 'sync_code');
    });
  });

  for (final theme in ThemeId.values) {
    for (final brightness in Brightness.values) {
      // The dark look is tested for one theme. The colours of the others
      // come from the same theme object.
      if (brightness == Brightness.dark && theme != ThemeId.grove) continue;
      final look = '${theme.name}_${brightness.name}';

      testWidgets('signed in $look', (tester) async {
        await withRealShadows(() async {
          final d = stillDevice(World(), signedIn: me);
          await idle(d.store);
          fixLastSync(d.store);
          await pumpCard(
            tester,
            d.store,
            themeId: theme,
            brightness: brightness,
          );
          await _shot(tester, 'sync_signed_in_$look');
        });
      });

      testWidgets('the window of the first login $look', (tester) async {
        await withRealShadows(() async {
          final d = await _asked(World());
          await pumpCard(
            tester,
            d.store,
            size: _dialogSize,
            themeId: theme,
            brightness: brightness,
            gate: true,
          );
          expect(_dialog, findsOneWidget);
          await _shot(tester, 'first_sync_dialog_$look', within: _dialog);
        });
      });
    }
  }

  testWidgets('signed in, with changes that wait and an error', (tester) async {
    await withRealShadows(() async {
      final world = World();
      final d = stillDevice(world, signedIn: me);
      await idle(d.store);
      fixLastSync(d.store);
      world.of(me).failure = const RemoteUnavailable('down');
      d.store
        ..quickAdd('Buy milk')
        ..quickAdd('Call the bank');
      await d.store.syncNow();
      await idle(d.store);
      await pumpCard(tester, d.store);
      await settle(tester);
      await _shot(tester, 'sync_error');
    });
  });

  testWidgets('the question in the card', (tester) async {
    await withRealShadows(() async {
      final d = await _asked(World());
      await pumpCard(tester, d.store, size: questionSize);
      await _shot(tester, 'sync_question');
    });
  });
}
