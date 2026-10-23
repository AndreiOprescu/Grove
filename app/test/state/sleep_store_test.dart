// The bedtime reminder in the store: nights learned from the use of this
// device, the synced settings, the reminders, a click on one, and "Open
// Grove at login" on the Mac.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/core/sleep/sleep_night.dart';
import 'package:grove/sync/sync.dart' show Outbox;

import 'support.dart';

// 2026-10-04 is a Sunday, 2026-10-05 a Monday.
const sunday = DayKey('2026-10-04');
const monday = DayKey('2026-10-05');

DateTime t(DayKey day, int hour, [int minute = 0]) =>
    DateTime(day.year, day.month, day.day, hour, minute);

/// The phone was used in the evening of [night] and the next morning.
void useAround(
  FakeActivity a,
  DayKey night, {
  int lastUse = 23 * 60 + 30,
  int firstUse = 7 * 60,
}) {
  final next = night.adding(days: 1);
  a
    ..use(t(night, 20), t(night, 0, lastUse))
    ..use(t(next, 0, firstUse), t(next, 0, firstUse + 30));
}

AppStore sleepStore(
  FakeActivity? activity, {
  WallTime now = const WallTime(day: monday, minute: 9 * 60),
  FakeNotifier? notifier,
  Prefs? prefs,
  LoginItem? loginItem,
}) => makeStore(
  activity: activity,
  notifier: notifier,
  prefs: prefs,
  loginItem: loginItem,
  clock: now,
);

SleepNight? night(AppStore s, DayKey day) {
  final key = SleepNightRules.key(day);
  final value = s.repos.settings.get(key);
  return value == null ? null : SleepNightRules.parse(key, value);
}

List<String> nightChanges(AppStore s) => [
  for (final e in Outbox(s.repos.db).entries())
    if (e.table == 'settings' && e.key.startsWith(SleepNightRules.prefix))
      e.key,
];

List<String> bedIds(List<Reminder> list) => [
  for (final r in list)
    if (r.id.startsWith('bed-')) r.id,
];

