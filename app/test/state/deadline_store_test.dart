import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

// Deadlines in the store: an event marked in its card, due at its end, ticked
// done in the Deadlines panel.

// Saturday 18 October 2026, 12:00.
final now = WallTime(day: d('2026-10-18'), minute: 12 * 60);

EventItem essay({String day = '2026-10-20', bool isDeadline = true}) =>
    EventItem(
      id: 'essay',
      title: 'Essay',
      start: WallTime(day: d(day), minute: 15 * 60),
      end: WallTime(day: d(day), minute: 17 * 60),
      isDeadline: isDeadline,
    );

void main() {
  group('DeadlineStore', () {
    test('the card saves an event as a deadline', () {
      final s = makeStore(clock: now);
      s.newEvent(on: d('2026-10-20'));
      final draft = EventDraft.setDeadline(
        s.editingEvent!.item.copyWith(title: 'Essay'),
        true,
      );
      s.saveEvent(draft, from: null);
      final saved = s.repos.events.all().single;
      expect(saved.isDeadline, isTrue);
      expect(s.deadlineSections.coming.map((e) => e.title), ['Essay']);
    });

    test('a deadline is coming, then missed when its time passes', () {
      final s = makeStore(clock: now);
      s.repos.events.save(essay());
      expect(s.deadlineSections.coming.map((e) => e.id), ['essay']);
      s.clockOverride = WallTime(day: d('2026-10-21'), minute: 9 * 60);
      expect(s.deadlineSections.coming, isEmpty);
      expect(s.deadlineSections.missed.map((e) => e.id), ['essay']);
    });

    test('a tick puts the time now on it, and it moves to done', () {
      final s = makeStore(clock: now);
      s.repos.events.save(essay());
      s.toggleDeadlineDone('essay');
      final e = s.repos.events.get('essay')!;
      expect(e.doneAt, '2026-10-18T12:00:00');
      expect(s.undoName, 'Complete Deadline');
      expect(s.deadlineSections.done.map((e) => e.id), ['essay']);
      expect(DeadlineRules.marginText(e), 'Done 2d 5h early');
    });

    test('a second tick takes it away, and both are one undo step', () {
      final s = makeStore(clock: now);
      s.repos.events.save(essay());
      s.toggleDeadlineDone('essay');
      s.toggleDeadlineDone('essay');
      expect(s.repos.events.get('essay')!.doneAt, isNull);
      expect(s.undoName, 'Reopen Deadline');
      s.undo();
      expect(s.repos.events.get('essay')!.doneAt, isNotNull);
      s.undo();
      expect(s.repos.events.get('essay')!.doneAt, isNull);
      s.redo();
      expect(s.repos.events.get('essay')!.doneAt, isNotNull);
    });

    test('a plain event cannot be ticked as a deadline', () {
      final s = makeStore(clock: now);
      s.repos.events.save(essay(isDeadline: false));
      s.toggleDeadlineDone('essay');
      expect(s.repos.events.get('essay')!.doneAt, isNull);
      expect(s.undoName, isNull);
      expect(s.deadlineSections.isEmpty, isTrue);
    });

    test('a tick gives no persona points', () {
      final s = makeStore(clock: now);
      s.repos.events.save(essay());
      s.toggleDeadlineDone('essay');
      expect(s.skillPoints, isEmpty);
    });

    test('turning the deadline off in the card takes the tick away', () {
      final done = essay().copyWith(doneAt: '2026-10-18T12:00:00');
      final off = EventDraft.setDeadline(done, false);
      expect(off.isDeadline, isFalse);
      expect(off.doneAt, isNull);
      final on = EventDraft.setDeadline(done, true);
      expect(on.doneAt, '2026-10-18T12:00:00');
    });

    test('the planner block of a deadline has the flag, and the tick', () {
      final s = makeStore(clock: now);
      s.repos.events.save(essay());
      PlannerBlock block() => s.blocks(DayRange.single(d('2026-10-20'))).single;
      expect(block().isDeadline, isTrue);
      expect(block().isDone, isFalse);
      s.toggleDeadlineDone('essay');
      expect(block().isDone, isTrue);
    });
  });
}
