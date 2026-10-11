// Shared helpers for the tests of the task and goal panels.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/ui/goals/goals_pane.dart';
import 'package:grove/ui/tasks/task_inspector.dart';
import 'package:grove/ui/tasks/tasks_pane.dart';
import 'package:grove/ui/theme/grove_theme.dart';
import 'package:grove/ui/theme/panel.dart';

import '../../state/support.dart';

export '../../state/support.dart';
export '../support.dart';

/// A Wednesday. The week of the tests is Monday 5 to Sunday 11 October 2026.
final wednesday = d('2026-10-07');

/// A store with motion off. "Now" is Wednesday at 10:00.
AppStore paneStore({int now = 10 * 60}) {
  final store = makeStore(
    prefs: MemoryPrefs()..set('appearance.motion', false),
    clock: WallTime(day: wednesday, minute: now),
  );
  store.selectedDay = wednesday;
  return store;
}

/// The size of a left panel in the smallest desktop window.
const paneSize = Size(320, 570);

/// Shows one panel alone, in a window of `size` points.
Future<void> pumpPane(
  WidgetTester tester,
  Widget pane, {
  Size size = paneSize,
  ThemeId themeId = ThemeId.grove,
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final theme = GroveTheme.make(themeId, brightness);
  await tester.pumpWidget(
    MaterialApp(
      key: UniqueKey(),
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: brightness,
        splashFactory: NoSplash.splashFactory,
      ),
      home: GroveThemeScope(
        theme: theme,
        child: Scaffold(
          backgroundColor: theme.bg,
          // The text style the shell of the app gives (`RootView`). Without
          // it the text gets the Material style, with a gap between letters.
          body: DefaultTextStyle(
            style: theme.body(13).copyWith(color: theme.ink),
            child: pane,
          ),
        ),
      ),
    ),
  );
  // Take the tree down at the end, before the store is closed.
  addTearDown(() => tester.pumpWidget(const SizedBox()));
  await tester.pumpAndSettle();
}

/// A new open task. The id is fixed when `id` is given.
TaskItem addTask(
  AppStore store,
  String title, {
  String? id,
  TaskBucket bucket = TaskBucket.day,
  DayKey? day,
  int priority = 0,
  String color = '',
  int estimateMin = 30,
  String? due,
  String notes = '',
  double sort = 0,
}) {
  final task = TaskItem(
    id: id ?? title.toLowerCase().replaceAll(' ', '-'),
    title: title,
    bucket: bucket,
    planDate: bucket == TaskBucket.day ? (day ?? wednesday) : null,
    planWeek: bucket == TaskBucket.week ? (day ?? wednesday).weekStart() : null,
    priority: priority,
    color: color,
    estimateMin: estimateMin,
    due: due,
    notes: notes,
    sort: sort,
  );
  store.repos.tasks.save(task);
  return task;
}

Finder rowFinder(String id) => find.byKey(ValueKey('task-$id'));

Finder checkFinder(String id) => find.byKey(ValueKey('check-$id'));

/// A right click at the middle of `finder`.
Future<void> rightClick(WidgetTester tester, Finder finder) async {
  await tester.tap(finder, buttons: kSecondaryMouseButton);
  await tester.pumpAndSettle();
}

/// Types `text` in the field and presses Return.
Future<void> typeLine(WidgetTester tester, Finder field, String text) async {
  await tester.tap(field);
  await tester.pump();
  await tester.enterText(
    find.descendant(of: field, matching: find.byType(EditableText)),
    text,
  );
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pumpAndSettle();
}

/// A mouse drag from the middle of `from` to the middle of `to`.
Future<void> dragOnto(
  WidgetTester tester,
  Finder from,
  Finder to, {
  Offset toOffset = Offset.zero,
}) async {
  final start = tester.getCenter(from);
  final end = tester.getCenter(to) + toOffset;
  final gesture = await tester.startGesture(
    start,
    kind: PointerDeviceKind.mouse,
  );
  await tester.pump();
  for (var i = 1; i <= 8; i++) {
    await gesture.moveTo(Offset.lerp(start, end, i / 8)!);
    await tester.pump(const Duration(milliseconds: 16));
  }
  await gesture.up();
  await tester.pumpAndSettle();
}

/// Lets the short message of the store go away.
Future<void> endToast(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 2500));
  await tester.pumpAndSettle();
}

/// The texts of the task and goal panels that do not sit on whole pixels
/// from left to right. The list is empty when all is well.
///
/// The letters of the test font are full boxes. When a text starts on a part
/// of a pixel, or has a gap between its letters that is not a whole number,
/// there is a thin seam between two letters. macOS, Linux and Windows draw
/// that seam each in its own way, so a golden picture made on the Mac fails
/// on the other two. Call this before each golden picture of a panel.
///
/// Not checked: an icon, a text of one letter (no seam), and a
/// `ThemedHeading` (the letter gap of the theme, -0.2 or 1.5, is its look).
List<String> textOffPixels(WidgetTester tester, {Finder? within}) {
  final out = <String>[];
  final panels =
      within ??
      find.byWidgetPredicate(
        (w) => w is TasksPane || w is TaskInspector || w is GoalsPane,
      );
  bool whole(double v) => (v - v.roundToDouble()).abs() < 0.01;

  void check(String kind, InlineSpan span, double left, List<TextBox> boxes) {
    final text = span.toPlainText().replaceAll('\n', ' ');
    if (text.trim().length < 2) return;
    var icon = false;
    final gaps = <double>{};
    span.visitChildren((s) {
      final style = s.style;
      if (style?.fontFamily == 'MaterialIcons') icon = true;
      final gap = style?.letterSpacing;
      if (gap != null) gaps.add(gap);
      return true;
    });
    // One icon is one shape with round edges. It has no seam.
    if (icon) return;
    final why = <String>[
      for (final gap in gaps)
        if (!whole(gap)) 'letter gap $gap',
      for (final box in boxes)
        if (!whole(left + box.left) || !whole(left + box.right))
          'from ${left + box.left} to ${left + box.right}',
    ];
    if (why.isNotEmpty) out.add('$kind "$text": ${why.join(', ')}');
  }

  final all = TextSelection(baseOffset: 0, extentOffset: 1 << 20);
  final headings = find
      .descendant(
        of: find.byType(ThemedHeading),
        matching: find.byType(RichText),
      )
      .evaluate()
      .toSet();
  for (final e
      in find
          .descendant(of: panels, matching: find.byType(RichText))
          .evaluate()) {
    if (headings.contains(e)) continue;
    final box = e.renderObject! as RenderParagraph;
    final length = box.text.toPlainText().length;
    check(
      'text',
      box.text,
      box.localToGlobal(Offset.zero).dx,
      box.getBoxesForSelection(all.copyWith(extentOffset: length)),
    );
  }
  for (final e
      in find
          .descendant(of: panels, matching: find.byType(EditableText))
          .evaluate()) {
    final box = tester
        .state<EditableTextState>(find.byWidget(e.widget))
        .renderEditable;
    final span = box.text;
    if (span == null) continue;
    final length = span.toPlainText().length;
    check(
      'field',
      span,
      box.localToGlobal(Offset.zero).dx,
      box.getBoxesForSelection(all.copyWith(extentOffset: length)),
    );
  }
  return out;
}
