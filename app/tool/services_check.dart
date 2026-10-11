// A small app to check the background services on a real device: a real
// notification, the "Mark done" button, the tray icon and the daily backup.
//
//   cd app && flutter run -d macos -t tool/services_check.dart
//
// It uses its own data folder in the temporary folder of the system. It never
// touches the data of Grove. Add `--dart-define=AUTO=true` to ask for the
// permission and to send the focus notification with no click.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:grove/core/model/day_key.dart';
import 'package:grove/core/model/event.dart';
import 'package:grove/core/model/link.dart';
import 'package:grove/core/model/task.dart';
import 'package:grove/services/services.dart';
import 'package:grove/state/state.dart';

const _auto = bool.fromEnvironment('AUTO');

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final dir =
      '${Directory.systemTemp.path}${Platform.pathSeparator}grove-services-check';
  final prefs = MemoryPrefs();
  final store = AppStore.open(
    dataDir: dir,
    notifier: AppServices.notifier(prefs),
    prefs: prefs,
  );
  final services = AppServices.forThisDevice(store)..start();
  runApp(
    MaterialApp(
      home: _Check(store: store, services: services, dir: dir),
    ),
  );
}

class _Check extends StatefulWidget {
  const _Check({
    required this.store,
    required this.services,
    required this.dir,
  });

  final AppStore store;
  final AppServices services;
  final String dir;

  @override
  State<_Check> createState() => _CheckState();
}

class _CheckState extends State<_Check> {
  final _log = <String>[];
  TaskItem? _task;
  TaskStatus? _status;
  late DayKey _day = widget.store.selectedDay;

  AppStore get store => widget.store;

  @override
  void initState() {
    super.initState();
    store.addListener(_changed);
    _say('data folder: ${widget.dir}');
    _say('backups: ${store.backupFiles().length}');
    _say('tray icon: ${widget.services.trayShown ? 'shown' : 'none'}');
    if (_auto) _runAuto();
  }

  @override
  void dispose() {
    store.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    final status = _task == null ? null : store.task(_task!.id)?.status;
    if (status != _status) {
      _status = status;
      _say('focus task: ${status?.name}');
    }
    if (store.selectedDay != _day) {
      _day = store.selectedDay;
      _say('selected day: ${_day.string}');
    }
    setState(() {});
  }

  void _say(String line) {
    debugPrint('CHECK $line');
    if (mounted) setState(() => _log.insert(0, line));
  }

  Future<void> _runAuto() async {
    await _allow();
    await _focusEnd();
  }

  Future<void> _allow() async {
    await store.askForNotifications();
    _say('permission: ${store.notifyStatus.name}');
  }

  /// The "time is up" notification, 10 seconds from now, with "Mark done".
  Future<void> _focusEnd() async {
    final task = _task = store.quickAdd('Check the focus notification today');
    if (task == null) return _say('no task was made');
    await store.notifier.scheduleFocusEnd(
      FocusEnd(
        title: task.title,
        at: DateTime.now().add(const Duration(seconds: 10)),
        day: DayKey.today(),
        ref: ItemRef(ItemType.task, task.id),
        taskId: task.id,
      ),
    );
    _say('focus notification asked for, 10 seconds from now');
  }

  /// A reminder for an event that starts 2 minutes from now, with no lead time.
  Future<void> _reminder() async {
    WallTime wall(DateTime d) =>
        WallTime(day: DayKey.fromDate(d), minute: d.hour * 60 + d.minute);
    final at = DateTime.now().add(const Duration(minutes: 2));
    final start = wall(at);
    store.setNotifyLead(0);
    store.repos.events.save(
      EventItem(
        title: 'Check the reminder',
        start: start,
        end: wall(at.add(const Duration(minutes: 30))),
      ),
    );
    await store.refreshReminders();
    _say('reminder asked for at ${start.string}');
  }

  @override
  Widget build(BuildContext context) {
    final task = _task == null ? null : store.task(_task!.id);
    return Scaffold(
      appBar: AppBar(title: const Text('Grove services check')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Permission: ${store.notifyStatus.name}'),
          Text('Tray icon: ${widget.services.trayShown ? 'shown' : 'none'}'),
          Text('Selected day: ${store.selectedDay.string}'),
          Text('Focus task: ${task == null ? '-' : task.status.name}'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: _allow,
                child: const Text('1. Allow notifications'),
              ),
              FilledButton(
                onPressed: _focusEnd,
                child: const Text('2. Focus end in 10 seconds'),
              ),
              FilledButton(
                onPressed: _reminder,
                child: const Text('3. Reminder in 2 minutes'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final line in _log) Text(line),
        ],
      ),
    );
  }
}
