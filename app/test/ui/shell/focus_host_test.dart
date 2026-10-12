// The timer of a focus session is a part of the window, not of one screen
// (Swift: the overlay at the bottom right of Sources/Grove/Layouts/
// RootView.swift). It shows on each screen while a session runs, one time.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/ui/app.dart';
import 'package:grove/ui/planner/focus_card.dart';
import 'package:grove/ui/shell/screen_switch.dart';
import 'package:grove/ui/shell/shell_layout.dart';

import '../planner/planner_support.dart';

final card = find.byType(FocusCard);

Finder inCard(Finder what) => find.descendant(of: card, matching: what);

/// A store with a block from 10:00 to 11:00 and a session on it. The clock
/// of the card says `hour`:`minute`.
Future<AppStore> pumpWithSession(
  WidgetTester tester, {
  int hour = 10,
  int minute = 35,
  int second = 0,
  Size size = desktopSize,
  Screen screen = Screen.planner,
}) async {
  final store = focusStore();
  final id = hourBlock(store, 'Write report');
  store.screen = screen;
  setFocusClock(tester, hour, minute, second);
  await pumpPlanner(tester, store, size: size);
  store.startFocus(store.event(id)!);
  await tester.pumpAndSettle();
  return store;
}

/// Counts the states made and taken away, to see that a layer stays when
/// the screen changes.
class _Probe extends StatefulWidget {
  const _Probe({required this.child});

  final Widget child;

