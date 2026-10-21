// The six tabs of the Settings window. Port of the tabs of
// Sources/Grove/Settings/SettingsView.swift; the texts are the same.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:grove/core/model/note.dart';
import 'package:grove/core/planner/planner_math.dart';
import 'package:grove/core/services/reminder_planner.dart';
import 'package:grove/data/data.dart'
    show DataExport, ExportFailure, ExportSummary;
import 'package:grove/state/state.dart' hide MotionRules;

import '../auth/sync_card.dart';
import '../planner/planner_dialogs.dart';
import '../planner/planner_geometry.dart';
import '../planner/planner_view.dart';
import '../tasks/task_widgets.dart';
import '../theme/grove_theme.dart';
import '../theme/named_colors.dart';
import '../theme/panel.dart';
import '../theme/theme_spec.dart';
import 'settings_parts.dart';
import 'settings_view.dart';
import 'weather_settings.dart';

/// Saves a view setting of this device and tells the screens.
///
/// The store has no call for "a setting changed" yet (asked of Track A in
/// `docs/tracks.md`). `setIntensity` with the value it has writes nothing
/// new, and it is the one call that only tells the screens.
void saveSetting(AppStore store, String key, Object value) {
  store.prefs.set(key, value);
  store.setIntensity(store.intensity);
}

const _gap = SizedBox(height: 16);

// Appearance

class AppearanceSettings extends StatelessWidget {
  const AppearanceSettings({super.key, required this.store});

