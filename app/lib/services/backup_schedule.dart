import 'dart:async';

import '../core/model/day_key.dart';
import '../state/state.dart';

/// Makes the daily copy of the database while Grove stays open (PLAN §9).
///
/// The launch makes the copy of the day. A phone or a computer can keep Grove
/// open for many days, so this asks again from time to time. A check on a day
/// that has its copy only looks for the file.
class BackupSchedule {
  BackupSchedule(
    this.store, {
    this.every = const Duration(minutes: 30),
    DayKey Function()? today,
  }) : _today = today ?? DayKey.today;

  final AppStore store;
  final Duration every;
  final DayKey Function() _today;
  Timer? _timer;

  void start() => _timer ??= Timer.periodic(every, (_) => check());

  /// Makes the copy of today when it is missing. Returns the path of a new copy.
  String? check() => store.runDailyBackup(today: _today());

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
