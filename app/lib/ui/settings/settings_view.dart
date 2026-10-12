// Port of Sources/Grove/Settings/SettingsView.swift: the Settings window.
// A window of 600 by 540 points on a desktop, the whole screen on a phone.
// The Mac app has five tabs. This one has "Sync" too.
import 'package:flutter/material.dart';
import 'package:grove/state/state.dart' hide MotionRules;

import '../shell/shell_layout.dart';
import '../tasks/task_widgets.dart';
import '../theme/grove_theme.dart';
import '../theme/panel.dart';
import 'settings_tabs.dart';

enum SettingsTab {
  appearance('Appearance', Icons.palette_outlined),
  planner('Planner', Icons.view_timeline_outlined),
  notes('Notes', Icons.sticky_note_2_outlined),
  notifications('Notifications', Icons.notifications_none),
  sync('Sync', Icons.cloud_outlined),
  data('Data', Icons.storage_outlined);

  const SettingsTab(this.title, this.icon);

  final String title;
  final IconData icon;
}

/// The file windows of the system, for "Export" and "Import" of the Data
/// tab. `main.dart` gives the real ones (`SystemFiles`, Q-18 of
/// `docs/questions.md`); with none the two buttons are hidden.
abstract class SettingsFiles {
  /// False on a system with no save window (Android and iOS). "Export" is
  /// hidden there.
  bool get canSave => true;

  /// Asks where to save, and writes `text` there. Gives the name of the
  /// file, or null when the person closed the window.
  Future<String?> save({required String suggestedName, required String text});

  /// Asks for one file and reads it. null when the person closed the
  /// window.
  Future<({String name, String text})?> open();

  /// True on a system with a window of folders (Finder, Explorer). "Show
  /// data folder" is hidden on the others.
  bool get canShowFolder => false;

  /// Opens the folder `path` in the window of folders of the system. False
  /// when the system did not open it.
  Future<bool> showFolder(String path) async => false;
}

/// Opens the Settings window on `tab`.
Future<void> showSettings(
  BuildContext context,
  AppStore store, {
  SettingsTab tab = SettingsTab.appearance,
  SettingsFiles? files,
}) => showDialog<void>(
  context: context,
  // A phone gets the whole screen. The window keeps clear of the notch by
  // itself.
  useSafeArea: false,
  builder: (context) => SettingsView(store: store, tab: tab, files: files),
);

class SettingsView extends StatefulWidget {
  const SettingsView({
    super.key,
    required this.store,
    this.tab = SettingsTab.appearance,
    this.files,
  });

  final AppStore store;

  /// The tab that is open at first.
  final SettingsTab tab;
  final SettingsFiles? files;

  /// The size of the window on a desktop. Swift: `.frame(width: 600,
  /// height: 540)`.
  static const size = Size(600, 540);

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  late SettingsTab _tab = widget.tab;

  Widget _body(BuildContext context, {required bool phone}) {
    final theme = GroveTheme.of(context);
    final store = widget.store;
    final side = phone ? 16.0 : 20.0;
    return DefaultTextStyle(
      // The text style of the app, not the Material one of a dialog (that
      // one adds a gap between letters).
      style: theme.body(13).copyWith(color: theme.ink),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(side, 12, side - 6, 8),
            child: Row(
              children: [
                const Expanded(child: ThemedHeading('Settings', 18)),
                IconTap(
                  key: const ValueKey('settings-close'),
                  icon: Icons.close,
                  label: 'Close',
                  size: phone ? 20 : 16,
                  onTap: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          _TabStrip(
            tab: _tab,
            side: side - 4,
            onPick: (tab) => setState(() => _tab = tab),
          ),
          const SizedBox(height: 8),
          SizedBox(height: 1, child: ColoredBox(color: theme.line)),
          Expanded(
            child: StoreBuilder(
              store: store,
              builder: (context) => SingleChildScrollView(
                key: ValueKey('settings-page-${_tab.name}'),
                padding: EdgeInsets.all(side),
                child: switch (_tab) {
                  SettingsTab.appearance => AppearanceSettings(store: store),
                  SettingsTab.planner => PlannerSettings(store: store),
                  SettingsTab.notes => NotesSettings(store: store),
                  SettingsTab.notifications => NotificationSettings(
                    store: store,
                  ),
                  SettingsTab.sync => SyncSettings(store: store),
                  SettingsTab.data => DataSettings(
                    store: store,
                    files: widget.files,
                  ),
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    final phone =
        ShellRules.layoutFor(MediaQuery.sizeOf(context).width) ==
        ShellLayout.phone;
    if (phone) {
      return Material(
        key: const ValueKey('settings-window'),
        color: theme.solidSurface,
        child: SafeArea(child: _body(context, phone: true)),
      );
    }
    return Dialog(
      backgroundColor: theme.solidSurface,
      insetPadding: const EdgeInsets.all(20),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(theme.radius),
        side: BorderSide(color: theme.line),
      ),
      child: SizedBox(
        key: const ValueKey('settings-window'),
        width: SettingsView.size.width,
        height: SettingsView.size.height,
        child: _body(context, phone: false),
      ),
    );
  }
}

/// The row of tabs. It scrolls sideways when the window is narrow.
class _TabStrip extends StatelessWidget {
  const _TabStrip({
    required this.tab,
    required this.side,
    required this.onPick,
  });

  final SettingsTab tab;
  final double side;
  final ValueChanged<SettingsTab> onPick;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: EdgeInsets.symmetric(horizontal: side),
    child: Row(
      spacing: 4,
      children: [
        for (final t in SettingsTab.values)
          _TabButton(
            key: ValueKey('settings-tab-${t.name}'),
            tab: t,
            chosen: t == tab,
            onPick: () => onPick(t),
          ),
      ],
    ),
  );
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    super.key,
    required this.tab,
    required this.chosen,
    required this.onPick,
  });

  final SettingsTab tab;
  final bool chosen;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    final color = chosen ? theme.ink : theme.muted;
    void pick() {
      onPick();
      // A tab that is half out of the row comes in.
      for (final policy in const [
        ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        ScrollPositionAlignmentPolicy.keepVisibleAtStart,
      ]) {
        Scrollable.ensureVisible(context, alignmentPolicy: policy);
      }
    }

    return Semantics(
      container: true,
      button: true,
      selected: chosen,
      label: tab.title,
      onTap: pick,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: pick,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: chosen ? theme.surface2 : null,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: chosen ? theme.line : const Color(0x00000000),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 6,
                children: [
                  Icon(tab.icon, size: 14, color: color),
                  Text(
                    tab.title,
                    maxLines: 1,
                    style: theme
                        .body(12, weight: FontWeight.w600)
                        .copyWith(color: color),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