void main() {
  group('learning the nights', () {
    test('a night of the phone is written as a settings row', () async {
      final a = FakeActivity();
      useAround(a, sunday);
      final s = sleepStore(a);
      await s.updateSleepNights(force: true);

      final n = night(s, sunday)!;
      expect(n.asleep, const WallTime(day: sunday, minute: 23 * 60 + 30));
      expect(n.woke, const WallTime(day: monday, minute: 7 * 60));
      expect(n.sources, ['android']);
      expect(n.parts.keys, ['android']);
      expect(s.sleepNights().keys, [sunday]);
      expect(nightChanges(s), ['sleep.night.2026-10-04']);
    });

    test('a night that did not change is not written again', () async {
      final a = FakeActivity();
      useAround(a, sunday);
      final s = sleepStore(a);
      await s.updateSleepNights(force: true);
      s.repos.db.execute('DELETE FROM outbox');

      await s.updateSleepNights(force: true);
      expect(a.reads, 2);
      expect(nightChanges(s), isEmpty);
    });

    test(
      'only the night row syncs: no events, no alarm, no planner line',
      () async {
        final a = FakeActivity()..alarm = t(monday, 6, 45);
        useAround(a, sunday);
        final s = sleepStore(a);
        await s.updateSleepNights(force: true);

        expect(
          [for (final e in Outbox(s.repos.db).entries()) '${e.table}:${e.key}'],
          ['settings:sleep.night.2026-10-04'],
        );
        final keys = s.repos.db.query(
          'SELECT key FROM settings',
          const [],
          (r) => r.text(0),
        );
        expect(keys.where((k) => k.startsWith('planner.')), isEmpty);
        final value = s.repos.settings.get('sleep.night.2026-10-04')!;
        expect(value, isNot(contains('06:45')));
      },
    );

    test('with no Usage access nothing is read or written', () async {
      final a = FakeActivity(answer: ActivityAccess.needsGrant);
      useAround(a, sunday);
      final s = sleepStore(a);
      await s.updateSleepNights(force: true);
      expect(s.activityAccess, ActivityAccess.needsGrant);
      expect(a.reads, 0);
      expect(night(s, sunday), isNull);

      a.answer = ActivityAccess.granted;
      await s.refreshActivityAccess();
      expect(s.activityAccess, ActivityAccess.granted);
    });

    test('no source: nothing happens', () async {
      final s = sleepStore(null);
      await s.updateSleepNights(force: true);
      expect(s.activityAccess, ActivityAccess.unsupported);
      expect(s.sleepNights(), isEmpty);
    });

    test('the part of another device is kept', () async {
      final a = FakeActivity();
      useAround(a, sunday);
      final s = sleepStore(a);
      s.repos.settings.set(
        SleepNightRules.key(sunday),
        SleepNightRules.merge(
          null,
          sunday,
          'mac',
          const NightPart(
            asleep: WallTime(day: sunday, minute: 23 * 60 + 50),
            woke: WallTime(day: monday, minute: 6 * 60 + 40),
          ),
        )!,
      );
      await s.updateSleepNights(force: true);

      final n = night(s, sunday)!;
      expect(n.parts.keys.toList()..sort(), ['android', 'mac']);
      // Asleep only while no device was used.
      expect(n.asleep, const WallTime(day: sunday, minute: 23 * 60 + 50));
      expect(n.woke, const WallTime(day: monday, minute: 6 * 60 + 40));
      expect(n.sources, ['android', 'mac']);
    });

    test('a second look within ten minutes reads nothing', () async {
      final a = FakeActivity();
      final s = sleepStore(a);
      await s.updateSleepNights();
      await s.updateSleepNights();
      expect(a.reads, 1);
      await s.updateSleepNights(force: true);
      expect(a.reads, 2);
      s.clockOverride = const WallTime(day: monday, minute: 9 * 60 + 11);
      await s.updateSleepNights();
      expect(a.reads, 3);
    });

    test('a source that fails breaks nothing', () async {
      final s = sleepStore(_BrokenActivity());
      await s.updateSleepNights(force: true);
      expect(s.sleepNights(), isEmpty);
      expect(s.buildReminders(), isNotEmpty);
    });

    test('making the reminders learns the nights first', () async {
      final fake = FakeNotifier();
      final a = FakeActivity();
      useAround(a, sunday);
      final s = sleepStore(a, notifier: fake);
      await s.refreshReminders();
      expect(a.reads, 1);
      expect(night(s, sunday), isNotNull);
      expect(bedIds(fake.sent.single), isNotEmpty);
    });

    test('the Mac waking up learns the night at once', () async {
      final a = FakeActivity(name: 'mac')
        ..log.add(ActivityEvent(t(sunday, 12), ActivitySignal.recordStart));
      final s = sleepStore(a);
      await s.updateSleepNights();
      expect(a.reads, 1);
      expect(night(s, sunday), isNull);

      useAround(a, sunday);
      a.used();
      await Future<void>.delayed(Duration.zero);
      await s.sleepWork;
      expect(a.reads, 2);
      expect(night(s, sunday)!.sources, ['mac']);
    });
  });

  group('the settings', () {
    test('on by default, 90 minutes before', () {
      final s = sleepStore(null);
      expect(s.bedtimeEnabled, isTrue);
      expect(s.bedtimeLead, 90);
    });

    test('the switch and the lead are synced settings rows, no undo step', () {
      final s = sleepStore(null);
      s.setBedtimeEnabled(false);
      s.setBedtimeLead(120);
      expect(s.repos.settings.get('bedtime.enabled'), '0');
      expect(s.repos.settings.get('bedtime.lead'), '120');
      expect(s.bedtimeEnabled, isFalse);
      expect(s.bedtimeLead, 120);
      expect(s.undoStack, isEmpty);

      final keys = [for (final e in Outbox(s.repos.db).entries()) e.key];
      expect(keys, containsAll(['bedtime.enabled', 'bedtime.lead']));

      s.setBedtimeLead(45);
      expect(s.bedtimeLead, 120);
      s.repos.settings.set('bedtime.lead', 'soon');
      expect(s.bedtimeLead, 90);
    });

    test('tonight: the usual bedtime and the time of the reminder', () {
      final s = sleepStore(null);
      // 09:00: the night now is last night.
      expect(s.usualBedtimeTonight, (
        bedtime: const WallTime(day: sunday, minute: 23 * 60),
        reminder: const WallTime(day: sunday, minute: 21 * 60 + 30),
      ));
      s.clockOverride = const WallTime(day: monday, minute: 12 * 60);
      s.setBedtimeLead(60);
      s.addDayMarker(DayMarkerKind.sleep, monday, at: 22 * 60 + 30);
      expect(s.usualBedtimeTonight, (
        bedtime: const WallTime(day: monday, minute: 22 * 60 + 30),
        reminder: const WallTime(day: monday, minute: 21 * 60 + 30),
      ));
    });
  });

  group('the reminders', () {
    const evening = WallTime(day: sunday, minute: 20 * 60);

    test('one per night before the usual bedtime', () {
      final s = sleepStore(null, now: evening);
      final list = s.buildReminders();
      expect(bedIds(list), [
        for (var i = 0; i < 7; i++) 'bed-${sunday.adding(days: i).string}',
      ]);
      final first = list.firstWhere((r) => r.id == 'bed-2026-10-04');
      expect(first.fireAt, const WallTime(day: sunday, minute: 21 * 60 + 30));
      expect(first.day, monday);
      expect(first.ref, isNull);
    });

    test(
      'an early alarm makes the reminder earlier, also with no Usage access',
      () async {
        // No nights: bedtime 23:00, length 8 hours. The alarm at 06:30 means
        // asleep by 22:30, so the reminder is at 21:00, not 21:30.
        final a = FakeActivity(answer: ActivityAccess.needsGrant)
          ..alarm = t(monday, 6, 30);
        final s = sleepStore(a, now: evening);
        await s.updateSleepNights(force: true);
        expect(
          s.buildReminders().firstWhere((r) => r.id == 'bed-2026-10-04').fireAt,
          const WallTime(day: sunday, minute: 21 * 60),
        );
      },
    );

    test('the switch and the lead count', () {
      final s = sleepStore(null, now: evening)..setBedtimeLead(60);
      expect(
        s.buildReminders().firstWhere((r) => r.id == 'bed-2026-10-04').fireAt,
        const WallTime(day: sunday, minute: 22 * 60),
      );
      s.setBedtimeEnabled(false);
      expect(bedIds(s.buildReminders()), isEmpty);
    });

    test('the sleep line and the plan of tomorrow count', () {
      final s = sleepStore(null, now: evening);
      s.addDayMarker(DayMarkerKind.sleep, sunday, at: 22 * 60 + 30);
      s.repos.events.save(
        EventItem(
          id: 'E1',
          title: 'Standup',
          start: const WallTime(day: monday, minute: 9 * 60),
          end: const WallTime(day: monday, minute: 10 * 60),
        ),
      );
      s.repos.events.save(
        EventItem(
          id: 'E2',
          title: 'Holiday',
          start: const WallTime(day: monday, minute: 0),
          end: const WallTime(day: monday, minute: 0),
          allDay: true,
        ),
      );
      final r = s.buildReminders().firstWhere((r) => r.id == 'bed-2026-10-04');
      expect(r.fireAt, const WallTime(day: sunday, minute: 21 * 60));
      expect('${r.title} ${r.body}', contains('1 thing'));
    });

    test('notifications off: no bedtime reminder is sent', () async {
      final fake = FakeNotifier();
      final s = sleepStore(null, now: evening, notifier: fake)
        ..setNotifyEnabled(false);
      await s.refreshReminders();
      expect(fake.sent.last, isEmpty);
    });

    test('the bedtime reminders leave the others room under the limit', () {
      final s = sleepStore(null, now: evening);
      for (var i = 0; i < 70; i++) {
        final day = monday.adding(days: i % 13);
        s.repos.events.save(
          EventItem(
            id: 'E$i',
            title: 'e$i',
            start: WallTime(day: day, minute: 8 * 60 + i),
            end: WallTime(day: day, minute: 9 * 60 + i),
          ),
        );
      }
      final list = s.buildReminders();
      expect(list.length, ReminderPlanner.limit);
      expect(bedIds(list).length, 7);
    });
  });

  group('a click', () {
    test('on a bedtime reminder opens the planner on its day', () {
      final fake = FakeNotifier();
      final s = sleepStore(null, notifier: fake);
      var shown = 0;
      s.bringToFront = () => shown++;
      s.screen = Screen.today;
      fake.onOpenPlanner?.call(monday.adding(days: 1));
      expect(s.screen, Screen.planner);
      expect(s.selectedDay, monday.adding(days: 1));
      expect(shown, 1);
    });

    test('on another reminder also brings the window to the front', () {
      final fake = FakeNotifier();
      final s = sleepStore(null, notifier: fake);
      var shown = 0;
      s.bringToFront = () => shown++;
      fake.onOpen?.call(monday, const ItemRef(ItemType.event, 'gone'));
      expect(shown, 1);
    });
  });

  group('open at login (Mac)', () {
    test('the first start turns it on once', () async {
      final prefs = MemoryPrefs();
      final login = FakeLoginItem();
      final s = sleepStore(null, prefs: prefs, loginItem: login);
      await s.startSleep();
      expect(login.sets, [true]);
      expect(s.openAtLogin, LoginItemStatus.enabled);

      await s.setOpenAtLogin(false);
      final again = sleepStore(null, prefs: prefs, loginItem: login);
      await again.startSleep();
      expect(login.sets, [true, false]);
      expect(again.openAtLogin, LoginItemStatus.notRegistered);
    });

    test('a refusal of the Mac on the first start is ignored', () async {
      final prefs = MemoryPrefs();
      final login = FakeLoginItem()
        ..refusal = PlatformException(code: 'login', message: 'no');
      final s = sleepStore(null, prefs: prefs, loginItem: login);
      await s.startSleep();
      expect(login.sets, [true]);
      expect(s.openAtLoginProblem, isNull);
      expect(prefs.getBool('mac.openAtLogin.asked'), isTrue);
    });

    test('a refusal from the switch says why', () async {
      final login = FakeLoginItem();
      final s = sleepStore(
        null,
        prefs: MemoryPrefs()..set('mac.openAtLogin.asked', true),
        loginItem: login,
      );
      login.refusal = PlatformException(
        code: 'login',
        message: 'Operation not permitted',
        details: 'requiresApproval',
      );
      await s.setOpenAtLogin(true);
      expect(
        s.openAtLoginProblem,
        'Allow Grove in System Settings › General › Login Items.',
      );

      login
        ..refusal = PlatformException(code: 'login', message: 'Broken')
        ..now = LoginItemStatus.notFound;
      await s.setOpenAtLogin(true);
      expect(s.openAtLoginProblem, contains('Broken'));

      login.refusal = null;
      await s.setOpenAtLogin(true);
      expect(s.openAtLoginProblem, isNull);
      expect(s.openAtLogin, LoginItemStatus.enabled);
    });

    test('no login item (a phone, Windows): nothing happens', () async {
      final s = sleepStore(null);
      await s.startSleep();
      expect(s.openAtLogin, LoginItemStatus.unsupported);
    });
  });
}

class _BrokenActivity extends FakeActivity {
  @override
  Future<List<ActivityEvent>> events(DateTime from, DateTime to) async =>
      throw StateError('broken');
}