  final AppStore store;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SettingsSection(
        title: 'Theme',
        children: [
          LayoutBuilder(
            builder: (context, box) {
              const gap = 10.0;
              final perRow = box.maxWidth >= 400 ? 4 : 2;
              final widths = wholeShares(
                box.maxWidth - gap * (perRow - 1),
                perRow,
              );
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final (i, spec) in ThemeSpec.all.indexed)
                    SizedBox(
                      width: widths[i % perRow],
                      child: _ThemeCard(
                        key: ValueKey('settings-theme-${spec.id.name}'),
                        spec: spec,
                        chosen: store.themeId == spec.id,
                        onPick: () => store.setTheme(spec.id),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
      _gap,
      SettingsSection(
        title: 'Light or dark',
        children: [
          Segments<AppearanceMode>(
            value: store.appearance,
            values: AppearanceMode.values,
            name: (mode) => mode.label,
            onPick: store.setAppearance,
            label: 'Mode',
          ),
          const SettingsCaption(
            'System follows your device. Every theme has a light and a '
            'dark look.',
          ),
        ],
      ),
      _gap,
      SettingsSection(
        title: 'Motion',
        children: [
          SettingsSwitchRow(
            switchKey: const ValueKey('settings-motion'),
            label: 'Moving background and small animations',
            value: store.motionSetting,
            onChanged: store.setMotion,
          ),
          SettingsSlider(
            sliderKey: const ValueKey('settings-intensity'),
            label: 'Accent intensity',
            valueText: '${(store.intensity * 100).round()}%',
            value: store.intensity,
            min: SettingsRules.minIntensity,
            max: SettingsRules.maxIntensity,
            // Steps of 1 %.
            onChanged: (v) => store.setIntensity((v * 100).round() / 100),
          ),
          const SettingsCaption(
            'How strong the soft circles in the background look.',
          ),
        ],
      ),
    ],
  );
}

/// A small picture of a theme: its background, a card, and its three
/// accent colours.
class _ThemeCard extends StatelessWidget {
  const _ThemeCard({
    super.key,
    required this.spec,
    required this.chosen,
    required this.onPick,
  });

  final ThemeSpec spec;
  final bool chosen;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    final look = GroveTheme.make(spec.id, theme.brightness);
    Widget bar(double width, double height, Color color) => SizedBox(
      width: width,
      height: height,
      child: DecoratedBox(
        decoration: ShapeDecoration(color: color, shape: const StadiumBorder()),
      ),
    );
    Widget dot(Color color) => SizedBox.square(
      dimension: 10,
      child: DecoratedBox(
        decoration: ShapeDecoration(color: color, shape: const CircleBorder()),
      ),
    );
    return Semantics(
      container: true,
      button: true,
      selected: chosen,
      label: '${spec.name} theme',
      onTap: onPick,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onPick,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 6,
            children: [
              Container(
                height: 70,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: look.bg,
                  borderRadius: BorderRadius.circular(8),
                ),
                // The border is over the picture, so the picture does not
                // move when the card is chosen.
                foregroundDecoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: chosen ? theme.accent : theme.line,
                    width: chosen ? 2 : 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      height: 30,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(
                        color: look.solidSurface,
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: look.line),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: 4,
                        children: [
                          bar(40, 4, look.ink),
                          bar(28, 3, look.muted),
                        ],
                      ),
                    ),
                    const Spacer(),
                    Row(
                      spacing: 4,
                      children: [
                        dot(look.accent),
                        dot(look.accent2),
                        dot(look.accent3),
                      ],
                    ),
                  ],
                ),
              ),
              WholeCenter(
                child: Text(
                  spec.name,
                  maxLines: 1,
                  style: theme
                      .body(
                        12,
                        weight: chosen ? FontWeight.w700 : FontWeight.w400,
                      )
                      .copyWith(color: theme.ink),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Planner

class PlannerSettings extends StatelessWidget {
  const PlannerSettings({super.key, required this.store});

  final AppStore store;

  static const workStartKey = 'planner.workStart';
  static const workEndKey = 'planner.workEnd';
  static const eventLengthKey = 'planner.defaultLength';
  static const hourHeightKey = 'planner.hourHeight';
  static const dailyLimitKey = 'planner.dailyLimitMin';
  static const weekStartKey = 'calendar.weekStartsSunday';

  int get _workStart => store.prefs.getInt(workStartKey) ?? 9 * 60;
  int get _workEnd => store.prefs.getInt(workEndKey) ?? 18 * 60;

  void _setWorkHours({int? start, int? end}) {
    final fixed = SettingsRules.workHours(
      start: start ?? _workStart,
      end: end ?? _workEnd,
      startChanged: start != null,
    );
    store.prefs.set(workStartKey, fixed.start);
    saveSetting(store, workEndKey, fixed.end);
  }

  @override
  Widget build(BuildContext context) {
    final length =
        store.prefs.getInt(eventLengthKey) ?? SettingsRules.defaultEventLength;
    final hour = store.plannerHourHeight.clamp(
      PlannerGeometry.minHourHeight,
      PlannerGeometry.maxHourHeight,
    );
    final moodTint = store.prefs.getBool(PlannerView.moodTintKey) ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSection(
          title: 'Time grid',
          children: [
            SettingsRow(
              label: 'New event length',
              control: MenuPick<int>(
                key: const ValueKey('settings-event-length'),
                value: length,
                values: SettingsRules.eventLengths,
                name: PlannerMath.duration,
                onPick: (v) => saveSetting(store, eventLengthKey, v),
                label: 'New event length',
              ),
            ),
            SettingsSlider(
              sliderKey: const ValueKey('settings-hour-height'),
              label: 'Hour height',
              valueText: '${hour.round()} pt',
              value: hour,
              min: PlannerGeometry.minHourHeight,
              max: PlannerGeometry.maxHourHeight,
              onChanged: (v) =>
                  saveSetting(store, hourHeightKey, v.roundToDouble()),
            ),
          ],
        ),
        _gap,
        SettingsSection(
          title: 'Working hours',
          children: [
            SettingsRow(
              label: 'Start',
              control: MenuPick<int>(
                key: const ValueKey('settings-work-start'),
                value: _workStart,
                values: [for (var h = 0; h <= 23; h++) h * 60],
                name: SettingsRules.hourText,
                onPick: (v) => _setWorkHours(start: v),
                label: 'Start',
              ),
            ),
            SettingsRow(
              label: 'End',
              control: MenuPick<int>(
                key: const ValueKey('settings-work-end'),
                value: _workEnd,
                values: [for (var h = 1; h <= 24; h++) h * 60],
                name: SettingsRules.hourText,
                onPick: (v) => _setWorkHours(end: v),
                label: 'End',
              ),
            ),
            SettingsRow(
              label: 'Busy day limit',
              control: MenuPick<int>(
                key: const ValueKey('settings-daily-limit'),
                value: store.dailyLimitMinutes,
                values: SettingsRules.dailyLimits,
                name: PlannerMath.duration,
                onPick: (v) => saveSetting(store, dailyLimitKey, v),
                label: 'Busy day limit',
              ),
            ),
            const SettingsCaption(
              'Grove warns you when a day has more time planned than this.',
            ),
          ],
        ),
        _gap,
        SettingsSection(
          title: 'Calendar',
          children: [
            SettingsSwitchRow(
              switchKey: const ValueKey('settings-mood-tint'),
              label: 'Tint days by mood',
              value: moodTint,
              onChanged: (on) =>
                  saveSetting(store, PlannerView.moodTintKey, on),
            ),
          ],
        ),
        _gap,
        SettingsSection(
          title: 'Week',
          children: [
            SettingsRow(
              label: 'Week starts on',
              control: SizedBox(
                width: 180,
                child: Segments<bool>(
                  value: store.weekStartsSunday,
                  values: const [false, true],
                  name: (sunday) => sunday ? 'Sunday' : 'Monday',
                  onPick: (sunday) => saveSetting(store, weekStartKey, sunday),
                  label: 'Week starts on',
                ),
              ),
            ),
            const SettingsCaption(
              'This changes the month grid, the week strip and the week '
              'view. Plans for “this week” still run Monday to Sunday.',
            ),
          ],
        ),
        if (store.canShowWeather) ...[_gap, WeatherSettings(store: store)],
      ],
    );
  }
}

// Notes

class NotesSettings extends StatelessWidget {
  const NotesSettings({super.key, required this.store});

