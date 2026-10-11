import 'dart:async';

import '../state/state.dart';

/// Syncs from time to time while Grove stays open, so the changes of the
/// other devices come in when this device makes no change of its own.
///
/// A change on this device syncs some seconds later (the store does that).
/// The store does nothing when nobody is signed in, so a check then costs
/// nothing.
class SyncSchedule {
  SyncSchedule(this.store, {this.every = const Duration(minutes: 5)});

  final AppStore store;
  final Duration every;
  Timer? _timer;

  void start() => _timer ??= Timer.periodic(every, (_) => check());

  /// Starts a sync. The app calls it too when it comes back to the front.
  void check() {
    if (store.isDisposed) return;
    unawaited(store.syncNow());
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
