// The Day Planner on a real device (milestone F7): create, drag, resize,
// overlap and undo. Then the screens of milestone F9: the Day Spread, the
// card of an event and a note. It runs on the Mac, on Windows, on an iOS
// simulator and on an Android emulator:
//   ./scripts/flutter_integration.sh macos|windows|ios|android
//
// A phone uses a finger: press, hold, then drag. A computer uses the mouse.
// A narrow screen shows one day column, so the drag to the next day runs only
// when the next day is on the screen.
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/core/model/day_key.dart';
import 'package:grove/core/model/task.dart';
import 'package:grove/data/data.dart';
import 'package:grove/state/state.dart';
import 'package:grove/ui/calendar/event_editor.dart';
import 'package:grove/ui/calendar/month_view.dart';
import 'package:grove/ui/notes/note_editor_pane.dart';
import 'package:grove/ui/shell/shell_layout.dart';
import 'package:grove/ui/spread/day_spread_view.dart';
import 'package:grove/ui/store_app.dart';
import 'package:grove/ui/tasks/task_inspector.dart';
import 'package:integration_test/integration_test.dart';

/// A Wednesday. "Now" is 11:00 on this day, so the grid opens at 10:00.
final wednesday = DayKey('2026-10-07');

bool get _finger =>
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS;

bool get _apple =>
    defaultTargetPlatform == TargetPlatform.macOS ||
    defaultTargetPlatform == TargetPlatform.iOS;

/// A store on an empty database in memory. Motion is off, so the screen
/// comes to rest.
AppStore _store() {
  final store = AppStore(
    repos: Repos(Database.inMemory()),
    prefs: MemoryPrefs()..set('appearance.motion', false),
  );
  store.clockOverride = WallTime(day: wednesday, minute: 11 * 60);
  addTearDown(store.dispose);
  store
    ..selectedDay = wednesday
    ..screen = Screen.planner;
  return store;
}

Future<void> _open(WidgetTester tester, AppStore store) async {
  await tester.pumpWidget(StoreApp(key: UniqueKey(), store: store));
  // Take the tree down at the end, before the store is closed.
  addTearDown(() => tester.pumpWidget(const SizedBox()));
  await tester.pumpAndSettle();
}

void _lunch(AppStore store) => store.createFromDraft(
  title: 'Lunch',
  day: wednesday,
  start: 11 * 60 + 30,
  end: 12 * 60 + 30,
  asEvent: true,
);

PlannerBlock _named(AppStore store, String title) => store
    .blocks(DayRange(wednesday.adding(days: -7), wednesday.adding(days: 7)))
    .firstWhere((b) => b.title == title);

Finder _block(String id) => find.byKey(ValueKey('block-$id'));

Finder _column(DayKey day) => find.byKey(ValueKey('day-column-${day.string}'));

Finder _key(String name) => find.byKey(ValueKey(name));

/// The text field inside the widget with this key.
Finder _field(String name) =>
    find.descendant(of: _key(name), matching: find.byType(EditableText));

/// A phone shows one part of a screen at a time.
bool _phone(WidgetTester tester) =>
    ShellRules.layoutFor(
      tester.view.physicalSize.width / tester.view.devicePixelRatio,
    ) ==
    ShellLayout.phone;

/// The point of the day column at `minute`, in window points.
Offset _at(WidgetTester tester, AppStore store, DayKey day, int minute) {
  final column = tester.getRect(_column(day));
  return Offset(
    column.center.dx,
    column.top + minute / 60 * store.plannerHourHeight,
  );
}

/// A drag with the pointer of this device. A finger holds first, or the
/// planner would scroll. An edge of a block needs no hold.
Future<void> _drag(
  WidgetTester tester,
  Offset from,
  Offset offset, {
  bool hold = true,
}) async {
  final gesture = await tester.startGesture(
    from,
    kind: _finger ? PointerDeviceKind.touch : PointerDeviceKind.mouse,
  );
  await tester.pump(Duration(milliseconds: _finger && hold ? 600 : 16));
  for (var i = 1; i <= 8; i++) {
    await gesture.moveTo(from + offset * (i / 8));
    await tester.pump(const Duration(milliseconds: 16));
  }
  await gesture.up();
  await tester.pumpAndSettle();
}

