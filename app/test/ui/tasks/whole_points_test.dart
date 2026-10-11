// The text of the panels sits on whole points, so a golden picture is the
// same on macOS, Linux and Windows (see `textOffPixels`).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/ui/goals/goals_pane.dart';
import 'package:grove/ui/tasks/task_widgets.dart';

import 'tasks_support.dart';

void main() {
  group('wholeShares', () {
    test('equal parts when the width divides', () {
      expect(wholeShares(300, 3), [100, 100, 100]);
    });

    test('the first parts get the points that are left over', () {
      expect(wholeShares(302, 4), [76, 76, 75, 75]);
    });

    test('a part of a point stays free', () {
      final parts = wholeShares(325.5, 4);
      expect(parts, [82, 81, 81, 81]);
      expect(parts.reduce((a, b) => a + b), 325);
    });

    test('nothing to share', () {
      expect(wholeShares(100, 0), isEmpty);
      expect(wholeShares(0, 2), [0, 0]);
      expect(wholeShares(-4, 2), [0, 0]);
      expect(wholeShares(double.infinity, 2), [0, 0]);
    });
  });

  group('Segments', () {
    Future<void> pumpSegments(WidgetTester tester, double width) => pumpPane(
      tester,
      Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: width,
          child: Segments<String>(
            value: 'Day',
            values: const ['Inbox', 'Day', 'Week', 'Someday'],
            name: (v) => v,
            onPick: (_) {},
            label: 'List',
          ),
        ),
      ),
    );

    for (final width in [308.0, 309.0, 310.0, 311.0, 310.5]) {
      testWidgets('each name starts on a whole point at width $width', (
        tester,
      ) async {
        await pumpSegments(tester, width);
        for (final name in ['Inbox', 'Day', 'Week', 'Someday']) {
          final left = tester.getTopLeft(find.text(name)).dx;
          expect(left, left.roundToDouble(), reason: name);
        }
      });
    }

    testWidgets('each name is in the middle of its button', (tester) async {
      await pumpSegments(tester, 310);
      // 310 - 4 of padding - 6 of gaps = 300, so each button is 75 wide.
      for (final (i, name) in ['Inbox', 'Day', 'Week', 'Someday'].indexed) {
        final middle = tester.getCenter(find.text(name)).dx;
        expect(middle, closeTo(2 + i * 77 + 37.5, 0.5), reason: name);
      }
    });

    testWidgets('a name too long for its button is cut, with no overflow', (
      tester,
    ) async {
      await pumpSegments(tester, 120);
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.text('Someday')).width, lessThanOrEqualTo(27));
    });
  });

  testWidgets('a text field has no gap between its letters', (tester) async {
    final store = paneStore();
    await pumpPane(tester, GoalsPane(store: store));
    final fields = tester.widgetList<EditableText>(find.byType(EditableText));
    expect(fields, isNotEmpty);
    for (final field in fields) {
      expect(field.style.letterSpacing, 0);
    }
    expect(textOffPixels(tester), isEmpty);
  });
}