  final AppStore store;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SettingsSection(
        title: 'Text',
        children: [
          SettingsSwitchRow(
            switchKey: const ValueKey('settings-show-marks'),
            label: 'Show marks',
            value: store.prefs.getBool(EditorServices.showMarksKey) ?? false,
            onChanged: (on) =>
                saveSetting(store, EditorServices.showMarksKey, on),
          ),
        ],
      ),
      const SizedBox(height: 10),
      const SettingsCaption(
        'Show the marks of a format, like ** and ##, as you type them.',
      ),
      _gap,
      _TemplateEditor(store: store, kind: NoteKind.daily, title: 'Daily note'),
      _gap,
      _TemplateEditor(
        store: store,
        kind: NoteKind.weekly,
        title: 'Weekly note',
      ),
      const SizedBox(height: 10),
      const SettingsCaption(
        'A new note starts with this text. Notes you already have do not '
        'change.',
      ),
    ],
  );
}

class _TemplateEditor extends StatefulWidget {
  const _TemplateEditor({
    required this.store,
    required this.kind,
    required this.title,
  });

  final AppStore store;
  final NoteKind kind;
  final String title;

  @override
  State<_TemplateEditor> createState() => _TemplateEditorState();
}

class _TemplateEditorState extends State<_TemplateEditor> {
  late final _text = TextEditingController(
    text: widget.store.template(widget.kind),
  );

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    final name = widget.kind.name;
    return SettingsSection(
      title: widget.title,
      children: [
        GroveField(
          key: ValueKey('settings-template-$name'),
          controller: _text,
          placeholder: 'Template',
          boxed: true,
          fill: theme.surface,
          minLines: 5,
          maxLines: 5,
          newlines: true,
          style: theme.number(12).copyWith(color: theme.ink),
          label: '${widget.title} template',
          onChanged: (text) => widget.store.setTemplate(widget.kind, text),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: CardButton(
            key: ValueKey('settings-template-$name-reset'),
            label: 'Use the default',
            onTap: () {
              widget.store.resetTemplate(widget.kind);
              _text.text = widget.store.template(widget.kind);
            },
          ),
        ),
      ],
    );
  }
}

// Notifications

class NotificationSettings extends StatefulWidget {
  const NotificationSettings({super.key, required this.store});

