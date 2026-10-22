import 'dart:math';

import '../../core/model/day_key.dart';
import '../notifier.dart';
import 'notes_rules.dart';

/// The small rules behind the Settings window (PLAN §5.8). Plain functions, so
/// tests can check them.
abstract final class SettingsRules {
  static const eventLengths = [15, 30, 45, 60, 90, 120];
  static const defaultEventLength = 60;

  /// The busy-day limit, whole hours from 6 to 12, in minutes. Planned time
  /// above it shows a warning.
  static const dailyLimits = [360, 420, 480, 540, 600, 660, 720];
  static const defaultDailyLimit = 540;

  /// How strong the moving circles look, 0% to 150%. 100% is the theme as designed.
  static const minIntensity = 0.0;
  static const maxIntensity = 1.5;

  /// Keeps the working day at least one hour long and inside 00:00 to 24:00.
  /// The value that did not just change gives way: that is the one the person
  /// did not touch.
  static ({int start, int end}) workHours({
    required int start,
    required int end,
    required bool startChanged,
  }) {
    var s = min(max(start, 0), 23 * 60), e = min(max(end, 60), 24 * 60);
    if (e - s < 60) {
      if (startChanged) {
        e = min(24 * 60, s + 60);
        s = e - 60;
      } else {
        s = max(0, e - 60);
        e = s + 60;
      }
    }
    return (start: s, end: e);
  }

  /// 540 → "09:00"
  static String hourText(int minutes) =>
      '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
      '${(minutes % 60).toString().padLeft(2, '0')}';

  /// 0 → "When it starts", 5 → "5 minutes before"
  static String leadText(int minutes) => switch (minutes) {
    0 => 'When it starts',
    1 => '1 minute before',
    _ => '$minutes minutes before',
  };

  /// The quiet note under the switch in the Notifications tab.
  static String notifyStatusText(NotifyAuthorization status) =>
      switch (status) {
        NotifyAuthorization.allowed => 'Notifications are allowed for Grove.',
        NotifyAuthorization.notAsked =>
          'Grove has not asked for permission yet.',
        NotifyAuthorization.denied => 'Notifications are off for Grove. Turn them on in System Settings to get reminders.',
      };

  // The bedtime reminder (ADR 0005)

  /// 60 → "1 hour before", 90 → "1½ hours before"
  static String bedtimeLeadText(int minutes) => switch (minutes) {
    60 => '1 hour before',
    90 => '1½ hours before',
    120 => '2 hours before',
    _ => '$minutes minutes before',
  };

  /// Under the bedtime switch: tonight's usual bedtime and, when the
  /// reminder is on, when it comes.
  static String bedtimeText({
    required WallTime bedtime,
    required WallTime? reminder,
  }) {
    final asleep = 'Tonight: usually asleep around ${hourText(bedtime.minute)}';
    final at = reminder == null
        ? ''
        : ', reminder at ${hourText(reminder.minute)}';
    return '$asleep$at. Only these times sync, never what you used.';
  }

  static const usageAccessOnText = 'Usage access is on';
  static const usageAccessOffText =
      'Turn on Usage access so Grove can learn when you sleep';
  static const openAtLoginText =
      'Closing the window keeps Grove in the menu bar, so it can learn when '
      'you sleep. Quit it from the menu bar.';

  // The agent (ADR 0004)

  /// Under "This device runs agent tasks" on a phone.
  static const agentNoRunner =
      'Only a computer with Claude Code can run agent tasks. Turn this on in '
      'Grove on your Mac.';

  /// While Grove looks for the `claude` command.
  static const agentLooking =
      'Grove is looking for Claude Code on this computer.';

  /// When the `claude` command is not in a known place.
  static const agentNotFound =
      'Grove could not find Claude Code on this computer. Install it, log in '
      'with your own Claude plan, then turn this on again.';

  /// The help text under the runner switch, or null when this device can run
  /// agent tasks.
  static String? agentHelp({
    required bool computer,
    required bool looked,
    required bool found,
  }) {
    if (!computer) return agentNoRunner;
    if (found) return null;
    return looked ? agentNotFound : agentLooking;
  }

  /// The day in a backup file name: "grove-2026-10-04.sqlite" → 2026-10-04.
  static DayKey? backupDay({required String fileName}) {
    const head = 'grove-', tail = '.sqlite';
    if (!fileName.startsWith(head) || !fileName.endsWith(tail)) return null;
    if (fileName.length < head.length + tail.length) return null;
    return DayKey.parse(
      fileName.substring(head.length, fileName.length - tail.length),
    );
  }
}

/// One copy of the database in the Backups folder.
class BackupFile {
  const BackupFile({required this.path, this.day, required this.bytes});

  final String path;
  final DayKey? day;
  final int bytes;

  /// The file name.
  String get id => path.split(RegExp(r'[/\\]')).last;

  String get title {
    final d = day;
    return d == null ? id : NotesRules.dailyTitle(d);
  }

  /// "512 bytes", "12 KB", "1.2 MB". Units of 1000, as the Mac shows file sizes.
  String get sizeText {
    if (bytes < 1000) return bytes == 1 ? '1 byte' : '$bytes bytes';
    if (bytes < 1000 * 1000) return '${(bytes / 1000).round()} KB';
    if (bytes < 1000 * 1000 * 1000) {
      return '${(bytes / 1e6).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1e9).toStringAsFixed(2)} GB';
  }

  @override
  bool operator ==(Object other) =>
      other is BackupFile &&
      other.path == path &&
      other.day == day &&
      other.bytes == bytes;

  @override
  int get hashCode => Object.hash(path, day, bytes);
}
