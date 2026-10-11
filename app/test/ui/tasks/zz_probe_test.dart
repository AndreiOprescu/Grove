// TEMPORARY. It goes away again in the next commit.
//
// Some golden pictures of the Tasks panel are close to the limit of the
// compare on Linux. This file draws the same scenes as
// `tasks_golden_test.dart` and prints, in the log of each CI job, WHERE the
// pixels are that the compare counts as different from the macOS picture:
// in a heading, in an icon, in another text, or in no text at all. It
// changes no picture and it never fails for a difference.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/ui/store_app.dart';
import 'package:grove/ui/tasks/task_inspector.dart';
import 'package:grove/ui/tasks/tasks_pane.dart';
import 'package:grove/ui/theme/panel.dart';

import '../planner/planner_support.dart' show plannerStore, pumpPlanner;
import 'tasks_support.dart';

/// A desktop window with room for the two panels and the planner.
const wideSize = Size(1360, 800);

/// Tasks of every kind: late, with no day, done today, with a priority, a
/// colour, a due date, tags and subtasks. All ids are fixed.
AppStore _scene({ThemeId theme = ThemeId.grove, bool dark = false}) {
  final store = plannerStore(now: 10 * 60 + 20);
  store
    ..setTheme(theme)
    ..setAppearance(dark ? AppearanceMode.dark : AppearanceMode.light);
  addTask(
    store,
    'Send the invoice',
    id: 'invoice',
    day: wednesday.adding(days: -2),
    priority: 2,
    sort: 1,
  );
  addTask(
    store,
    'Fix the bike',
    id: 'bike',
    day: wednesday.adding(days: -1),
    color: 'teal',
    estimateMin: 60,
    sort: 2,
  );
  addTask(
    store,
    'Renew the passport',
    id: 'passport',
    bucket: TaskBucket.inbox,
    priority: 3,
    due: '2026-10-09',
    sort: 3,
  );
  addTask(
    store,
    'Plan the birthday party',
    id: 'party',
    bucket: TaskBucket.inbox,
    priority: 1,
    color: 'purple',
    estimateMin: 90,
    due: '2026-10-16T18:00',
    notes: 'Ask Ana for the list of guests.\nBook the room before Friday.',
    sort: 4,
  );
  addTask(
    store,
    'Book the dentist',
    id: 'dentist',
    bucket: TaskBucket.inbox,
    estimateMin: 15,
    sort: 5,
  );
  addTask(
    store,
    'Water the plants',
    id: 'plants',
    bucket: TaskBucket.inbox,
    sort: 6,
  );
  store
    ..setSummary('party', 'Saturday, at home')
    ..setTags(taskId: 'party', to: ['family', 'home'])
    ..toggleDone(taskId: 'plants');
  store.repos.tasks
    ..save(
      TaskItem(id: 'party-1', title: 'Invite the guests', parentId: 'party'),
    )
    ..save(
      TaskItem(
        id: 'party-2',
        title: 'Order the cake',
        parentId: 'party',
        sort: 1,
        estimateMin: 15,
        status: TaskStatus.done,
        completedAt: '2026-10-06T09:00:00',
      ),
    );
  return store;
}

/// The same tasks, planned for today. For the list of the Today screen.
AppStore _today() {
  final store = paneStore(now: 10 * 60 + 20);
  addTask(store, 'Send the invoice', id: 'invoice', priority: 3, sort: 1);
  addTask(
    store,
    'Fix the bike',
    id: 'bike',
    color: 'teal',
    estimateMin: 60,
    priority: 2,
    sort: 2,
  );
  addTask(
    store,
    'Plan the birthday party',
    id: 'party',
    priority: 1,
    color: 'purple',
    due: '2026-10-09',
    sort: 3,
  );
  addTask(store, 'Book the dentist', id: 'dentist', estimateMin: 15, sort: 4);
  addTask(store, 'Water the plants', id: 'plants', sort: 5);
  store.repos.tasks.save(
    TaskItem(id: 'party-1', title: 'Invite the guests', parentId: 'party'),
  );
  store.toggleDone(taskId: 'plants');
  // An open task with a block yesterday: the card of yesterday shows.
  final yesterday = wednesday.adding(days: -1);
  addTask(store, 'Email the bank', id: 'bank', day: yesterday);
  store.repos.events.save(
    EventItem(
      id: 'bank-block',
      title: 'Email the bank',
      start: WallTime(day: yesterday, minute: 540),
      end: WallTime(day: yesterday, minute: 600),
      kind: EventKind.block,
      taskId: 'bank',
    ),
  );
  return store;
}

