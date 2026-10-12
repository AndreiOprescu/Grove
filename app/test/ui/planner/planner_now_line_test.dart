// The now line of the planner and the frames it asks for (PLAN §6.3: "Now
// line gently pulses (opacity 1 → 0.45, 3.2 s)").
//
// A planner that nobody touches must not ask the engine for a frame at each
// refresh of the screen. With motion on, the pulse needs 20 frames a second
// at most.
// With motion off, or with the window not in front, it needs none. The line
// moves when the minute changes.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/ui/planner/planner_kind.dart';
import 'package:grove/ui/planner/planner_view.dart';

import '../tasks/tasks_support.dart' show pumpPane;
import 'planner_support.dart' hide Layer;

const size = Size(1100, 620);

final line = find.byKey(const ValueKey('now-line'));

/// The part of the now line that fades.
final fade = find.descendant(of: line, matching: find.byType(FadeTransition));

/// The planner with no shell around it, so no other part of the app asks
/// for a frame (the moving background is a part of the shell).
Future<void> pumpGrid(
  WidgetTester tester,
  AppStore store, {
  PlannerKind kind = PlannerKind.week,
}) => pumpPane(
  tester,
  PlannerView(store: store, kind: kind),
  size: size,
);

/// How many frames the screen asks for in `time` while nobody touches it.
/// The clock of the test goes on in steps of `step`. With a step of one
/// millisecond a running ticker asks for 1000 frames a second here; on a
/// device it asks for one at each refresh of the screen.
Future<int> framesAsked(
  WidgetTester tester, {
  Duration time = const Duration(seconds: 1),
  Duration step = const Duration(milliseconds: 1),
}) async {
  var frames = 0;
  for (var at = Duration.zero; at < time; at += step) {
    await tester.binding.delayed(step);
    if (tester.binding.hasScheduledFrame) {
      frames++;
      await tester.pump();
    }
  }
  return frames;
}

/// How strong the now line is drawn, 0 to 1.
double strength(WidgetTester tester) =>
    tester.widget<FadeTransition>(fade).opacity.value;

/// The frames of one second of the pulse: 20 steps, less the steps at the
/// top and at the bottom of the pulse, where the line looks the same.
final aSecondOfPulse = inInclusiveRange(15, 20);

/// The middle of the now line, top to bottom.
double lineY(WidgetTester tester) => tester.getRect(line).center.dy;

void moveClock(AppStore store, DayKey day, int minute) =>
    store.clockOverride = WallTime(day: day, minute: minute);

/// Says to the app that its window is in front, or not.
void setInFront(WidgetTester tester, bool inFront) {
  tester.binding.handleAppLifecycleStateChanged(
    inFront ? AppLifecycleState.resumed : AppLifecycleState.inactive,
  );
}

/// Starts the pulse again from its first step: the line is at full strength.
/// The pulse began when the screen came up, some steps ago.
Future<void> restartPulse(WidgetTester tester) async {
  addTearDown(() => setInFront(tester, true));
  setInFront(tester, false);
  setInFront(tester, true);
  await tester.pump();
}

/// Each picture that the window is made of. A part that is painted again
/// gets a new one.
List<Object?> pictures(WidgetTester tester) {
  final found = <Object?>[];
  void visit(Layer layer) {
    if (layer is PictureLayer) found.add(layer.picture);
    if (layer is ContainerLayer) {
      for (var c = layer.firstChild; c != null; c = c.nextSibling) {
        visit(c);
      }
    }
  }

  visit(tester.binding.renderViews.first.debugLayer!);
  return found;
}

