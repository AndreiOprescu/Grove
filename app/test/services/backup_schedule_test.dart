import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../data/helpers.dart' show tempDir;
import 'support.dart';

void main() {
  late AppStore store;
  late DayKey day;

  int copies() => store.backupFiles().length;

  setUp(() {
    day = DayKey.today();
    store = AppStore.open(
      dataDir: tempDir('grove-schedule').path,
      prefs: MemoryPrefs(),
    );
    addTearDown(() {
      store.dispose();
      store.repos.db.close();
    });
  });

  test('a check on the same day makes no copy', () {
    final schedule = BackupSchedule(store, today: () => day);
    expect(schedule.check(), isNull);
    expect(copies(), 1);
  });

  test('a check on a new day makes the copy of that day', () {
    final schedule = BackupSchedule(store, today: () => day);
    day = day.adding(days: 1);
    expect(schedule.check(), endsWith('grove-${day.string}.sqlite'));
    expect(schedule.check(), isNull);
    expect(copies(), 2);
  });

  test('a copy that is gone is made again', () {
    File(store.backupFiles().single.path).deleteSync();
    expect(BackupSchedule(store).check(), isNotNull);
    expect(copies(), 1);
  });

  testWidgets('the timer checks while Grove stays open over midnight', (
    tester,
  ) async {
    final schedule = BackupSchedule(
      store,
      every: const Duration(minutes: 30),
      today: () => day,
    )..start();
    addTearDown(schedule.dispose);

    await tester.pump(const Duration(minutes: 31));
    expect(copies(), 1);

    day = day.adding(days: 1);
    await tester.pump(const Duration(minutes: 30));
    expect(copies(), 2);

    // A second start does not make a second timer.
    schedule.start();
    schedule.dispose();
    day = day.adding(days: 1);
    await tester.pump(const Duration(hours: 2));
    expect(copies(), 2);
  });
}
