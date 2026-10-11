import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/model/day_key.dart';
import '../core/model/link.dart';
import '../core/services/reminder_planner.dart';
import '../state/notifier.dart';
import '../state/prefs.dart';
import 'notification_gateway.dart';

/// The real notifier, on the system notification centre of each OS (port of
/// `SystemNotifier` in Sources/Grove/Reminders/Notifier.swift).
///
/// A call to the system that fails is dropped: a lost reminder is better than
/// a crash, and the next refresh asks again.
class SystemNotifier extends Notifier {
  SystemNotifier({
    required this.gateway,
    required this.prefs,
    DateTime Function()? now,
    int Function(String reminderId)? idOf,
  }) : _now = now ?? DateTime.now,
       _idOf = idOf ?? idFor;

  final NotificationGateway gateway;
  final Prefs prefs;
  final DateTime Function() _now;
  final int Function(String reminderId) _idOf;

  /// The one "time is up" notification of a focus session.
  static const focusId = 1;

  /// Reminders have this number or a higher one. Lower numbers are not theirs.
  static const firstReminderId = 1000;
  static const _lastId = 0x7fffffff;

  /// The id of the "Mark done" button.
  static const doneAction = 'focus-done';

  /// True in the settings of this device after Grove showed the system
  /// question. Not every system can tell "not asked" from "denied".
  static const askedKey = 'notifications.asked';

  Future<void>? _started;
  String? _lastClick;
  bool _launchDone = false;

  /// The number the system knows a reminder by. The same text gives the same
  /// number on each device and in each run (FNV-1a; `String.hashCode` can
  /// change between runs).
  static int idFor(String reminderId) {
    var hash = 0x811c9dc5;
    for (final byte in utf8.encode(reminderId)) {
      hash = ((hash ^ byte) * 0x01000193) & 0xffffffff;
    }
    return firstReminderId + hash % (_lastId - firstReminderId + 1);
  }

  /// The local date and time of [time].
  static DateTime fireTime(WallTime time) =>
      DateTime(time.day.year, time.day.month, time.day.day, 0, time.minute);

  Future<T?> _safe<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on Object catch (error) {
      // Also an Error: the plugin throws ArgumentError for a time in the past.
      assert(() {
        debugPrint('Grove notifications: $error');
        return true;
      }());
      return null;
    }
  }

  Future<void> _ready() => _started ??= _safe(() => gateway.start(_clicked));

  @override
  Future<NotifyAuthorization> authorization() async {
    await _ready();
    if (await _safe(gateway.permitted) ?? false) {
      return NotifyAuthorization.allowed;
    }
    return prefs.getBool(askedKey) ?? false
        ? NotifyAuthorization.denied
        : NotifyAuthorization.notAsked;
  }

  @override
  Future<NotifyAuthorization> requestAuthorization() async {
    await _ready();
    final allowed = await _safe(gateway.requestPermission);
    // The question did not show. Grove can ask again.
    if (allowed == null) return authorization();
    prefs.set(askedKey, true);
    return allowed ? NotifyAuthorization.allowed : NotifyAuthorization.denied;
  }

  @override
  Future<void> replaceAll(List<Reminder> reminders) async {
    await _ready();
    final now = _now();
    final wanted = <int, NoteRequest>{};
    for (final r in reminders) {
      final at = fireTime(r.fireAt);
      if (!at.isAfter(now)) continue;
      var id = _idOf(r.id);
      // Two texts with the same number: the second takes the next free one.
      while (wanted.containsKey(id)) {
        id = id >= _lastId ? firstReminderId : id + 1;
      }
      wanted[id] = NoteRequest(
        id: id,
        title: r.title,
        body: r.body,
        // The time is in the payload, so a moved reminder is a changed one.
        payload: jsonEncode({..._target(r.day, r.ref), 'at': r.fireAt.string}),
        at: at,
      );
    }

    final held = {
      for (final p in await _safe(gateway.pending) ?? const <PendingNote>[])
        if (p.id >= firstReminderId) p.id: p,
    };
    for (final id in held.keys) {
      if (!wanted.containsKey(id)) await _safe(() => gateway.cancel(id));
    }
    for (final want in wanted.values) {
      final old = held[want.id];
      if (old != null) {
        final same =
            old.title == want.title &&
            old.body == want.body &&
            old.payload == want.payload;
        if (same) continue;
        await _safe(() => gateway.cancel(want.id));
      }
      await _safe(() => gateway.schedule(want));
    }
  }

  @override
  Future<void> scheduleFocusEnd(FocusEnd end) async {
    await _ready();
    await _safe(() => gateway.cancel(focusId));
    final soonest = _now().add(const Duration(seconds: 1));
    final taskId = end.taskId;
    final target = {..._target(end.day, end.ref), 'taskId': ?taskId};
    await _safe(
      () => gateway.schedule(
        NoteRequest(
          id: focusId,
          title: 'Focus time is up',
          body: taskId == null
              ? '${end.title} is over.'
              : '${end.title}. Mark it done?',
          payload: jsonEncode(target),
          donePayload: taskId == null
              ? null
              : jsonEncode({...target, 'action': doneAction}),
          at: end.at.isAfter(soonest) ? end.at : soonest,
        ),
      ),
    );
  }

  @override
  Future<void> cancelFocusEnd() async {
    await _ready();
    await _safe(() => gateway.cancel(focusId));
  }

  /// Gives the click that started the app to the store. Call it one time,
  /// after the store set [onOpen] and [onFocusDone].
  Future<void> deliverLaunch() async {
    if (_launchDone) return;
    _launchDone = true;
    await _ready();
    final response = await _safe(gateway.launchResponse);
    // Some systems also send the launch click as a normal click.
    if (response == null || _key(response) == _lastClick) return;
    _clicked(response);
  }

  static Map<String, String> _target(DayKey day, ItemRef ref) => {
    'day': day.string,
    'kind': ref.type.name,
    'id': ref.id,
  };

  static String _key(NoteResponse r) => '${r.actionId}\n${r.payload}';

  void _clicked(NoteResponse response) {
    _lastClick = _key(response);
    final Object? info;
    try {
      info = jsonDecode(response.payload ?? '');
    } on FormatException {
      return;
    }
    if (info is! Map<String, dynamic>) return;

    final done =
        response.actionId == doneAction || info['action'] == doneAction;
    final taskId = info['taskId'];
    if (done) {
      if (taskId is String) onFocusDone?.call(taskId);
      return;
    }

    final day = info['day'], kind = info['kind'], id = info['id'];
    if (day is! String || kind is! String || id is! String) return;
    final key = DayKey.parse(day);
    final type = ItemType.values.asNameMap()[kind];
    if (key == null || type == null) return;
    onOpen?.call(key, ItemRef(type, id));
  }
}
