import 'dart:async';

import 'package:flutter/services.dart';

import '../core/sleep/activity.dart';

/// The use history of this device, read from the native side over the
/// channel `grove/activity`: `MainActivity.kt` on Android (Usage access) and
/// `ActivityRecorder.swift` on the Mac (its own log, kept while Grove runs).
///
/// The native side sends times and codes only, never app names. A device
/// with no native side is `unsupported`; nothing here throws.
class MethodChannelActivitySource implements ActivitySource {
  MethodChannelActivitySource({
    required this.name,
    this.channel = const MethodChannel('grove/activity'),
  });

  /// The codes of the flat event list, in the order of the native side.
  static const _signals = ActivitySignal.values;

  @override
  final String name;

  /// The native side. A test gives its own.
  final MethodChannel channel;

  late final StreamController<void> _changes = StreamController<void>.broadcast(
    onListen: () => channel.setMethodCallHandler(_handle),
    onCancel: () => channel.setMethodCallHandler(null),
  );

  Future<Object?> _handle(MethodCall call) async {
    if (call.method == 'changed') _changes.add(null);
    return null;
  }

  @override
  Future<ActivityAccess> access() async {
    final answer = await _call<String>('access');
    return switch (answer) {
      'granted' => ActivityAccess.granted,
      'needsGrant' => ActivityAccess.needsGrant,
      _ => ActivityAccess.unsupported,
    };
  }

  @override
  Future<void> openAccessSettings() => _call<void>('openAccessSettings');

  @override
  Future<List<ActivityEvent>> events(DateTime from, DateTime to) async {
    final flat = await _call<List<Object?>>('events', {
      'from': from.millisecondsSinceEpoch,
      'to': to.millisecondsSinceEpoch,
    });
    if (flat == null) return const [];
    return decode(flat);
  }

  /// Reads [ms, code, ms, code, …]. A pair with an unknown code or a broken
  /// number is left out. The result is oldest first.
  static List<ActivityEvent> decode(List<Object?> flat) {
    final events = <ActivityEvent>[];
    for (var i = 0; i + 1 < flat.length; i += 2) {
      final ms = flat[i];
      final code = flat[i + 1];
      if (ms is! num || code is! num) continue;
      final c = code.toInt();
      if (c < 0 || c >= _signals.length) continue;
      events.add(
        ActivityEvent(
          DateTime.fromMillisecondsSinceEpoch(ms.toInt()),
          _signals[c],
        ),
      );
    }
    // The native side sends them in order. Two events at the same time keep
    // the order they came in, so the sort runs only when one is out of place.
    for (var i = 1; i < events.length; i++) {
      if (events[i].at.isBefore(events[i - 1].at)) {
        final order = {for (var j = 0; j < events.length; j++) events[j]: j};
        events.sort((a, b) {
          final byTime = a.at.compareTo(b.at);
          return byTime != 0 ? byTime : order[a]!.compareTo(order[b]!);
        });
        break;
      }
    }
    return events;
  }

  @override
  Future<DateTime?> nextAlarm() async {
    final ms = await _call<num>('nextAlarm');
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms.toInt());
  }

  /// Fires when the Mac is used again. Android sends nothing: Grove reads the
  /// phone when it opens.
  @override
  Stream<void> get changes => _changes.stream;

  Future<T?> _call<T>(String method, [Object? arguments]) async {
    try {
      return await channel.invokeMethod<T>(method, arguments);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    } on TypeError {
      // The native side sent something else than this asks for.
      return null;
    }
  }
}
