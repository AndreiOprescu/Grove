part of 'app_store.dart';

/// What the menu bar (tray) window needs from the store.
extension AppStoreMenuBar on AppStore {
  /// The "Now" and "Next" lines for today.
  NowNext menuBarLines({required int minute}) => NowNextRules.make(
    blocks: blocks(DayRange.single(DayKey.today())),
    minute: minute,
  );

  /// The quick-add box in the menu bar. A task with no day in its text goes to
  /// today.
  TaskItem? menuBarAdd(String text) =>
      quickAdd(text, placement: TaskPlacement.day(DayKey.today()));
}
