// "Now" for the planner. Tests fix it with `AppStore.clockOverride`, so the
// now line and the "today" column do not move between runs.
import 'package:grove/core/model/day_key.dart';
import 'package:grove/state/state.dart' show AppStore;

extension PlannerClock on AppStore {
  DayKey get plannerToday => clockOverride?.day ?? DayKey.today();

  /// Minutes since midnight.
  int get plannerNow => clockOverride?.minute ?? nowMinute();
}
