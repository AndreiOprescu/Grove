// The window of Grove on a computer (PLAN §5.8, Sources/Grove/GroveApp.swift):
// it opens 1280 × 800 and is never under 1100 × 620. On the Mac it has no
// title bar: the app fills the whole window and its top strip starts next
// to the three window buttons. Run it on the Mac and on Windows:
//   ./scripts/flutter_integration.sh macos|windows
//
// The native side is in macos/Runner/MainFlutterWindow.swift and in
// windows/runner/win32_window.cpp.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/data/data.dart';
import 'package:grove/state/state.dart';
import 'package:grove/ui/shell/left_dock.dart';
import 'package:grove/ui/shell/root_view.dart';
import 'package:grove/ui/store_app.dart';
import 'package:integration_test/integration_test.dart';

const _first = Size(1280, 800);
const _smallest = Size(1100, 620);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final computer =
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.windows;

  testWidgets('the window opens at the size of the Mac app', (tester) async {
    final store = AppStore(
      repos: Repos(Database.inMemory()),
      prefs: MemoryPrefs()..set('appearance.motion', false),
    );
    addTearDown(store.dispose);
    await tester.pumpWidget(StoreApp(key: UniqueKey(), store: store));
    addTearDown(() => tester.pumpWidget(const SizedBox()));
    await tester.pumpAndSettle();

    final view = tester.view;
    final window = view.physicalSize / view.devicePixelRatio;
    final screen = view.display.size / view.display.devicePixelRatio;
    final padding = view.padding.top / view.devicePixelRatio;
    final dock = tester.getTopLeft(find.byType(LeftDock));
    // The line is in the log of the run: the proof of what the system gave.
    debugPrint(
      'GROVE_WINDOW system=${defaultTargetPlatform.name} '
      'window=${window.width}x${window.height} '
      'screen=${screen.width}x${screen.height} '
      'paddingTop=$padding dock=${dock.dx},${dock.dy}',
    );

    // Never under the smallest size, also on a small screen.
    expect(window.width, greaterThanOrEqualTo(_smallest.width - 0.5));
    expect(window.height, greaterThanOrEqualTo(_smallest.height - 0.5));
    expect(window.width, lessThanOrEqualTo(_first.width + 0.5));
    expect(window.height, lessThanOrEqualTo(_first.height + 0.5));
    // A screen with room for it gets the first size. (A screen of a test
    // machine can be 1024 × 768: the window is smaller there.)
    if (screen.width >= 1440 && screen.height >= 960) {
      expect(window.width, closeTo(_first.width, 0.5));
      expect(window.height, closeTo(_first.height, 0.5));
    }

    // The top strip starts at the top edge of the window: 5 points down,
    // and 84 points from the left on the Mac (the three window buttons).
    expect(padding, 0);
    expect(dock, Offset(RootView.dockLeft, 5));
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      expect(RootView.dockLeft, 84);
    }
  }, skip: !computer);
}
