// The small sync mark in the top bar (asked by Track A with F11-login). A
// copy of Grove with no sync shows nothing.
import 'package:flutter/material.dart';
import 'package:grove/state/state.dart' hide MotionRules;

import '../auth/sync_card.dart';
import '../shell/shell_button.dart';
import '../shell/shell_layout.dart';
import '../tasks/task_widgets.dart';
import '../theme/grove_theme.dart';

class SyncMark extends StatelessWidget {
  const SyncMark({
    super.key,
    required this.store,
    required this.onTap,
    this.layout = ShellLayout.desktop,
    this.now,
  });

  final AppStore store;

  /// Opens the Sync tab of Settings.
  final VoidCallback onTap;
  final ShellLayout layout;

  /// The time of the device. Tests give a fixed one.
  final DateTime Function()? now;

  static IconData icon(SyncStatus status) => switch (status) {
    SyncStatus.off || SyncStatus.signedOut => Icons.cloud_off_outlined,
    SyncStatus.checking || SyncStatus.syncing => Icons.cloud_sync_outlined,
    SyncStatus.question => Icons.help_outline,
    SyncStatus.error => Icons.sync_problem,
    SyncStatus.upToDate => Icons.cloud_done_outlined,
  };

  /// One line for the tooltip and for a screen reader.
  static String words(AppStore store, {required DateTime now}) =>
      store.syncStatus == SyncStatus.error
      ? 'The last sync did not work. Open Settings to see why.'
      : SyncWords.status(store, now: now);

  @override
  Widget build(BuildContext context) => StoreBuilder(
    store: store,
    builder: (context) {
      final status = store.syncStatus;
      if (status == SyncStatus.off) return const SizedBox.shrink();
      final theme = GroveTheme.of(context);
      return ShellButton(
        label: 'Sync',
        selected: false,
        tooltip: words(store, now: (now ?? DateTime.now)()),
        onTap: onTap,
        child: PillGroup(
          children: [
            Pill(
              selected: false,
              child: (foreground) => SizedBox.fromSize(
                size: ShellRules.dockButton(layout),
                child: Icon(
                  icon(status),
                  size: layout == ShellLayout.phone ? 20 : 14,
                  color: status == SyncStatus.error
                      ? theme.accent2
                      : foreground,
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}
