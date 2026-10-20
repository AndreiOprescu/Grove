// Shared helpers for the tests of the login and the sync card.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/ui/auth/first_sync_dialog.dart';
import 'package:grove/ui/auth/sync_card.dart';
import 'package:grove/ui/theme/grove_theme.dart';

import '../../state/sync_support.dart';

export 'package:grove/ui/auth/first_sync_dialog.dart';
export 'package:grove/ui/auth/sync_card.dart';
export 'package:grove/ui/theme/grove_theme.dart';

export '../../state/sync_support.dart';
export '../support.dart';
export '../tasks/tasks_support.dart' show textOffPixels;

typedef Device = ({AppStore store, MemoryAuth auth});

/// "Now" in the pictures: Sunday 11 October 2026 at 10:00.
DateTime fixedNow() => DateTime(2026, 10, 11, 10);

/// The card in a column as wide as a settings column.
const cardSize = Size(380, 300);

/// The same column with room for the question of the first login.
const questionSize = Size(380, 400);

/// A device with motion off.
Device stillDevice(World world, {String? signedIn, bool seed = false}) =>
    world.device(
      signedIn: signedIn,
      seed: seed,
      prefs: MemoryPrefs()..set('appearance.motion', false),
      // `tester.pump` moves the clock of a widget test.
      realTime: true,
    );

/// Shows the sync card alone, with the gate that opens the question when
/// `gate` is true. The theme sits above the navigator, as in the app, so a
/// window gets it too.
Future<void> pumpCard(
  WidgetTester tester,
  AppStore store, {
  Size size = cardSize,
  ThemeId themeId = ThemeId.grove,
  Brightness brightness = Brightness.light,
  bool gate = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final theme = GroveTheme.make(themeId, brightness);
  final Widget card = Align(
    alignment: Alignment.topLeft,
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: SyncCard(store: store, now: fixedNow),
    ),
  );
  await tester.pumpWidget(
    MaterialApp(
      key: UniqueKey(),
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: brightness,
        splashFactory: NoSplash.splashFactory,
      ),
      builder: (context, child) => GroveThemeScope(theme: theme, child: child!),
      home: Scaffold(
        backgroundColor: theme.bg,
        // The text style the shell of the app gives (`RootView`).
        body: DefaultTextStyle(
          style: theme.body(13).copyWith(color: theme.ink),
          child: gate ? FirstSyncGate(store: store, child: card) : card,
        ),
      ),
    ),
  );
  // Take the tree down at the end, before the store is closed.
  addTearDown(() => tester.pumpWidget(const SizedBox()));
  await tester.pumpAndSettle();
}

/// Types the address and the code in the card, as a person does.
Future<void> signInWithCard(WidgetTester tester, Device d, String email) async {
  await tester.enterText(
    find.descendant(
      of: find.byKey(SyncCard.emailKey),
      matching: find.byType(EditableText),
    ),
    email,
  );
  await tester.tap(find.byKey(SyncCard.sendKey));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.descendant(
      of: find.byKey(SyncCard.codeKey),
      matching: find.byType(EditableText),
    ),
    d.auth.code,
  );
  await tester.tap(find.byKey(SyncCard.signInKey));
  await settle(tester);
}

/// Lets the sync end, and the message at the foot of the screen go away.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pump(const Duration(seconds: 3));
  await tester.pumpAndSettle();
}

/// The time of the last sync is "today at 09:41" from here on.
void fixLastSync(AppStore store) => store.prefs.set(
  'sync.lastAt',
  DateTime(2026, 10, 11, 9, 41).millisecondsSinceEpoch,
);

/// An account that already has one task, from another device.
Future<void> fillAccount(World world, String email) async {
  final d = stillDevice(world);
  await signIn(d, email);
  d.store.quickAdd('From the laptop');
  await d.store.syncNow();
  await idle(d.store);
}
