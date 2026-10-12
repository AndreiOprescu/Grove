// Shared helpers for the tests of the Settings window.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/ui/settings/settings_parts.dart';
import 'package:grove/ui/settings/settings_view.dart';
import 'package:grove/ui/store_app.dart';

import '../planner/planner_support.dart';

export 'package:grove/ui/settings/settings_parts.dart';
export 'package:grove/ui/settings/settings_view.dart';
export 'package:grove/ui/store_app.dart';

export '../planner/planner_support.dart';
export '../tasks/tasks_support.dart' show addTask, textOffPixels;

final settingsView = find.byType(SettingsView);

Finder keyed(String key) => find.byKey(ValueKey(key));

Finder tabButton(SettingsTab tab) => keyed('settings-tab-${tab.name}');

/// A widget inside the Settings window.
Finder inSettings(Finder what) =>
    find.descendant(of: settingsView, matching: what);

/// A file window that only writes down what the screen asks for.
class FakeFiles implements SettingsFiles {
  /// The file the person picks in "Import". null: the person closes the
  /// window.
  ({String name, String text})? picked;

  /// False: the person closes the window of "Export".
  bool saves = true;

  /// The error of the next save or open.
  Object? failure;

  /// False: a system with no save window (a phone).
  @override
  bool canSave = true;

  /// True: a system with a window of folders (a Mac, Windows).
  @override
  bool canShowFolder = false;

  /// False: the system does not open the folder.
  bool shows = true;

  /// The folders the screen asked the system to show.
  final shown = <String>[];

  @override
  Future<bool> showFolder(String path) async {
    if (failure case final f?) throw f;
    shown.add(path);
    return shows;
  }

  /// Runs while the window of "Import" is open.
  Future<void> Function()? whileOpen;

  final saved = <({String name, String text})>[];
  int opened = 0;

  @override
  Future<String?> save({
    required String suggestedName,
    required String text,
  }) async {
    if (failure case final f?) throw f;
    if (!saves) return null;
    saved.add((name: suggestedName, text: text));
    return suggestedName;
  }

  @override
  Future<({String name, String text})?> open() async {
    opened += 1;
    if (failure case final f?) throw f;
    await whileOpen?.call();
    return picked;
  }
}

/// Shows the app on `store`, with the file window `files`.
Future<void> pumpApp(
  WidgetTester tester,
  AppStore store, {
  Size size = desktopSize,
  SettingsFiles? files,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    StoreApp(key: UniqueKey(), store: store, files: files),
  );
  // Take the tree down at the end, before the store is closed.
  addTearDown(() => tester.pumpWidget(const SizedBox()));
  await tester.pumpAndSettle();
}

/// Ctrl and comma. A test runs as an Android device, so the key is Ctrl.
Future<void> pressSettingsKey(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
  await tester.sendKeyEvent(LogicalKeyboardKey.comma);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
  await tester.pumpAndSettle();
}

/// Shows the app and opens the Settings window on `tab`.
Future<void> openSettings(
  WidgetTester tester,
  AppStore store, {
  SettingsTab tab = SettingsTab.appearance,
  Size size = desktopSize,
  SettingsFiles? files,
}) async {
  await pumpApp(tester, store, size: size, files: files);
  await pressSettingsKey(tester);
  expect(settingsView, findsOneWidget);
  if (tab != SettingsTab.appearance) await showTab(tester, tab);
}

Future<void> showTab(WidgetTester tester, SettingsTab tab) async {
  await tester.ensureVisible(tabButton(tab));
  await tester.pumpAndSettle();
  await tester.tap(tabButton(tab));
  await tester.pumpAndSettle();
}

/// Opens the list of a picker and takes the line `text`.
Future<void> pick(WidgetTester tester, String key, String text) async {
  await tester.ensureVisible(keyed(key));
  await tester.pumpAndSettle();
  await tester.tap(keyed(key));
  await tester.pumpAndSettle();
  await tester.tap(find.text(text).last);
  await tester.pumpAndSettle();
}

/// A tap on a control of the window, after it is moved into view.
Future<void> tapIn(WidgetTester tester, Finder what) async {
  await tester.ensureVisible(what);
  await tester.pumpAndSettle();
  await tester.tap(what);
  await tester.pumpAndSettle();
}

/// Moves a slider to `value`, as a drag does.
Future<void> slideTo(WidgetTester tester, String key, double value) async {
  tester.widget<Slider>(keyed(key)).onChanged!(value);
  await tester.pumpAndSettle();
}

bool switchOn(WidgetTester tester, String key) =>
    tester.widget<GroveSwitch>(keyed(key)).value;