  static int made = 0;

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  void initState() {
    super.initState();
    _Probe.made++;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

void main() {
  group('the focus timer in the window', () {
    testWidgets('it shows on Notes and on the Garden too', (tester) async {
      final store = await pumpWithSession(tester);

      store.screen = Screen.notes;
      await tester.pumpAndSettle();
      expect(card, findsOneWidget);
      expect(inCard(find.text('Write report')), findsOneWidget);
      expect(inCard(find.text('25:00')), findsOneWidget);

      store.screen = Screen.garden;
      await tester.pumpAndSettle();
      expect(card, findsOneWidget);
      expect(inCard(find.text('25:00')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('each screen has one timer, not two', (tester) async {
      final store = await pumpWithSession(tester);
      for (final screen in Screen.values) {
        store.screen = screen;
        await tester.pumpAndSettle();
        expect(card, findsOneWidget, reason: screen.name);
        expect(find.byType(FocusLayer), findsOneWidget, reason: screen.name);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('a session that starts on Notes shows there at once', (
      tester,
    ) async {
      await pumpWithSession(tester, screen: Screen.notes);
      expect(card, findsOneWidget);
      expect(inCard(find.text('25:00')), findsOneWidget);
    });

    testWidgets('it counts on while the screen changes', (tester) async {
      final store = await pumpWithSession(tester);
      store.screen = Screen.notes;
      await tester.pump(const Duration(seconds: 1));
      expect(inCard(find.text('24:59')), findsOneWidget);
      store.screen = Screen.garden;
      await tester.pump(const Duration(seconds: 1));
      expect(inCard(find.text('24:58')), findsOneWidget);
      store.screen = Screen.planner;
      await tester.pump(const Duration(seconds: 1));
      expect(inCard(find.text('24:57')), findsOneWidget);
      expect(card, findsOneWidget);
    });

    testWidgets('a session that ends on Notes asks there, and "Mark done" '
        'checks the task off', (tester) async {
      final store = await pumpWithSession(
        tester,
        minute: 59,
        second: 58,
        screen: Screen.notes,
      );
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect(store.focus?.finished, isTrue);
      expect(inCard(find.text('Time is up. Mark done?')), findsOneWidget);

      await tester.tap(inCard(find.bySemanticsLabel('Mark done')));
      await tester.pumpAndSettle();
      expect(store.focus, isNull);
      expect(card, findsNothing);
      final block = store
          .blocks(DayRange.single(focusDay))
          .firstWhere((b) => b.title == 'Write report');
      expect(store.task(store.event(block.id)!.taskId!)!.isDone, isTrue);
    });

    testWidgets('the cross stops the session on the Garden', (tester) async {
      final store = await pumpWithSession(tester, screen: Screen.garden);
      await tester.tap(inCard(find.bySemanticsLabel('Stop focus')));
      await tester.pumpAndSettle();
      expect(store.focus, isNull);
      expect(card, findsNothing);
    });

    testWidgets('it is 16 from the bottom right corner of the window on '
        'each screen', (tester) async {
      final store = await pumpWithSession(tester);
      for (final screen in Screen.values) {
        store.screen = screen;
        await tester.pumpAndSettle();
        final rect = tester.getRect(card);
        expect(rect.width, 230, reason: screen.name);
        expect(rect.right, desktopSize.width - 16, reason: screen.name);
        expect(rect.bottom, desktopSize.height - 16, reason: screen.name);
        // On whole points, so the text is sharp.
        expect(rect.left, rect.left.roundToDouble(), reason: screen.name);
        expect(rect.top, rect.top.roundToDouble(), reason: screen.name);
      }
    });

    testWidgets('with a left panel open the timer keeps its place', (
      tester,
    ) async {
      final store = await pumpWithSession(tester);
      store.showLeftPane(LeftPane.tasks);
      await tester.pumpAndSettle();
      expect(card, findsOneWidget);
      final rect = tester.getRect(card);
      expect(rect.right, desktopSize.width - 16);
      expect(rect.bottom, desktopSize.height - 16);
    });

    testWidgets('on a phone it stands over the bar at the bottom, on each '
        'screen', (tester) async {
      final store = await pumpWithSession(tester, size: phoneSize);
      for (final screen in Screen.values) {
        store.screen = screen;
        await tester.pumpAndSettle();
        expect(card, findsOneWidget, reason: screen.name);
        final rect = tester.getRect(card);
        final bar = tester.getRect(find.byType(PhoneNavBar));
        expect(rect.width, 230, reason: screen.name);
        expect(rect.right, phoneSize.width - 16, reason: screen.name);
        expect(rect.bottom, bar.top - 16, reason: screen.name);
        expect(
          rect.top,
          greaterThanOrEqualTo(ShellRules.phoneTopStrip),
          reason: screen.name,
        );
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('on a phone it shows over an open panel too', (tester) async {
      final store = await pumpWithSession(tester, size: phoneSize);
      store.showLeftPane(LeftPane.tasks);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pane-tasks')), findsOneWidget);
      expect(card, findsOneWidget);
      final bar = tester.getRect(find.byType(PhoneNavBar));
      expect(tester.getRect(card).bottom, bar.top - 16);
    });

    testWidgets('the screen under the rest of the window still takes '
        'clicks', (tester) async {
      final store = await pumpWithSession(tester, screen: Screen.garden);
      // The screen switch is not under the layer.
      await tester.tap(find.byKey(const ValueKey('screen-notes')));
      await tester.pumpAndSettle();
      expect(store.screen, Screen.notes);
      expect(card, findsOneWidget);
    });
  });

  group('the layer of the window', () {
    setUp(() => _Probe.made = 0);

    testWidgets('it is under the top strip, and it stays when the screen '
        'changes', (tester) async {
      final model = still();
      tester.view.physicalSize = desktopSize;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        GroveApp(
          model: model,
          contentLayer: (context, content) => _Probe(child: content),
        ),
      );
      await tester.pumpAndSettle();
      expect(_Probe.made, 1);
      final rect = tester.getRect(find.byType(_Probe));
      expect(rect.top, ShellRules.desktopTopStrip);
      expect(rect.left, 0);
      expect(rect.right, desktopSize.width);
      expect(rect.bottom, desktopSize.height);

      model.screen = Screen.notes;
      await tester.pumpAndSettle();
      model.screen = Screen.planner;
      model.showLeftPane(LeftPane.tasks);
      await tester.pumpAndSettle();
      expect(_Probe.made, 1);
      expect(
        find.descendant(
          of: find.byType(_Probe),
          matching: find.byKey(const ValueKey('pane-tasks')),
        ),
        findsOneWidget,
      );
    });

    testWidgets('on a phone it is between the top strip and the bar', (
      tester,
    ) async {
      final model = still();
      tester.view.physicalSize = phoneSize;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        GroveApp(
          model: model,
          contentLayer: (context, content) => _Probe(child: content),
        ),
      );
      await tester.pumpAndSettle();
      final rect = tester.getRect(find.byType(_Probe));
      expect(rect.top, ShellRules.phoneTopStrip);
      expect(rect.bottom, tester.getRect(find.byType(PhoneNavBar)).top);
      expect(rect.width, phoneSize.width);

      model.screen = Screen.garden;
      await tester.pumpAndSettle();
      expect(_Probe.made, 1);
    });
  });
}