void main() {
  group('a planner that nobody touches, with motion on', () {
    testWidgets('no frame waits after a frame', (tester) async {
      final store = plannerStore(motion: true);
      await pumpGrid(tester, store);
      expect(line, findsOneWidget);

      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 7));
        expect(tester.binding.hasScheduledFrame, isFalse);
        expect(tester.hasRunningAnimations, isFalse);
      }
    });

    testWidgets('the pulse asks for 20 frames a second at most, not one at '
        'each refresh of the screen', (tester) async {
      final store = plannerStore(motion: true);
      await pumpGrid(tester, store);

      expect(await framesAsked(tester), aSecondOfPulse);
      expect(
        await framesAsked(tester, time: const Duration(seconds: 5)),
        inInclusiveRange(85, 100),
      );
    });

    // The whole Today screen has a plant in its header too. The plant has a
    // clock of its own, in the theme folder.
    testWidgets('the timeline of the Today screen asks for the same 20 '
        'frames a second', (tester) async {
      final store = plannerStore(motion: true)..screen = Screen.today;
      await pumpGrid(tester, store, kind: PlannerKind.today);
      expect(line, findsOneWidget);

      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(await framesAsked(tester), aSecondOfPulse);
    });

    testWidgets('the pulse goes from 1 to 0.45 and back in 3.2 seconds', (
      tester,
    ) async {
      final store = plannerStore(motion: true);
      await pumpGrid(tester, store);
      await restartPulse(tester);
      expect(strength(tester), 1);

      await framesAsked(tester, time: const Duration(milliseconds: 800));
      expect(strength(tester), closeTo(0.725, 0.001));
      await framesAsked(tester, time: const Duration(milliseconds: 800));
      expect(strength(tester), closeTo(0.45, 0.001));
      await framesAsked(tester, time: const Duration(milliseconds: 1600));
      expect(strength(tester), closeTo(1, 0.001));
      await framesAsked(tester, time: const Duration(milliseconds: 1600));
      expect(strength(tester), closeTo(0.45, 0.001));
    });

    testWidgets('one step changes the line by 0.03 at most', (tester) async {
      final store = plannerStore(motion: true);
      await pumpGrid(tester, store);
      await restartPulse(tester);

      var last = strength(tester);
      var steps = 0;
      for (var ms = 0; ms < 3200; ms++) {
        await tester.binding.delayed(const Duration(milliseconds: 1));
        if (!tester.binding.hasScheduledFrame) continue;
        await tester.pump();
        final next = strength(tester);
        expect((next - last).abs(), lessThanOrEqualTo(0.03));
        last = next;
        steps++;
      }
      expect(steps, inInclusiveRange(55, 64));
    });

    testWidgets('a step of the pulse paints no part of the window again', (
      tester,
    ) async {
      final store = plannerStore(motion: true);
      store.createFromDraft(
        title: 'Lunch',
        day: wednesday,
        start: 12 * 60,
        end: 13 * 60,
        asEvent: true,
      );
      await pumpGrid(tester, store);
      final box = tester.renderObject(fade);
      // The line is a layer of its own.
      expect(box.isRepaintBoundary, isTrue);
      final layer = box.debugLayer! as OpacityLayer;

      for (var step = 0; step < 10; step++) {
        final before = pictures(tester);
        final alpha = layer.alpha;
        expect(before, isNotEmpty);
        expect(
          await framesAsked(tester, time: const Duration(milliseconds: 50)),
          1,
        );

        // The layer of the line is the same one with a new strength, and
        // each picture of the window is the old one.
        expect(box.debugLayer, same(layer));
        expect(layer.alpha, isNot(alpha));
        final after = pictures(tester);
        expect(after.length, before.length);
        for (var i = 0; i < before.length; i++) {
          expect(after[i], same(before[i]));
        }
      }
    });

    testWidgets('the window is not in front: the pulse stops, and it starts '
        'again with the window', (tester) async {
      addTearDown(() => setInFront(tester, true));
      final store = plannerStore(motion: true);
      await pumpGrid(tester, store);
      await framesAsked(tester, time: const Duration(milliseconds: 800));
      expect(strength(tester), lessThan(1));

      setInFront(tester, false);
      await tester.pump();
      expect(strength(tester), 1);
      expect(await framesAsked(tester, time: const Duration(seconds: 3)), 0);

      setInFront(tester, true);
      await tester.pump();
      expect(await framesAsked(tester), aSecondOfPulse);
    });

    testWidgets('a planner under another screen stops its pulse', (
      tester,
    ) async {
      final store = plannerStore(motion: true);
      final shown = ValueNotifier(true);
      addTearDown(shown.dispose);
      await pumpPane(
        tester,
        ValueListenableBuilder(
          valueListenable: shown,
          builder: (context, enabled, child) =>
              TickerMode(enabled: enabled, child: child!),
          child: PlannerView(store: store, kind: PlannerKind.week),
        ),
        size: size,
      );
      expect(await framesAsked(tester), aSecondOfPulse);

      shown.value = false;
      await tester.pump();
      expect(strength(tester), 1);
      expect(await framesAsked(tester, time: const Duration(seconds: 3)), 0);

      shown.value = true;
      await tester.pump();
      expect(await framesAsked(tester), aSecondOfPulse);
    });

    testWidgets('"Reduce motion" of the system stops the pulse', (
      tester,
    ) async {
      final store = plannerStore(motion: true);
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await pumpGrid(tester, store);

      expect(strength(tester), 1);
      expect(await framesAsked(tester, time: const Duration(seconds: 3)), 0);
    });

    testWidgets('the screen goes away with a pulse on its way: no error', (
      tester,
    ) async {
      final store = plannerStore(motion: true);
      await pumpGrid(tester, store);
      await framesAsked(tester, time: const Duration(milliseconds: 120));

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(await framesAsked(tester, time: const Duration(seconds: 2)), 0);
      expect(tester.takeException(), isNull);
    });
  });

  group('a planner that nobody touches, with motion off', () {
    testWidgets('no frame in two minutes while the minute is the same', (
      tester,
    ) async {
      final store = plannerStore();
      await pumpGrid(tester, store);
      expect(strength(tester), 1);

      expect(
        await framesAsked(
          tester,
          time: const Duration(minutes: 2),
          step: const Duration(milliseconds: 500),
        ),
        0,
      );
      expect(strength(tester), 1);
    });

    testWidgets('a new minute asks for one frame', (tester) async {
      final store = plannerStore();
      await pumpGrid(tester, store);

      moveClock(store, wednesday, 10 * 60 + 1);
      expect(
        await framesAsked(
          tester,
          time: const Duration(minutes: 1),
          step: const Duration(milliseconds: 500),
        ),
        1,
      );
    });

    testWidgets('motion goes on in Settings: the pulse starts; off: it stops', (
      tester,
    ) async {
      final store = plannerStore();
      await pumpGrid(tester, store);
      expect(await framesAsked(tester), 0);

      store.setMotion(true);
      await tester.pump();
      expect(await framesAsked(tester), aSecondOfPulse);

      store.setMotion(false);
      await tester.pump();
      expect(strength(tester), 1);
      expect(await framesAsked(tester), 0);
      // The store says "Motion off" for a moment. Its timer ends here.
      await tester.binding.delayed(const Duration(seconds: 3));
    });
  });

  group('the now line follows the clock', () {
    for (final motion in [false, true]) {
      final mode = motion ? 'motion on' : 'motion off';

      testWidgets('$mode: the line is at the minute of the clock, and moves '
          'with it', (tester) async {
        final store = plannerStore(motion: motion);
        await pumpGrid(tester, store);
        final start = lineY(tester);
        expect(start, pointAt(tester, wednesday, 10 * 60).dy);

        // Half an hour later the line is half an hour lower.
        moveClock(store, wednesday, 10 * 60 + 30);
        await tester.pump(const Duration(seconds: 20));
        await tester.pump();
        expect(lineY(tester), start + hour / 2);
        expect(lineY(tester), pointAt(tester, wednesday, 10 * 60 + 30).dy);

        // One minute is a little more than one point.
        moveClock(store, wednesday, 10 * 60 + 31);
        await tester.pump(const Duration(seconds: 20));
        await tester.pump();
        expect(lineY(tester), closeTo(start + hour * 31 / 60, 0.001));
      });

      testWidgets('$mode: the faded past ends at the line', (tester) async {
        final store = plannerStore(motion: motion);
        await pumpGrid(tester, store);
        final past = find.byKey(const ValueKey('past-shade'));
        expect(tester.getRect(past).bottom, lineY(tester));

        moveClock(store, wednesday, 13 * 60 + 10);
        await tester.pump(const Duration(seconds: 20));
        await tester.pump();
        expect(tester.getRect(past).bottom, lineY(tester));
        expect(lineY(tester), pointAt(tester, wednesday, 13 * 60 + 10).dy);
      });

      testWidgets('$mode: after midnight the line is in the next day', (
        tester,
      ) async {
        final store = plannerStore(motion: motion, now: 23 * 60 + 58);
        await pumpGrid(tester, store);
        final thursday = wednesday.adding(days: 1);
        expect(
          tester
              .getRect(columnFinder(wednesday))
              .contains(tester.getRect(line).center),
          isTrue,
        );

        moveClock(store, thursday, 2);
        await tester.pump(const Duration(seconds: 20));
        await tester.pump();
        final middle = tester.getRect(line).center;
        expect(tester.getRect(columnFinder(thursday)).contains(middle), isTrue);
        expect(
          middle.dy - tester.getRect(columnFinder(thursday)).top,
          closeTo(hour * 2 / 60, 0.001),
        );
      });
    }

    testWidgets('the line waits 20 seconds at most for the new minute', (
      tester,
    ) async {
      final store = plannerStore();
      await pumpGrid(tester, store);
      final start = lineY(tester);

      moveClock(store, wednesday, 10 * 60 + 15);
      await tester.pump(const Duration(seconds: 19));
      await tester.pump();
      expect(lineY(tester), start);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(lineY(tester), start + hour / 4);
    });

    testWidgets('a week with no today has no now line and asks for no '
        'frame', (tester) async {
      final store = plannerStore(motion: true);
      store.selectedDay = wednesday.adding(days: 14);
      await pumpGrid(tester, store);

      expect(line, findsNothing);
      expect(await framesAsked(tester, time: const Duration(seconds: 2)), 0);
    });
  });
}