  final AppStore store;

  @override
  State<NotificationSettings> createState() => _NotificationSettingsState();
}

class _NotificationSettingsState extends State<NotificationSettings> {
  AppStore get store => widget.store;

  @override
  void initState() {
    super.initState();
    // The person can change the permission in the settings of the system.
    unawaited(store.refreshNotifyStatus());
  }

  void _setEnabled(bool on) {
    store.setNotifyEnabled(on);
    if (on && store.notifyStatus == NotifyAuthorization.notAsked) {
      unawaited(store.askForNotifications());
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    final on = store.notifyEnabled;
    final status = store.notifyStatus;
    final denied = status == NotifyAuthorization.denied;
    final words = SettingsRules.notifyStatusText(status);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSection(
          title: 'Reminders',
          children: [
            SettingsSwitchRow(
              switchKey: const ValueKey('settings-notify'),
              label: 'Remind me about events, blocks and due times',
              value: on,
              onChanged: _setEnabled,
            ),
            SettingsRow(
              label: 'Remind me',
              control: IgnorePointer(
                ignoring: !on,
                child: ExcludeSemantics(
                  excluding: !on,
                  child: Opacity(
                    opacity: on ? 1 : 0.45,
                    child: MenuPick<int>(
                      key: const ValueKey('settings-notify-lead'),
                      value: store.notifyLead,
                      values: ReminderPlanner.leadChoices,
                      name: SettingsRules.leadText,
                      onPick: store.setNotifyLead,
                      label: 'Remind me',
                    ),
                  ),
                ),
              ),
            ),
            const SettingsCaption(
              'Grove reminds you about the next 14 days. A task with a due '
              'day but no time does not remind.',
            ),
          ],
        ),
        _gap,
        SettingsSection(
          title: 'Permission',
          children: [
            Semantics(
              key: const ValueKey('settings-notify-status'),
              container: true,
              label: denied ? 'Problem: $words' : words,
              excludeSemantics: true,
              child: Text(
                words,
                style: theme
                    .body(13)
                    .copyWith(
                      color: denied ? TaskPalette.color('orange') : theme.muted,
                    ),
              ),
            ),
            if (status == NotifyAuthorization.notAsked)
              Align(
                alignment: Alignment.centerLeft,
                child: CardButton(
                  key: const ValueKey('settings-notify-allow'),
                  label: 'Allow notifications',
                  onTap: () => unawaited(store.askForNotifications()),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

// Sync

class SyncSettings extends StatelessWidget {
  const SyncSettings({super.key, required this.store});

  final AppStore store;

  @override
  Widget build(BuildContext context) => SettingsSection(
    // The card of Track A has its own title, "Sync".
    children: [SyncCard(store: store)],
  );
}

// Data

class DataSettings extends StatefulWidget {
  const DataSettings({super.key, required this.store, this.files});

  final AppStore store;

  /// The file windows. "Export" and "Import" are hidden when null.
  final SettingsFiles? files;

  /// What Grove says while Import is blocked (Q-18 of
  /// `docs/questions.md`): Import replaces all data of this device, and
  /// with sync on that would go to the account too.
  static const importBlocked =
      'Import is off while you are signed in to sync. Sign out first '
      '(Settings, Sync), then import.';

  @override
  State<DataSettings> createState() => _DataSettingsState();
}

class _DataSettingsState extends State<DataSettings> {
  String? _message;
  bool _failed = false;
  String? _updateMessage;
  bool _checking = false;
  late List<BackupFile> _backups = widget.store.backupFiles();

  AppStore get store => widget.store;

  void _report(String text, {bool failed = false}) {
    if (!mounted) return;
    setState(() {
      _message = text;
      _failed = failed;
    });
  }

  /// The plain words of an error.
  static String _words(Object error) =>
      error is ExportFailure ? error.message : '$error';

  Future<void> _export(SettingsFiles files) async {
    try {
      final name = await files.save(
        suggestedName: DataExport.suggestedFileName(store.clockToday),
        text: store.exportData(),
      );
      if (name != null) _report('Saved $name.');
    } on Object catch (error) {
      _report('Grove could not save the file. ${_words(error)}', failed: true);
    }
  }

  /// True when Import must not run now. It says why.
  bool _blockedNow() {
    if (!store.isSignedIn) return false;
    _report(
      'You are signed in to sync. Sign out first, then import. Nothing '
      'was changed.',
      failed: true,
    );
    return true;
  }

  Future<void> _import(SettingsFiles files) async {
    // The button is off while signed in. A login can also come while a
    // window of this import is open, so each step looks again.
    if (_blockedNow()) return;
    try {
      final file = await files.open();
      if (file == null || !mounted || _blockedNow()) return;
      final summary = DataExport.summary(file.text);
      if (!await _confirmReplace(summary) || !mounted) return;
      if (_blockedNow()) return;
      store
        ..saveSafetyCopy()
        ..importData(file.text);
      setState(() => _backups = store.backupFiles());
      _report(
        'Imported ${file.name}. Your old data is in before-import.sqlite '
        'in the data folder.',
      );
    } on Object catch (error) {
      _report('${_words(error)} Nothing was changed.', failed: true);
    }
  }

  /// The window says that import replaces everything (PLAN §4.4).
  Future<bool> _confirmReplace(ExportSummary s) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) {
        final theme = GroveTheme.of(context);
        return Dialog(
          key: const ValueKey('settings-import-question'),
          backgroundColor: theme.solidSurface,
          insetPadding: const EdgeInsets.all(20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(theme.radius),
            side: BorderSide(color: theme.line),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: DefaultTextStyle(
              style: theme.body(13).copyWith(color: theme.ink),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 12,
                  children: [
                    const ThemedHeading('Replace everything in Grove?', 18),
                    Text(
                      'This file has ${s.tasks} tasks, ${s.events} events, '
                      '${s.notes} notes and ${s.lists} lists.\n'
                      'Import replaces ALL your data with the data in this '
                      'file.\n'
                      'Grove saves a copy of your data first, in the data '
                      'folder.',
                      style: theme.body(13).copyWith(color: theme.muted),
                    ),
                    Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        DialogButton(
                          label: 'Cancel',
                          onTap: () => Navigator.of(context).pop(false),
                        ),
                        DialogButton(
                          label: 'Replace Everything',
                          primary: true,
                          onTap: () => Navigator.of(context).pop(true),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
    return yes ?? false;
  }

  Future<void> _copyPath(String path) async {
    await Clipboard.setData(ClipboardData(text: path));
    _report('The path is copied.');
  }

  /// Swift: "Show data folder" opens the folder in Finder.
  Future<void> _showFolder(SettingsFiles files, String path) async {
    var shown = false;
    try {
      shown = await files.showFolder(path);
    } on Object {
      shown = false;
    }
    if (!shown) {
      _report(
        'Grove could not open the folder. You can copy its path.',
        failed: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    final files = widget.files;
    final dir = store.dataDir;
    final message = _message;
    final signedIn = store.isSignedIn;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSection(
          title: 'Your data',
          children: [
            Text(
              dir ?? const DataFolderError().toString(),
              key: const ValueKey('settings-data-path'),
              style: dir == null
                  ? theme.body(13).copyWith(color: theme.muted)
                  : theme.number(11).copyWith(color: theme.ink),
            ),
            if (files != null || dir != null)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (files != null) ...[
                    if (files.canSave)
                      CardButton(
                        key: const ValueKey('settings-export'),
                        label: 'Export JSON…',
                        onTap: () => unawaited(_export(files)),
                      ),
                    _OffWhen(
                      key: const ValueKey('settings-import-off'),
                      off: signedIn,
                      label: 'Import JSON…',
                      child: CardButton(
                        key: const ValueKey('settings-import'),
                        label: 'Import JSON…',
                        onTap: () => unawaited(_import(files)),
                      ),
                    ),
                  ],
                  if (dir != null && files != null && files.canShowFolder)
                    CardButton(
                      key: const ValueKey('settings-show-folder'),
                      label: 'Show data folder',
                      onTap: () => unawaited(_showFolder(files, dir)),
                    ),
                  if (dir != null)
                    CardButton(
                      key: const ValueKey('settings-copy-path'),
                      label: 'Copy the path',
                      onTap: () => unawaited(_copyPath(dir)),
                    ),
                ],
              ),
            SettingsCaption(
              files == null
                  ? 'Export and Import are not in this copy of Grove yet. '
                        'The daily backups are.'
                  : files.canSave
                  ? 'Export saves everything in one file. Import replaces '
                        'everything with the file you pick.'
                  : 'Import replaces everything with the file you pick. '
                        'Export is not on this device yet.',
            ),
            if (files != null && signedIn)
              Text(
                DataSettings.importBlocked,
                key: const ValueKey('settings-import-blocked'),
                style: theme.body(13).copyWith(color: theme.ink),
              ),
            if (message != null)
              Semantics(
                container: true,
                liveRegion: true,
                label: _failed ? 'Problem: $message' : message,
                excludeSemantics: true,
                child: Text(
                  message,
                  key: const ValueKey('settings-data-message'),
                  style: theme
                      .body(13)
                      .copyWith(
                        color: _failed ? PriorityColors.high : theme.muted,
                      ),
                ),
              ),
          ],
        ),
        _gap,
        SettingsSection(
          title: 'Daily backups',
          children: [
            if (_backups.isEmpty)
              Text(
                'No backups yet. Grove makes one each day when it starts '
                'and keeps the newest 14.',
                style: theme.body(13).copyWith(color: theme.muted),
              )
            else
              for (final file in _backups)
                Row(
                  key: ValueKey('settings-backup-${file.id}'),
                  spacing: 12,
                  children: [
                    Expanded(
                      child: Text(
                        file.title,
                        style: theme.body(13).copyWith(color: theme.ink),
                      ),
                    ),
                    Text(
                      file.sizeText,
                      style: theme.number(12).copyWith(color: theme.muted),
                    ),
                  ],
                ),
          ],
        ),
        if (store.canCheckForUpdates) ...[_gap, _updates(theme)],
      ],
    );
  }

  /// The version of this copy and the check for a newer one on GitHub.
  Widget _updates(GroveTheme theme) {
    final message = _updateMessage;
    return SettingsSection(
      title: 'Updates',
      children: [
        Text(
          'Grove ${store.currentVersion}',
          key: const ValueKey('settings-updates-version'),
          style: theme.body(13).copyWith(color: theme.ink),
        ),
        SettingsSwitchRow(
          label: 'Check for updates',
          value: store.checksForUpdates,
          onChanged: (on) => store.checksForUpdates = on,
          switchKey: const ValueKey('settings-updates-switch'),
        ),
        Wrap(
          children: [
            CardButton(
              key: const ValueKey('settings-updates-check'),
              label: _checking ? 'Checking…' : 'Check now',
              onTap: () => unawaited(_checkNow()),
            ),
          ],
        ),
        const SettingsCaption(
          'Grove asks GitHub for a new version when it starts and every '
          'few hours. A card shows when one is out.',
        ),
        if (message != null)
          Semantics(
            container: true,
            liveRegion: true,
            label: message,
            excludeSemantics: true,
            child: Text(
              message,
              key: const ValueKey('settings-updates-message'),
              style: theme.body(13).copyWith(color: theme.muted),
            ),
          ),
      ],
    );
  }

  Future<void> _checkNow() async {
    if (_checking) return;
    setState(() => _checking = true);
    final words = await store.checkForUpdates(manual: true);
    if (!mounted) return;
    setState(() {
      _checking = false;
      _updateMessage = words ?? _updateMessage;
    });
  }
}

/// A button that is grey and takes no tap while `off`.
class _OffWhen extends StatelessWidget {
  const _OffWhen({
    super.key,
    required this.off,
    required this.label,
    required this.child,
  });

  final bool off;
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => off
      ? Semantics(
          container: true,
          button: true,
          enabled: false,
          label: label,
          excludeSemantics: true,
          child: IgnorePointer(child: Opacity(opacity: 0.45, child: child)),
        )
      : child;
}