/// A part of the picture with a name: a heading, an icon, a text, a panel.
typedef Zone = ({String name, Rect rect});

/// The parts of the picture, the most exact first: the headings, the icons,
/// the other texts, then the two panels of Track A.
List<Zone> zones(WidgetTester tester) {
  final headings = find
      .descendant(
        of: find.byType(ThemedHeading),
        matching: find.byType(RichText),
      )
      .evaluate()
      .toSet();
  final byKind = <String, List<Zone>>{'heading': [], 'icon': [], 'text': []};
  for (final e in find.byType(RichText).evaluate()) {
    final box = e.renderObject! as RenderParagraph;
    if (!box.hasSize) continue;
    final style = box.text.style;
    final at = box.localToGlobal(Offset.zero);
    final text = box.text.toPlainText().replaceAll('\n', ' ');
    final short = text.length > 22 ? text.substring(0, 22) : text;
    final place =
        'size ${style?.fontSize} gap ${style?.letterSpacing} '
        '${style?.fontStyle == FontStyle.italic ? 'italic ' : ''}'
        'at ${at.dx.toStringAsFixed(2)},${at.dy.toStringAsFixed(2)} '
        'box ${box.size.width.toStringAsFixed(2)}x'
        '${box.size.height.toStringAsFixed(2)}';
    final kind = headings.contains(e)
        ? 'heading'
        : style?.fontFamily == 'MaterialIcons'
        ? 'icon'
        : 'text';
    byKind[kind]!.add((
      name: kind == 'icon' ? 'an icon' : '$kind "$short" ($place)',
      rect: (at & box.size).inflate(2),
    ));
  }
  return [
    ...byKind['heading']!,
    ...byKind['icon']!,
    ...byKind['text']!,
    for (final e
        in find
            .byWidgetPredicate((w) => w is TasksPane || w is TaskInspector)
            .evaluate())
      (
        name: 'no text, in the panel ${e.widget.runtimeType}',
        rect:
            (e.renderObject! as RenderBox).localToGlobal(Offset.zero) &
            (e.renderObject! as RenderBox).size,
      ),
  ];
}

/// Counts with the rule of [TolerantGoldenComparator] and prints where the
/// counted pixels are. It always says "the same".
class WhereComparator extends LocalFileComparator {
  WhereComparator(super.testFile);

  static List<Zone> parts = const [];

  static const _tolerance = TolerantGoldenComparator.channelTolerance;
  static const _radius = TolerantGoldenComparator.edgeRadius;

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final name = golden.pathSegments.last;
    final now = await _decode(imageBytes);
    final mac = await _decode(Uint8List.fromList(await getGoldenBytes(golden)));
    if (now.width != mac.width || now.height != mac.height) {
      debugPrint('WHERE $name: the sizes differ');
      return true;
    }
    final width = now.width;
    final height = now.height;
    final a = (await now.toByteData())!.buffer.asUint8List();
    final b = (await mac.toByteData())!.buffer.asUint8List();
    now.dispose();
    mac.dispose();

    // One column through the first letter of some texts, from top to bottom:
    // the colour here and on the Mac, row by row.
    for (final part in parts) {
      if (!looked.any(part.name.contains)) continue;
      final x = part.rect.left.round() + 6;
      final line = StringBuffer();
      for (var y = part.rect.top.round(); y < part.rect.bottom.round(); y++) {
        if (x < 0 || x >= width || y < 0 || y >= height) continue;
        final i = (y * width + x) * 4;
        line.write(' $y:${_hex(a, i)}/${_hex(b, i)}');
      }
      debugPrint('WHERE $name: column $x of ${part.name}, here/Mac:$line');
    }

