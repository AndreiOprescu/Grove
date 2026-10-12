// On a Mac the window has no title bar (PLAN §5.8). An empty part of the
// top strip moves the window, as a title bar does.
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/ui/shell/left_dock.dart';
import 'package:grove/ui/shell/screen_switch.dart';
import 'package:grove/ui/shell/shell_layout.dart';
import 'package:grove/ui/shell/window_drag.dart';

import '../settings/settings_support.dart';

const channel = MethodChannel('grove/window');
const wide = Size(1440, 900);

/// What the app asked of the native window.
List<String> listen(WidgetTester tester) {
  final asked = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
    call,
  ) async {
    asked.add(call.method);
    return null;
  });
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      null,
    ),
  );
  return asked;
}

/// A point of the top strip with nothing on it: between the left dock and
/// the screen switch.
Offset emptyPoint(WidgetTester tester) {
  final dock = tester.getRect(find.byType(LeftDock));
  final screens = tester.getRect(find.byType(ScreenSwitch));
  expect(screens.left - dock.right, greaterThan(40));
  return Offset((dock.right + screens.left) / 2, 17);
}

Future<void> mouseDrag(WidgetTester tester, Offset from) async {
  await tester.dragFrom(
    from,
    const Offset(60, 10),
    kind: PointerDeviceKind.mouse,
  );
  await tester.pumpAndSettle();
}

Future<void> onMac(Future<void> Function() body) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

void main() {
  testWidgets('on a Mac a drag on an empty part of the top strip moves the '
      'window', (tester) async {
    await onMac(() async {
      final asked = listen(tester);
      final store = plannerStore();
      await pumpApp(tester, store, size: wide);
      await mouseDrag(tester, emptyPoint(tester));
      expect(asked, ['drag']);
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('the whole height of the strip moves the window, not more', (
    tester,
  ) async {
    await onMac(() async {
      final asked = listen(tester);
      final store = plannerStore();
      await pumpApp(tester, store, size: wide);
      final x = emptyPoint(tester).dx;
      await mouseDrag(tester, Offset(x, 1));
      await mouseDrag(tester, Offset(x, ShellRules.desktopTopStrip - 1));
      expect(asked, ['drag', 'drag']);
      // Under the strip the mouse belongs to the screen.
      await mouseDrag(tester, Offset(x, ShellRules.desktopTopStrip + 30));
      expect(asked, hasLength(2));
      await tester.pumpWidget(const SizedBox());
    });
  });

  // The system wants the mouse from the press on (AppKit: `performDrag`
  // takes the mouse-down event). With no move the window stays in place.
  testWidgets('the mouse goes to the system when it is pressed, one time', (
    tester,
  ) async {
    await onMac(() async {
      final asked = listen(tester);
      final store = plannerStore();
      await pumpApp(tester, store, size: wide);
      final mouse = await tester.startGesture(
        emptyPoint(tester),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      expect(asked, ['drag']);
      await mouse.moveBy(const Offset(30, 4));
      await mouse.moveBy(const Offset(30, 4));
      await mouse.up();
      await tester.pumpAndSettle();
      expect(asked, ['drag']);
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('a finger on the strip does not move the window', (tester) async {
    await onMac(() async {
      final asked = listen(tester);
      final store = plannerStore();
      await pumpApp(tester, store, size: wide);
      await tester.dragFrom(emptyPoint(tester), const Offset(60, 10));
      await tester.pumpAndSettle();
      expect(asked, isEmpty);
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('a button of the strip keeps its own mouse', (tester) async {
    await onMac(() async {
      final asked = listen(tester);
      final store = plannerStore();
      await pumpApp(tester, store, size: wide);
      await mouseDrag(tester, tester.getCenter(keyed('search-button')));
      expect(asked, isEmpty);
      await tester.tap(keyed('search-button'));
      await tester.pumpAndSettle();
      expect(store.paletteOpen, isTrue);
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('a Mac with no native side: the drag does nothing', (
    tester,
  ) async {
    await onMac(() async {
      final store = plannerStore();
      await pumpApp(tester, store, size: wide);
      await mouseDrag(tester, emptyPoint(tester));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('the other systems have a title bar: nothing is asked', (
    tester,
  ) async {
    final asked = listen(tester);
    final store = plannerStore();
    await pumpApp(tester, store, size: wide);
    expect(find.byType(WindowDragArea), findsNothing);
    await mouseDrag(tester, emptyPoint(tester));
    expect(asked, isEmpty);
  });
}
