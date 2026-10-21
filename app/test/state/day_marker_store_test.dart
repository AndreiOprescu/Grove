// The wake-up line and the sleep line of a day in the planner: the store
// calls, the rules for a new line, undo, a restart of the app, export and
// import, and the sync between two devices.
import 'package:flutter_test/flutter_test.dart';

import '../data/helpers.dart' show tempDir;
import 'sync_support.dart';

final monday = d('2026-10-05');
final tuesday = d('2026-10-06');
final wednesday = d('2026-10-07');
final thursday = d('2026-10-08');

const wake = DayMarkerKind.wake;
const sleep = DayMarkerKind.sleep;

/// The lines of Monday to Thursday as "day kind minute".
List<String> lines(AppStore s) => [
  for (final m in s.dayMarkers(DayRange(monday, thursday)))
    '${m.day.string} ${m.kind.name} ${m.minute}',
];

AppStore openStore(String dir) {
  final s = AppStore.open(dataDir: dir, prefs: MemoryPrefs());
  addTearDown(() {
    if (!s.isDisposed) s.dispose();
  });
  return s;
}

void main() {
  group('A new line', () {
    test('a day has no line until one is added', () {
      final s = makeStore();
      expect(lines(s), isEmpty);
      expect(s.dayMarker(wake, wednesday), isNull);
      expect(s.dayMarker(sleep, wednesday), isNull);
    });

    test('the first wake-up line is at 07:00, the first sleep line at '
        '23:00', () {
      final s = makeStore();
      expect(s.addDayMarker(wake, wednesday), 7 * 60);
      expect(s.addDayMarker(sleep, wednesday), 23 * 60);
      expect(s.dayMarker(wake, wednesday), 7 * 60);
      expect(s.dayMarker(sleep, wednesday), 23 * 60);
      expect(lines(s), ['2026-10-07 wake 420', '2026-10-07 sleep 1380']);
    });

    test('a line belongs to one day', () {
      final s = makeStore();
      s.addDayMarker(wake, wednesday);
      expect(s.dayMarker(wake, tuesday), isNull);
      expect(s.dayMarker(wake, thursday), isNull);
      expect(s.dayMarkers(DayRange.single(thursday)), isEmpty);
    });

    test('a new line takes the time of the last day before that has one', () {
      final s = makeStore();
      s
        ..addDayMarker(wake, monday)
        ..moveDayMarker(wake, monday, 6 * 60)
        ..addDayMarker(wake, tuesday)
        ..moveDayMarker(wake, tuesday, 6 * 60 + 30);
      expect(s.addDayMarker(wake, thursday), 6 * 60 + 30);
      // The sleep line has its own time. It does not take the wake-up time.
      expect(s.addDayMarker(sleep, thursday), 23 * 60);
    });

    test('with no day before, it takes the time of the next day that has '
        'one', () {
      final s = makeStore();
      s
        ..addDayMarker(sleep, thursday)
        ..moveDayMarker(sleep, thursday, 22 * 60 + 15)
        ..addDayMarker(sleep, wednesday)
        ..moveDayMarker(sleep, wednesday, 21 * 60);
      expect(s.addDayMarker(sleep, monday), 21 * 60);
    });

    test('adding a line that is there changes nothing', () {
      final s = makeStore();
      s
        ..addDayMarker(wake, wednesday)
        ..moveDayMarker(wake, wednesday, 8 * 60);
      final steps = s.undoStack.length;
      expect(s.addDayMarker(wake, wednesday), 8 * 60);
      expect(s.dayMarker(wake, wednesday), 8 * 60);
      expect(s.undoStack.length, steps);
    });

    test('a line added at a time starts there, on the 15-minute grid', () {
      final s = makeStore();
      s
        ..addDayMarker(wake, tuesday)
        ..moveDayMarker(wake, tuesday, 6 * 60);
      expect(s.addDayMarker(wake, wednesday, at: 7 * 60 + 38), 7 * 60 + 45);
      expect(s.dayMarker(wake, wednesday), 7 * 60 + 45);
      expect(s.undoName, 'Add Wake-up Line');

      s.undo();
      expect(s.dayMarker(wake, wednesday), isNull);
    });

    test('a line that is there keeps its time when added at a time', () {
      final s = makeStore();
      s.addDayMarker(sleep, wednesday);
      final steps = s.undoStack.length;
      expect(s.addDayMarker(sleep, wednesday, at: 22 * 60), 23 * 60);
      expect(s.dayMarker(sleep, wednesday), 23 * 60);
      expect(s.undoStack.length, steps);
    });
  });

  group('Moving and removing a line', () {
    test('a move changes only that line of that day', () {
      final s = makeStore();
      s
        ..addDayMarker(wake, wednesday)
        ..addDayMarker(sleep, wednesday)
        ..addDayMarker(wake, thursday)
        ..moveDayMarker(wake, wednesday, 6 * 60 + 45);
      expect(lines(s), [
        '2026-10-07 wake 405',
        '2026-10-07 sleep 1380',
        '2026-10-08 wake 420',
      ]);
    });

    test('a time snaps to 15 minutes and stays in the day', () {
      final s = makeStore();
      s.addDayMarker(wake, wednesday);
      s.moveDayMarker(wake, wednesday, 6 * 60 + 52);
      expect(s.dayMarker(wake, wednesday), 6 * 60 + 45);
      s.moveDayMarker(wake, wednesday, 6 * 60 + 53);
      expect(s.dayMarker(wake, wednesday), 7 * 60);
      s.moveDayMarker(wake, wednesday, -200);
      expect(s.dayMarker(wake, wednesday), 0);
      s.moveDayMarker(wake, wednesday, 5000);
      expect(s.dayMarker(wake, wednesday), 23 * 60 + 45);
    });

    test('the two lines have no order: sleep can be above wake-up', () {
      final s = makeStore();
      s
        ..addDayMarker(wake, wednesday)
        ..addDayMarker(sleep, wednesday)
        // To bed at 00:30, after midnight: the top of the day.
        ..moveDayMarker(sleep, wednesday, 30);
      expect(s.dayMarker(sleep, wednesday), 30);
      expect(s.dayMarker(wake, wednesday), 7 * 60);
    });

    test('a line does not move or block a task', () {
      final s = makeStore();
      s.createFromDraft(
        title: 'Run',
        day: wednesday,
        start: 7 * 60,
        end: 8 * 60,
        asEvent: false,
      );
      String blocks() => [
        for (final b in s.blocks(DayRange.single(wednesday)))
          '${b.title} ${b.startMinute}-${b.endMinute}',
      ].join(', ');
      final before = blocks();
      final planned = s.plannedMinutes(wednesday);
      s
        ..addDayMarker(wake, wednesday)
        ..moveDayMarker(wake, wednesday, 7 * 60 + 30)
        ..addDayMarker(sleep, wednesday)
        ..moveDayMarker(sleep, wednesday, 7 * 60 + 15);
      expect(blocks(), before);
      expect(s.plannedMinutes(wednesday), planned);
    });

    test('a move of a line that is not there does nothing', () {
      final s = makeStore();
      s.moveDayMarker(wake, wednesday, 8 * 60);
      expect(s.dayMarker(wake, wednesday), isNull);
      expect(s.undoName, isNull);
    });

    test('a move to the same time is no undo step', () {
      final s = makeStore();
      s.addDayMarker(wake, wednesday);
      final steps = s.undoStack.length;
      s.moveDayMarker(wake, wednesday, 7 * 60 + 3);
      expect(s.undoStack.length, steps);
    });

    test('a removed line is gone, the other one stays', () {
      final s = makeStore();
      s
        ..addDayMarker(wake, wednesday)
        ..addDayMarker(sleep, wednesday)
        ..removeDayMarker(wake, wednesday);
      expect(lines(s), ['2026-10-07 sleep 1380']);
      // Removing it again does nothing.
      final steps = s.undoStack.length;
      s.removeDayMarker(wake, wednesday);
      expect(s.undoStack.length, steps);
    });

    test('each change tells the screens', () {
      final s = makeStore();
      var before = s.revision;
      s.addDayMarker(wake, wednesday);
      expect(s.revision, greaterThan(before));
      before = s.revision;
      s.moveDayMarker(wake, wednesday, 8 * 60);
      expect(s.revision, greaterThan(before));
      before = s.revision;
      s.removeDayMarker(wake, wednesday);
      expect(s.revision, greaterThan(before));
    });

    test('a value that is not a time is not a line', () {
      final s = makeStore();
      s.repos.settings.set('planner.wake.2026-10-07', 'soon');
      s.repos.settings.set('planner.sleep.2026-10-07', '99999');
      s.repos.settings.set('planner.wake.someday', '300');
      expect(lines(s), ['2026-10-07 sleep 1425']);
      expect(s.dayMarker(wake, wednesday), isNull);
    });
  });

  group('Undo', () {
    test('add, move and remove are one step each, with a name', () {
      final s = makeStore();
      s.addDayMarker(wake, wednesday);
      expect(s.undoName, 'Add Wake-up Line');
      s.moveDayMarker(wake, wednesday, 6 * 60);
      expect(s.undoName, 'Move Wake-up Line');
      s.removeDayMarker(wake, wednesday);
      expect(s.undoName, 'Remove Wake-up Line');
      expect(s.undoStack.length, 3);

      s.undo();
      expect(s.dayMarker(wake, wednesday), 6 * 60);
      s.undo();
      expect(s.dayMarker(wake, wednesday), 7 * 60);
      s.undo();
      expect(s.dayMarker(wake, wednesday), isNull);
      expect(s.undoName, isNull);

      s.redo();
      expect(s.dayMarker(wake, wednesday), 7 * 60);
      s.redo();
      expect(s.dayMarker(wake, wednesday), 6 * 60);
      s.redo();
      expect(s.dayMarker(wake, wednesday), isNull);
    });

    test('the sleep line has its own names', () {
      final s = makeStore();
      s.addDayMarker(sleep, wednesday);
      expect(s.undoName, 'Add Sleep Line');
      s.moveDayMarker(sleep, wednesday, 22 * 60);
      expect(s.undoName, 'Move Sleep Line');
      s.removeDayMarker(sleep, wednesday);
      expect(s.undoName, 'Remove Sleep Line');
    });

    test('undo after a move of a line does not undo an older block move', () {
      final s = makeStore();
      s.createFromDraft(
        title: 'Run',
        day: wednesday,
        start: 9 * 60,
        end: 10 * 60,
        asEvent: false,
      );
      s.addDayMarker(wake, wednesday);
      s.moveDayMarker(wake, wednesday, 8 * 60);
      s.undo();
      expect(s.dayMarker(wake, wednesday), 7 * 60);
      expect(s.blocks(DayRange.single(wednesday)).single.title, 'Run');
    });

    test('two moves of a line are two steps', () {
      final s = makeStore();
      s
        ..addDayMarker(wake, wednesday)
        ..moveDayMarker(wake, wednesday, 6 * 60)
        ..moveDayMarker(wake, wednesday, 5 * 60);
      expect(s.undoStack.length, 3);
      s.undo();
      expect(s.dayMarker(wake, wednesday), 6 * 60);
    });
  });

  group('The lines stay', () {
    test('after the app starts again', () {
      final dir = tempDir('grove-day-markers').path;
      final first = openStore(dir);
      first
        ..addDayMarker(wake, wednesday)
        ..moveDayMarker(wake, wednesday, 6 * 60 + 15)
        ..addDayMarker(sleep, wednesday)
        ..moveDayMarker(sleep, wednesday, 22 * 60 + 30)
        ..addDayMarker(wake, thursday)
        ..addDayMarker(sleep, thursday)
        ..removeDayMarker(sleep, thursday);
      first.dispose();
      first.repos.db.close();

      final second = openStore(dir);
      addTearDown(second.repos.db.close);
      // Thursday took the wake-up time of Wednesday when it was added.
      expect(lines(second), [
        '2026-10-07 wake 375',
        '2026-10-07 sleep 1350',
        '2026-10-08 wake 375',
      ]);
    });

    test('in an export file, and after its import', () {
      final a = makeStore();
      a
        ..addDayMarker(wake, wednesday)
        ..moveDayMarker(wake, wednesday, 6 * 60 + 15)
        ..addDayMarker(sleep, wednesday);
      final b = makeStore();
      b.addDayMarker(wake, monday);
      b.importData(a.exportData());
      expect(lines(b), ['2026-10-07 wake 375', '2026-10-07 sleep 1380']);
    });
  });

  group('Sync', () {
    test('a line goes to the other device: added, moved, removed', () async {
      final world = World();
      final a = world.device(), b = world.device();
      await signIn(a, me);
      await signIn(b, me);

      a.store
        ..addDayMarker(wake, wednesday)
        ..addDayMarker(sleep, wednesday);
      await a.store.syncNow();
      final seen = b.store.revision;
      await b.store.syncNow();
      expect(lines(b.store), ['2026-10-07 wake 420', '2026-10-07 sleep 1380']);
      // The screens of the other device draw again.
      expect(b.store.revision, greaterThan(seen));

      b.store.moveDayMarker(wake, wednesday, 6 * 60 + 30);
      await b.store.syncNow();
      await a.store.syncNow();
      expect(a.store.dayMarker(wake, wednesday), 6 * 60 + 30);

      a.store.removeDayMarker(sleep, wednesday);
      await a.store.syncNow();
      await b.store.syncNow();
      expect(lines(b.store), ['2026-10-07 wake 390']);
    });

    test('wake-up moved on one device and sleep on the other: both moves '
        'stay', () async {
      final world = World();
      final a = world.device(), b = world.device();
      await signIn(a, me);
      await signIn(b, me);
      a.store
        ..addDayMarker(wake, wednesday)
        ..addDayMarker(sleep, wednesday);
      await a.store.syncNow();
      await b.store.syncNow();

      a.store.moveDayMarker(wake, wednesday, 6 * 60);
      b.store.moveDayMarker(sleep, wednesday, 22 * 60);
      await a.store.syncNow();
      await b.store.syncNow();
      await a.store.syncNow();
      const both = ['2026-10-07 wake 360', '2026-10-07 sleep 1320'];
      expect(lines(a.store), both);
      expect(lines(b.store), both);
    });
  });
}
