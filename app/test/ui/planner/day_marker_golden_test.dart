// Golden screenshots of the wake-up line and the sleep line of the planner.
//
// Make the pictures again after a wanted change of the look:
//   cd app && flutter test --update-goldens test/ui/planner
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/ui/planner/day_markers.dart';
import 'package:grove/ui/store_app.dart';

import '../tasks/tasks_support.dart' show textOffPixels;
import 'planner_support.dart';

void line(AppStore store, DayMarkerKind kind, DayKey day, int minute) => store
  ..addDayMarker(kind, day)
  ..moveDayMarker(kind, day, minute);

/// A morning with lines on some days of the week. One line lies on a block.
AppStore _morning({ThemeId theme = ThemeId.grove, bool dark = false}) {
  final store = plannerStore(now: 8 * 60 + 20);
  store
    ..setTheme(theme)
    ..setAppearance(dark ? AppearanceMode.dark : AppearanceMode.light)
    ..createFromDraft(
      title: 'Stand-up',
      day: wednesday,
      start: 9 * 60,
      end: 9 * 60 + 30,
      asEvent: true,
    )
    ..createFromDraft(
      title: 'Pack for the trip',
      day: wednesday.adding(days: 1),
      start: 8 * 60 + 30,
      end: 10 * 60,
      asEvent: false,
    );
  line(store, DayMarkerKind.wake, wednesday.adding(days: -2), 8 * 60);
  line(store, DayMarkerKind.wake, wednesday, 7 * 60 + 45);
  line(store, DayMarkerKind.wake, wednesday.adding(days: 1), 9 * 60 + 15);
  // A late morning after a night shift.
  line(store, DayMarkerKind.sleep, wednesday.adding(days: 3), 9 * 60 + 30);
  line(store, DayMarkerKind.wake, wednesday.adding(days: 3), 12 * 60 + 15);
  store.selection = {};
  return store;
}

final layer = find.byType(DayMarkerLayer);

void main() {
  setUpAll(() async {
    TolerantGoldenComparator.install();
    await loadIconFont();
  });

  for (final theme in ThemeId.values) {
    testWidgets('day lines desktop ${theme.name}', (tester) async {
      await withRealShadows(() async {
        final store = _morning(theme: theme);
        await pumpPlanner(tester, store);
        expect(textOffPixels(tester, within: layer), isEmpty);
        await expectLater(
          find.byType(StoreApp),
          matchesGoldenFile(
            'goldens/day_lines_desktop_${theme.name}_light.png',
          ),
        );
      });
    });
  }

  testWidgets('day lines desktop grove dark', (tester) async {
    await withRealShadows(() async {
      final store = _morning(dark: true);
      await pumpPlanner(tester, store);
      await expectLater(
        find.byType(StoreApp),
        matchesGoldenFile('goldens/day_lines_desktop_grove_dark.png'),
      );
    });
  });

  // One wide day column: the label has the name of the line too.
  testWidgets('day lines phone grove', (tester) async {
    await withRealShadows(() async {
      final store = plannerStore(now: 21 * 60 + 30);
      store.createFromDraft(
        title: 'Read',
        day: wednesday,
        start: 22 * 60,
        end: 22 * 60 + 45,
        asEvent: false,
      );
      // A day after a night shift.
      line(store, DayMarkerKind.wake, wednesday, 15 * 60 + 30);
      line(store, DayMarkerKind.sleep, wednesday, 23 * 60);
      store.selection = {};
      await pumpPlanner(tester, store, size: phoneSize);
      expect(textOffPixels(tester, within: layer), isEmpty);
      await expectLater(
        find.byType(StoreApp),
        matchesGoldenFile('goldens/day_lines_phone_grove_light.png'),
      );
    });
  });

  // The timeline of the Today screen, with a line in the middle of a drag:
  // its label is dark and shows the time under the pointer.
  testWidgets('day lines on Today, one in a drag', (tester) async {
    await withRealShadows(() async {
      final store = plannerStore(now: 8 * 60 + 20)..screen = Screen.today;
      line(store, DayMarkerKind.wake, wednesday, 7 * 60 + 45);
      line(store, DayMarkerKind.sleep, wednesday, 11 * 60);
      await pumpPlanner(tester, store);
      final from = tester.getCenter(
        find.byKey(ValueKey('day-marker-sleep-${wednesday.string}')),
      );
      final gesture = await tester.startGesture(
        from,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await gesture.moveTo(from + const Offset(0, 48));
      await tester.pump();

      expect(textOffPixels(tester, within: layer), isEmpty);
      await expectLater(
        find.byType(StoreApp),
        matchesGoldenFile('goldens/day_lines_today_drag_grove_light.png'),
      );
      await gesture.up();
      await tester.pumpAndSettle();
      expect(store.dayMarker(DayMarkerKind.sleep, wednesday), 11 * 60 + 45);
    });
  });
}
