// The speed test of the goal map: 50 squares and 70 lines, with each kind of
// move. Run it in profile mode on a real device:
//
//   flutter run --profile -t tool/goal_map_bench.dart -d <device>
//
// It prints the frame times of each part, then "BENCH DONE".
// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:grove/core/goals/goal_graph.dart';
import 'package:grove/core/model/goal_square.dart';
import 'package:grove/ui/goal_map/goal_map_view.dart';

const _a = 'A', _b = 'B';

class _Fixture {
  _Fixture(this.goalId, {int squares = 50, int lines = 70, int seed = 3}) {
    final rnd = Random(seed);
    final root = GoalSquare.rootIdOf(goalId);
    final all = [root, for (var i = 1; i < squares; i++) '$goalId$i'];
    ids = all;
    for (var i = 1; i < all.length; i++) {
      links.add(SquareLink(childId: all[i], parentId: all[rnd.nextInt(i)]));
    }
    while (links.length < lines) {
      final c = 1 + rnd.nextInt(all.length - 1);
      final link = SquareLink(childId: all[c], parentId: all[rnd.nextInt(c)]);
      if (!links.contains(link)) links.add(link);
    }
  }

  final String goalId;
  late final List<String> ids;
  final links = <SquareLink>[];
  final done = <String>{};
  final extra = <String>[];

  GoalGraph get graph => GoalGraph.build(goalId, [
    for (final id in [...ids, ...extra])
      GoalSquare(
        id: id,
        goalId: goalId,
        title: 'Step $id of the work',
        doneAt: done.contains(id) ? '2026-11-05T10:00:00' : null,
      ),
  ], links);

  /// The squares with no open child: a tick on one wakes its parents.
  String? nextReady(GoalGraph g) {
    for (final id in g.readyIds) {
      if (id != g.rootId) return id;
    }
    return null;
  }
}

void main() {
  runApp(const _Bench());
}

class _Bench extends StatefulWidget {
  const _Bench();

  @override
  State<_Bench> createState() => _BenchState();
}

class _BenchState extends State<_Bench> {
  final _fixtures = {_a: _Fixture(_a), _b: _Fixture(_b, seed: 11)};
  final _controller = GoalMapController();
  String _goal = _a;
  String? _selected;
  String _part = 'start';
  final _times = <String, List<FrameTiming>>{};

  _Fixture get _f => _fixtures[_goal]!;

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback((list) {
      (_times[_part] ??= []).addAll(list);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_run()));
  }

  Future<void> _wait(int ms) => Future.delayed(Duration(milliseconds: ms));

  Future<void> _run() async {
    await _wait(1500);
    _part = 'rest';
    await _wait(2000);
    _part = 'tick';
    for (var i = 0; i < 6; i++) {
      final id = _f.nextReady(_f.graph);
      if (id != null) setState(() => _f.done.add(id));
      await _wait(1200);
    }
    _part = 'add and delete';
    final parent = _f.ids[1];
    for (var i = 0; i < 6; i++) {
      final id = 'new$i';
      setState(() {
        _f.extra.add(id);
        _f.links.add(SquareLink(childId: id, parentId: parent));
        _selected = id;
      });
      await _wait(600);
      setState(() {
        _f.extra.remove(id);
        _f.links.removeWhere((l) => l.childId == id);
        _selected = null;
      });
      await _wait(600);
    }
    _part = 'pan';
    await _pan();
    _part = 'pinch';
    await _pinch();
    _part = 'fit';
    for (var i = 0; i < 3; i++) {
      _controller.fit();
      await _wait(700);
    }
    _part = 'change goal';
    for (var i = 0; i < 4; i++) {
      setState(() => _goal = _goal == _a ? _b : _a);
      await _wait(1400);
    }
    _part = 'root wave';
    setState(() => _f.done.add(_f.graph.rootId));
    await _wait(2000);
    _part = 'end';
    await _wait(300);
    _report();
  }

  Offset get _middle {
    final view = PlatformDispatcher.instance.views.first;
    return (view.physicalSize / view.devicePixelRatio).center(Offset.zero);
  }

  void _send(PointerEvent e) => GestureBinding.instance.handlePointerEvent(e);

  Future<void> _pan() async {
    final start = _middle;
    for (var turn = 0; turn < 4; turn++) {
      final way = turn.isEven ? 6.0 : -6.0;
      var at = start;
      _send(PointerDownEvent(pointer: 1, position: at));
      for (var i = 0; i < 60; i++) {
        await _wait(16);
        at += Offset(way, way / 3);
        _send(
          PointerMoveEvent(
            pointer: 1,
            position: at,
            delta: Offset(way, way / 3),
          ),
        );
      }
      _send(PointerUpEvent(pointer: 1, position: at));
      await _wait(250);
    }
  }

  Future<void> _pinch() async {
    final c = _middle;
    for (var turn = 0; turn < 2; turn++) {
      final out = turn.isEven ? 2.5 : -2.5;
      var spread = turn.isEven ? 60.0 : 220.0;
      _send(PointerDownEvent(pointer: 2, position: c - Offset(spread, 0)));
      _send(PointerDownEvent(pointer: 3, position: c + Offset(spread, 0)));
      for (var i = 0; i < 60; i++) {
        await _wait(16);
        spread += out;
        _send(
          PointerMoveEvent(
            pointer: 2,
            position: c - Offset(spread, 0),
            delta: Offset(-out, 0),
          ),
        );
        _send(
          PointerMoveEvent(
            pointer: 3,
            position: c + Offset(spread, 0),
            delta: Offset(out, 0),
          ),
        );
      }
      _send(PointerUpEvent(pointer: 2, position: c - Offset(spread, 0)));
      _send(PointerUpEvent(pointer: 3, position: c + Offset(spread, 0)));
      await _wait(300);
    }
  }

  void _report() {
    final refresh = PlatformDispatcher.instance.views.first.display.refreshRate;
    final budget = 1000 / refresh;
    print('BENCH refresh ${refresh.toStringAsFixed(0)} Hz');
    print(
      'BENCH part | frames | build p50 p90 p99 max | raster p50 p90 p99 '
      'max | over budget',
    );
    for (final entry in _times.entries) {
      final t = entry.value;
      if (t.isEmpty) {
        print('BENCH ${entry.key} | 0 frames');
        continue;
      }
      final build = [for (final f in t) f.buildDuration.inMicroseconds / 1000];
      final raster = [
        for (final f in t) f.rasterDuration.inMicroseconds / 1000,
      ];
      final over = t
          .where(
            (f) =>
                f.buildDuration.inMicroseconds / 1000 > budget ||
                f.rasterDuration.inMicroseconds / 1000 > budget,
          )
          .length;
      print(
        'BENCH ${entry.key} | ${t.length} | ${_line(build)} | ${_line(raster)} '
        '| $over',
      );
    }
    print('BENCH DONE');
  }

  String _line(List<double> v) {
    final s = [...v]..sort();
    double p(double q) => s[((s.length - 1) * q).round()];
    return [
      p(.5),
      p(.9),
      p(.99),
      s.last,
    ].map((n) => n.toStringAsFixed(1)).join(' ');
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      body: GoalMapView(
        goalId: _goal,
        title: 'Delft AI Hub work',
        graph: _f.graph,
        goalColor: Colors.teal,
        motion: true,
        controller: _controller,
        selectedId: _selected,
      ),
    ),
  );
}