/// The command key of this device with `key`: Cmd on Apple devices, Ctrl on
/// the others.
Future<void> _command(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool shift = false,
}) async {
  final command = _apple
      ? LogicalKeyboardKey.metaLeft
      : LogicalKeyboardKey.controlLeft;
  await tester.sendKeyDownEvent(command);
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(key);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(command);
  await tester.pumpAndSettle();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('create: a drag on empty time makes a block', (tester) async {
    final store = _store();
    await _open(tester, store);

    await _drag(
      tester,
      _at(tester, store, wednesday, 11 * 60 + 30),
      Offset(0, store.plannerHourHeight),
    );
    final draft = find.byKey(const ValueKey('planner-draft'));
    expect(draft, findsOneWidget);
    // Nothing is saved before the title.
    expect(store.blocks(DayRange.single(wednesday)), isEmpty);

    await tester.enterText(
      find.descendant(of: draft, matching: find.byType(EditableText)),
      'Write report',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    final block = _named(store, 'Write report');
    expect(block.day, wednesday);
    expect(block.startMinute, 11 * 60 + 30);
    expect(block.endMinute, 12 * 60 + 30);
    expect(draft, findsNothing);
    expect(_block(block.id), findsOneWidget);
  });

  testWidgets('drag: a block moves to a new time and to the next day', (
    tester,
  ) async {
    final store = _store();
    _lunch(store);
    await _open(tester, store);

    await _drag(
      tester,
      _at(tester, store, wednesday, 12 * 60),
      Offset(0, store.plannerHourHeight / 2),
    );
    var block = _named(store, 'Lunch');
    expect(block.day, wednesday);
    expect(block.startMinute, 12 * 60);
    expect(block.endMinute, 13 * 60);

    final thursday = wednesday.adding(days: 1);
    if (_column(thursday).evaluate().isNotEmpty) {
      final from = _at(tester, store, wednesday, 12 * 60 + 30);
      final to = _at(tester, store, thursday, 12 * 60 + 30);
      await _drag(tester, from, to - from);
      block = _named(store, 'Lunch');
      expect(block.day, thursday);
      expect(block.startMinute, 12 * 60);
      expect(block.endMinute, 13 * 60);
    }
  });

  testWidgets('resize: the bottom edge changes the end', (tester) async {
    final store = _store();
    _lunch(store);
    final id = _named(store, 'Lunch').id;
    await _open(tester, store);

    final handle = tester.getCenter(find.byKey(ValueKey('resizeBottom-$id')));
    await _drag(
      tester,
      handle,
      Offset(0, store.plannerHourHeight / 2),
      hold: false,
    );

    final block = _named(store, 'Lunch');
    expect(block.startMinute, 11 * 60 + 30);
    expect(block.endMinute, 13 * 60);
  });

  testWidgets('overlap: two blocks at the same time are both in view', (
    tester,
  ) async {
    final store = _store();
    store
      ..createFromDraft(
        title: 'First',
        day: wednesday,
        start: 11 * 60,
        end: 13 * 60,
        asEvent: true,
      )
      ..createFromDraft(
        title: 'Second',
        day: wednesday,
        start: 11 * 60 + 30,
        end: 12 * 60 + 30,
        asEvent: true,
      );
    await _open(tester, store);

    final first = tester.getRect(_block(_named(store, 'First').id));
    final second = tester.getRect(_block(_named(store, 'Second').id));
    final column = tester.getRect(_column(wednesday));
    // The later block starts more to the right and stays in the column.
    expect(second.left, greaterThan(first.left));
    expect(second.right, lessThanOrEqualTo(column.right));
    expect(first.left, greaterThanOrEqualTo(column.left));
    expect(find.text('First'), findsOneWidget);
    expect(find.text('Second'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('undo: Undo puts a moved block back; Redo moves it again', (
    tester,
  ) async {
    final store = _store();
    _lunch(store);
    await _open(tester, store);
    await _drag(
      tester,
      _at(tester, store, wednesday, 12 * 60),
      Offset(0, store.plannerHourHeight / 2),
    );
    expect(_named(store, 'Lunch').startMinute, 12 * 60);

    await _command(tester, LogicalKeyboardKey.keyZ);
    expect(_named(store, 'Lunch').startMinute, 11 * 60 + 30);
    expect(
      tester.getTopLeft(_block(_named(store, 'Lunch').id)).dy,
      closeTo(_at(tester, store, wednesday, 11 * 60 + 30).dy, 1.5),
    );

    await _command(tester, LogicalKeyboardKey.keyZ, shift: true);
    expect(_named(store, 'Lunch').startMinute, 12 * 60);
    // Let the short message at the bottom of the window go away.
    await tester.pump(const Duration(milliseconds: 2500));
    await tester.pumpAndSettle();
  });

  testWidgets('today: the Day Spread opens, a tap on a task opens its panel', (
    tester,
  ) async {
    final store = _store()..screen = Screen.today;
    store.repos.tasks.save(
      TaskItem(
        id: 'report',
        title: 'Write the report',
        bucket: TaskBucket.day,
        planDate: wednesday,
      ),
    );
    store.repos.tasks.save(
      TaskItem(id: 'bread', title: 'Buy bread', bucket: TaskBucket.inbox),
    );
    await _open(tester, store);
    expect(find.byType(DaySpreadView), findsOneWidget);
    expect(find.text('Wednesday 7 October'), findsOneWidget);
    expect(_column(wednesday), findsOneWidget);

    // A wide window has the tasks of today beside the timeline. A phone has
    // the tasks in the panel at the left.
    var row = 'task-report';
    if (_phone(tester)) {
      store.leftPane = LeftPane.tasks;
      await tester.pumpAndSettle();
      row = 'task-bread';
    }
    expect(_key(row).hitTestable(), findsOneWidget);
    await tester.tap(_key(row));
    await tester.pumpAndSettle();
    expect(store.selectedTaskId, row.substring('task-'.length));
    expect(find.byType(TaskInspector), findsOneWidget);
  });

  testWidgets('calendar: the card of a new event saves the event', (
    tester,
  ) async {
    final store = _store()..screen = Screen.calendar;
    await _open(tester, store);
    expect(find.byType(MonthView), findsOneWidget);

    final day = wednesday.adding(days: 8);
    store.newEvent(on: day);
    await tester.pumpAndSettle();
    expect(find.byType(EventEditor), findsOneWidget);
    await tester.enterText(_field('event-title'), 'Dentist');
    await tester.pumpAndSettle();
    await tester.ensureVisible(_key('event-save'));
    await tester.pumpAndSettle();
    await tester.tap(_key('event-save'));
    await tester.pumpAndSettle();
    expect(find.byType(EventEditor), findsNothing);
    final saved = store.eventItems(DayRange(day, day)).single;
    expect(saved.title, 'Dentist');
    expect(saved.allDay, isTrue);
    expect(find.text('Dentist'), findsOneWidget);
  });

  testWidgets('notes: the text of a note is saved a moment after typing', (
    tester,
  ) async {
    final store = _store()..screen = Screen.notes;
    await _open(tester, store);
    expect(find.text('No notes here yet.'), findsOneWidget);

    await tester.tap(_key('notes-new'));
    await tester.pumpAndSettle();
    final note = store.notes().single;
    expect(store.selectedNoteId, note.id);
    expect(find.byType(NoteEditorPane), findsOneWidget);

    await tester.enterText(_field('note-text'), 'Hello from the device');
    await tester.pump();
    await tester.pump(NoteEditorPane.saveDelay);
    await tester.pumpAndSettle();
    expect(store.note(note.id)!.body, 'Hello from the device');
  });
}
