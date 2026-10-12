// The small window of an error (Swift: the `.alert("Grove", ...)` of
// Sources/Grove/Layouts/RootView.swift): the store has an error message,
// the window shows it, "OK" takes the message away.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/ui/shell/error_alert.dart';

import '../settings/settings_support.dart';

final alert = keyed('error-alert');
final alertText = keyed('error-alert-text');
final okButton = keyed('error-alert-ok');

String shown(WidgetTester tester) => tester.widget<Text>(alertText).data!;

void main() {
  testWidgets('with no error there is no window', (tester) async {
    final store = plannerStore();
    await pumpApp(tester, store);
    expect(store.errorMessage, isNull);
    expect(alert, findsNothing);
  });

  testWidgets('an error of the store opens the window with its text', (
    tester,
  ) async {
    final store = plannerStore();
    await pumpApp(tester, store);
    store.errorMessage = 'Could not save: the disk is full';
    await tester.pumpAndSettle();
    expect(alert, findsOneWidget);
    expect(shown(tester), 'Could not save: the disk is full');
    // The heading and the button of the Mac app.
    expect(find.descendant(of: alert, matching: find.text('Grove')), findsOne);
    expect(find.descendant(of: alert, matching: find.text('OK')), findsOne);
    // The message stays in the store while the window is open.
    expect(store.errorMessage, isNotNull);
  });

  testWidgets('"OK" closes the window and takes the message away', (
    tester,
  ) async {
    final store = plannerStore();
    await pumpApp(tester, store);
    store.errorMessage = 'Could not save';
    await tester.pumpAndSettle();
    await tester.tap(okButton);
    await tester.pumpAndSettle();
    expect(alert, findsNothing);
    expect(store.errorMessage, isNull);
  });

  testWidgets('Escape and a click next to the window do the same', (
    tester,
  ) async {
    final store = plannerStore();
    await pumpApp(tester, store);
    store.errorMessage = 'Could not save';
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(alert, findsNothing);
    expect(store.errorMessage, isNull);

    store.errorMessage = 'Could not save again';
    await tester.pumpAndSettle();
    expect(shown(tester), 'Could not save again');
    await tester.tapAt(const Offset(10, 300));
    await tester.pumpAndSettle();
    expect(alert, findsNothing);
    expect(store.errorMessage, isNull);
  });

  testWidgets('an error that is there at the start is shown too', (
    tester,
  ) async {
    final store = plannerStore()..errorMessage = 'Could not open the data';
    await pumpApp(tester, store);
    expect(shown(tester), 'Could not open the data');
  });

  testWidgets('one window at a time; a newer error gets its own window', (
    tester,
  ) async {
    final store = plannerStore();
    await pumpApp(tester, store);
    store.errorMessage = 'First';
    await tester.pumpAndSettle();
    store.errorMessage = 'Second';
    await tester.pumpAndSettle();
    expect(alert, findsOneWidget);
    expect(shown(tester), 'First');
    await tester.tap(okButton);
    await tester.pumpAndSettle();
    // The newer message was not thrown away with the first window.
    expect(alert, findsOneWidget);
    expect(shown(tester), 'Second');
    await tester.tap(okButton);
    await tester.pumpAndSettle();
    expect(alert, findsNothing);
    expect(store.errorMessage, isNull);
  });

  testWidgets('while the window is open the keys of the app do nothing', (
    tester,
  ) async {
    final store = plannerStore();
    await pumpApp(tester, store);
    store.errorMessage = 'Could not save';
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit5);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(store.screen, Screen.planner);
    expect(alert, findsOneWidget);
  });

  testWidgets('a long text stays inside a phone and can be read to the end', (
    tester,
  ) async {
    final store = plannerStore();
    await pumpApp(tester, store, size: phoneSize);
    store.errorMessage = [
      for (var i = 0; i < 60; i++) 'Could not save the file number $i.',
    ].join(' ');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final box = tester.getRect(alert);
    expect(box.left, greaterThanOrEqualTo(0));
    expect(box.right, lessThanOrEqualTo(phoneSize.width));
    expect(box.bottom, lessThanOrEqualTo(phoneSize.height));
    // The button is at the end of the text: the window scrolls to it.
    await tester.ensureVisible(okButton);
    await tester.pumpAndSettle();
    await tester.tap(okButton);
    await tester.pumpAndSettle();
    expect(store.errorMessage, isNull);
  });

  testWidgets('the text is on whole pixels', (tester) async {
    final store = plannerStore();
    await pumpApp(tester, store);
    store.errorMessage = 'Could not save: the disk is full';
    await tester.pumpAndSettle();
    expect(textOffPixels(tester, within: alert), isEmpty);
  });

  testWidgets('the window can be opened by hand', (tester) async {
    final store = plannerStore();
    await pumpApp(tester, store);
    final context = tester.element(find.byType(ErrorGate));
    final closed = showErrorAlert(context, 'By hand');
    await tester.pumpAndSettle();
    expect(shown(tester), 'By hand');
    await tester.tap(okButton);
    await tester.pumpAndSettle();
    await closed;
    expect(alert, findsNothing);
  });
}
