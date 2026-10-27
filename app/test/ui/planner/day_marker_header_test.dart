// The header of the planner. It must fit at each width, and it has no "+"
// for the wake-up line and the sleep line: the day menu adds them.
//
// The other tests draw text in the test font, where each letter is a
// square: "Plan my day" is much wider there than in the app. This file
// loads the fonts of the app, so the widths are the real ones.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/ui/planner/planner_kind.dart';
import 'package:grove/ui/planner/planner_view.dart';
import 'package:grove/ui/theme/panel.dart';

import '../tasks/tasks_support.dart' show pumpPane;
import 'planner_support.dart';

/// The fonts of the body text of the four themes.
const fonts = {
  'Nunito': ['fonts/nunito/Nunito-Variable.ttf'],
  'Inter': ['fonts/inter/Inter-Variable.ttf'],
  'Courier Prime': [
    'fonts/courierprime/CourierPrime-Regular.ttf',
    'fonts/courierprime/CourierPrime-Bold.ttf',
  ],
  'Newsreader': ['fonts/newsreader/Newsreader-Variable.ttf'],
  'Archivo': ['fonts/archivo/Archivo-Variable.ttf'],
  'JetBrains Mono': ['fonts/jetbrainsmono/JetBrainsMono-Variable.ttf'],
};

void main() {
  setUpAll(() async {
    await loadIconFont();
    for (final entry in fonts.entries) {
      final loader = FontLoader(entry.key);
      for (final path in entry.value) {
        final bytes = await File(path).readAsBytes();
        loader.addFont(Future.value(ByteData.sublistView(bytes)));
      }
      await loader.load();
    }
  });

  for (final themeId in ThemeId.values) {
    testWidgets('the week fits at each width in the ${themeId.name} '
        'theme', (tester) async {
      final store = plannerStore();
      final bad = <String>[];
      for (var width = 320.0; width <= 1100; width += 6) {
        await pumpPane(
          tester,
          PlannerView(store: store, kind: PlannerKind.week),
          size: Size(width, 620),
          themeId: themeId,
        );
        await tester.pumpAndSettle();
        final error = tester.takeException();
        if (error != null) bad.add('$width: $error');
        expect(find.byKey(const ValueKey('day-marker-add')), findsNothing);
      }
      expect(bad, isEmpty);
    });
  }

  // The buttons must not take room from the dates of the week. In these two
  // themes the dates are whole from this width on.
  for (final themeId in [ThemeId.grove, ThemeId.minimal]) {
    testWidgets('the buttons do not cut the dates of the week in the '
        '${themeId.name} theme', (tester) async {
      final store = plannerStore();
      // The week with the longest dates: 28 Sep to 4 Oct.
      store.selectedDay = d('2026-09-30');
      final cut = <double>[];
      for (var width = 500.0; width <= 1100; width += 4) {
        await pumpPane(
          tester,
          PlannerView(store: store, kind: PlannerKind.week),
          size: Size(width, 620),
          themeId: themeId,
        );
        await tester.pumpAndSettle();
        final title = tester.renderObject<RenderParagraph>(
          find
              .descendant(
                of: find.byType(ThemedHeading).first,
                matching: find.byType(RichText),
              )
              .first,
        );
        if (title.didExceedMaxLines) cut.add(width);
      }
      expect(cut, isEmpty);
    });
  }
}