    var all = 0;
    final count = <String, int>{};
    final columns = <String, Set<int>>{};
    final rows = <String, Map<int, int>>{};
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final i = (y * width + x) * 4;
        if (_near(a, b, i)) continue;
        if (_between(a, i, b, x, y, width, height) &&
            _between(b, i, a, x, y, width, height)) {
          continue;
        }
        all++;
        final at = Offset(x + 0.5, y + 0.5);
        var where = 'no text, outside the panels of Track A';
        for (final part in parts) {
          if (part.rect.contains(at)) {
            where = part.name;
            break;
          }
        }
        count[where] = (count[where] ?? 0) + 1;
        (columns[where] ??= {}).add(x);
        final row = rows[where] ??= {};
        row[y] = (row[y] ?? 0) + 1;
      }
    }
    final share = (all * 100 / (width * height)).toStringAsFixed(3);
    debugPrint('WHERE $name: $all pixels counted = $share %');
    var headings = 0;
    var icons = 0;
    var texts = 0;
    var rest = 0;
    for (final e in count.entries) {
      if (e.key.startsWith('heading')) {
        headings += e.value;
      } else if (e.key.startsWith('an icon')) {
        icons += e.value;
      } else if (e.key.startsWith('text')) {
        texts += e.value;
      } else {
        rest += e.value;
      }
    }
    debugPrint(
      'WHERE $name: in a heading $headings, in an icon $icons, '
      'in another text $texts, in no text $rest',
    );
    final sorted = count.entries.toList()
      ..sort((x, y) => y.value.compareTo(x.value));
    for (final e in sorted.take(30)) {
      final xs = columns[e.key]!.toList()..sort();
      debugPrint(
        'WHERE $name: ${e.value} in ${e.key}; columns '
        '${xs.length > 40 ? '${xs.take(40).join(' ')} …' : xs.join(' ')}',
      );
      final ys = rows[e.key]!.entries.toList()
        ..sort((x, y) => x.key.compareTo(y.key));
      debugPrint(
        'WHERE $name: rows of ${e.key.split(' (').first}: '
        '${ys.take(40).map((r) => '${r.key}:${r.value}').join(' ')}',
      );
    }
    return true;
  }

  /// The texts to look at more closely.
  static const looked = [
    'text "Move to today"',
    'text "Leave"',
    'text "due Fri 9 Oct"',
    'heading "TODAY"',
  ];

  static String _hex(Uint8List p, int i) =>
      [for (var c = 0; c < 3; c++) p[i + c].toRadixString(16).padLeft(2, '0')]
          .join();

  static bool _near(Uint8List a, Uint8List b, int i) {
    for (var c = 0; c < 4; c++) {
      if ((a[i + c] - b[i + c]).abs() > _tolerance) return false;
    }
    return true;
  }

  static bool _between(
    Uint8List from,
    int i,
    Uint8List around,
    int x,
    int y,
    int width,
    int height,
  ) {
    for (var c = 0; c < 4; c++) {
      var low = 255;
      var high = 0;
      for (var dy = -_radius; dy <= _radius; dy++) {
        final ny = y + dy;
        if (ny < 0 || ny >= height) continue;
        for (var dx = -_radius; dx <= _radius; dx++) {
          final nx = x + dx;
          if (nx < 0 || nx >= width) continue;
          final value = around[(ny * width + nx) * 4 + c];
          if (value < low) low = value;
          if (value > high) high = value;
        }
      }
      final value = from[i + c];
      if (value < low - _tolerance || value > high + _tolerance) return false;
    }
    return true;
  }

  static Future<ui.Image> _decode(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    codec.dispose();
    return frame.image;
  }
}

void main() {
  setUpAll(() async {
    final current = goldenFileComparator as LocalFileComparator;
    goldenFileComparator = WhereComparator(
      current.basedir.resolve('placeholder_test.dart'),
    );
    await loadIconFont();
  });

  for (final theme in ThemeId.values) {
    testWidgets('where tasks desktop ${theme.name} differs', (tester) async {
      await withRealShadows(() async {
        final store = _scene(theme: theme)
          ..leftPane = LeftPane.tasks
          ..selectedTaskId = 'party';
        await pumpPlanner(tester, store, size: wideSize);
        await tester.tap(find.byKey(const ValueKey('done-toggle')));
        await tester.pumpAndSettle();
        WhereComparator.parts = zones(tester);
        await expectLater(
          find.byType(StoreApp),
          matchesGoldenFile('goldens/tasks_desktop_${theme.name}_light.png'),
        );
      });
    });

    testWidgets('where the list of today ${theme.name} differs', (
      tester,
    ) async {
      await withRealShadows(() async {
        final store = _today();
        await pumpPane(
          tester,
          Padding(
            padding: const EdgeInsets.all(12),
            child: TasksPane(store: store, mode: TasksPaneMode.today),
          ),
          size: const Size(344, 700),
          themeId: theme,
        );
        await tester.tap(find.byKey(const ValueKey('subtasks-party')));
        await tester.pumpAndSettle();
        WhereComparator.parts = zones(tester);
        await expectLater(
          find.byType(Scaffold),
          matchesGoldenFile('goldens/today_list_${theme.name}_light.png'),
        );
      });
    });
  }
}
