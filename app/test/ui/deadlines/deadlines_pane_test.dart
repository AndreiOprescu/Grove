import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/ui/deadlines/deadlines_pane.dart';

import '../tasks/tasks_support.dart';

// The clock of `paneStore` is Wednesday 7 October 2026, 10:00.

Finder byKey(String key) => find.byKey(ValueKey(key));

EventItem deadline(
  String id, {
  required String day,
  int end = 17 * 60,
  String? doneAt,
}) => EventItem(
  id: id,
  title: id,
  start: WallTime(day: d(day), minute: end - 60),
  end: WallTime(day: d(day), minute: end),
  isDeadline: true,
  doneAt: doneAt,
);

Future<AppStore> pumpDeadlines(
  WidgetTester tester, {
  List<EventItem> events = const [],
}) async {
  final store = paneStore();
  for (final e in events) {
    store.repos.events.save(e);
  }
  await pumpPane(tester, DeadlinesPane(store: store));
  return store;
}

Future<void> tapOn(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('an empty panel says how to make a deadline', (tester) async {
    await pumpDeadlines(tester);
    expect(find.text('Deadlines'), findsOneWidget);
    expect(find.text('Nothing due'), findsOneWidget);
    expect(byKey('deadlines-empty'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('missed, coming and a folded done part', (tester) async {
    await pumpDeadlines(
      tester,
      events: [
        deadline('Essay', day: '2026-10-09'),
        deadline('Form', day: '2026-10-06'),
        deadline('Talk', day: '2026-10-08', doneAt: '2026-10-06T15:00:00'),
      ],
    );
    expect(find.text('2 open'), findsOneWidget);
    expect(find.text('Missed · 1'), findsOneWidget);
    expect(find.text('Coming · 1'), findsOneWidget);
    expect(find.text('Tue 6 Oct, 17:00 · missed by 17h'), findsOneWidget);
    expect(find.text('Fri 9 Oct, 17:00 · in 2d 7h'), findsOneWidget);
    expect(find.text('Talk'), findsNothing);

    await tapOn(tester, byKey('deadlines-done-toggle'));
    expect(find.text('Talk'), findsOneWidget);
    expect(find.text('Tomorrow 17:00 · Done 2d 2h early'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the tick moves a deadline to done, and back', (tester) async {
    final store = await pumpDeadlines(
      tester,
      events: [deadline('Essay', day: '2026-10-09')],
    );
    await tapOn(tester, byKey('deadline-check-Essay'));
    expect(store.repos.events.get('Essay')!.doneAt, '2026-10-07T10:00:00');
    expect(find.text('Done · 1'), findsOneWidget);
    expect(find.text('Nothing due'), findsOneWidget);

    await tapOn(tester, byKey('deadlines-done-toggle'));
    await tapOn(tester, byKey('deadline-check-Essay'));
    expect(store.repos.events.get('Essay')!.doneAt, isNull);
    expect(find.text('Coming · 1'), findsOneWidget);
  });

  testWidgets('a tap on the title opens the card of the event; on a phone '
      'the panel closes first', (tester) async {
    final store = await pumpDeadlines(
      tester,
      events: [deadline('Essay', day: '2026-10-09')],
    );
    store.leftPane = LeftPane.deadlines;
    await tester.pumpAndSettle();
    await tapOn(tester, byKey('deadline-row-Essay'));
    expect(store.editingEvent?.item.id, 'Essay');
    // The panel is 320 points wide here: the phone layout.
    expect(store.leftPane, isNull);
  });
}
