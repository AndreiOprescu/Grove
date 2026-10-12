// Port of Sources/Grove/Garden/GardenView.swift: the Garden screen. One
// plant that grows with every task you finish.
import 'dart:math';

import 'package:flutter/widgets.dart';

import '../../core/services/garden.dart';
import '../../state/rules/plant_math.dart' show PlantMath;
import '../../state/state.dart' show AppStore, AppStoreAppearance;
import '../shell/shell_layout.dart';
import '../tasks/task_widgets.dart' show StoreBuilder, WholeCenter;
import '../theme/grove_theme.dart';
import '../theme/growing_plant.dart' show GrowingPlant;
import '../theme/panel.dart';
import '../theme/sway_clock.dart';
import '../theme/theme_math.dart';
import 'garden_painter.dart';

class GardenView extends StatelessWidget {
  const GardenView({super.key, required this.store});

  final AppStore store;

  /// The page is never wider than this.
  static const maxWidth = 980.0;

  /// The height of the big plant.
  static const plantHeight = 360.0;

  /// How long the plant takes to grow to a new size.
  static const growTime = Duration(milliseconds: 900);

  /// The sway in degrees. A big tree sways less than a sprout.
  static double sway({required double growth, required double at}) =>
      PlantMath.swayDegrees(at: at) * (1 - 0.5 * growth / Garden.maxGrowth);

  static String finished(int done) =>
      done == 1 ? '1 task finished' : '$done tasks finished';

  @override
  Widget build(BuildContext context) => StoreBuilder(
    store: store,
    builder: (context) {
      final done = store.gardenDone();
      final stage = Garden.stage(done: done);
      final phone =
          ShellRules.layoutFor(MediaQuery.sizeOf(context).width) ==
          ShellLayout.phone;
      final side = phone ? 12.0 : 24.0;
      return SingleChildScrollView(
        child: WholeCenter(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: maxWidth),
            child: Padding(
              padding: EdgeInsets.fromLTRB(side, 6, side, phone ? 12 : 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 18,
                children: [
                  _header(context, phone),
                  _hero(context, done, stage),
                  _ladder(context, done, stage),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );

  Widget _header(BuildContext context, bool phone) {
    final theme = GroveTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 2,
      children: [
        ThemedHeading('Garden', phone ? 22 : 28),
        Text(
          'Your plant grows each time you finish a task.',
          style: theme.body(12).copyWith(color: theme.muted),
        ),
      ],
    );
  }

  // The plant

  Widget _hero(BuildContext context, int done, GardenStage stage) {
    final theme = GroveTheme.of(context);
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: 'Garden plant, ${stage.name}',
      value: finished(done),
      child: Panel(
        key: const ValueKey('garden-hero'),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            spacing: 14,
            children: [
              SizedBox(height: plantHeight, child: _plant(context, done)),
              Column(
                spacing: 4,
                children: [
                  WholeCenter(child: ThemedHeading(stage.name, 24)),
                  WholeCenter(
                    child: Text(
                      finished(done),
                      style: theme.body(13).copyWith(color: theme.muted),
                    ),
                  ),
                ],
              ),
              _nextStep(context, done),
            ],
          ),
        ),
      ),
    );
  }

  Widget _plant(BuildContext context, int done) {
    final motionOn = MotionRules.isOn(
      setting: store.motionSetting,
      reduceMotion: MediaQuery.disableAnimationsOf(context),
    );
    return TweenAnimationBuilder<double>(
      tween: Tween(end: Garden.growth(done: done)),
      duration: motionOn ? growTime : Duration.zero,
      curve: Curves.easeOutBack,
      builder: (context, growth, _) {
        // The bounce at the end must not leave the range of the picture.
        final shown = max(0.0, min(Garden.maxGrowth, growth));
        // The two boundaries: a sway draws only the plant again, not the
        // page around it.
        return RepaintBoundary(
          child: SwayClock(
            on: motionOn,
            framesPerSecond: SwayClock.framesFor(
              reach: plantHeight * 0.88,
              degreesPerSecond: GrowingPlant.swaySpeed,
            ),
            builder: (context, seconds) => Transform.rotate(
              angle: motionOn ? sway(growth: shown, at: seconds) * pi / 180 : 0,
              // The foot of the plant: 0.88 of the way down.
              alignment: const Alignment(0, 0.76),
              child: RepaintBoundary(child: GardenDrawing(growth: shown)),
            ),
          ),
        );
      },
    );
  }

  Widget _nextStep(BuildContext context, int done) {
    final theme = GroveTheme.of(context);
    final small = theme.body(12).copyWith(color: theme.muted);
    final next = Garden.next(after: done);
    final left = Garden.tasksToNext(done: done);
    if (next == null || left == null) {
      return WholeCenter(
        child: Text(
          'Fully grown. Keep going. It likes company.',
          textAlign: TextAlign.center,
          style: small,
        ),
      );
    }
    return Column(
      spacing: 6,
      children: [
        WholeCenter(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: SizedBox(
              key: const ValueKey('garden-bar'),
              height: 8,
              child: LayoutBuilder(
                builder: (context, box) => DecoratedBox(
                  decoration: ShapeDecoration(
                    color: theme.surface2,
                    shape: StadiumBorder(side: BorderSide(color: theme.line)),
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: SizedBox(
                      key: const ValueKey('garden-bar-fill'),
                      width: max(
                        8.0,
                        (box.maxWidth * Garden.progress(done: done))
                            .roundToDouble(),
                      ),
                      height: 8,
                      child: DecoratedBox(
                        decoration: ShapeDecoration(
                          color: theme.accent,
                          shape: const StadiumBorder(),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        WholeCenter(
          child: Text(
            '$left more ${left == 1 ? 'task' : 'tasks'} to become a '
            '${next.name.toLowerCase()}',
            textAlign: TextAlign.center,
            style: small,
          ),
        ),
      ],
    );
  }

  // All the stages

  static const _cardMinimum = 118.0;
  static const _cardMaximum = 160.0;
  static const _cardGap = 10.0;

  Widget _ladder(BuildContext context, int done, GardenStage current) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: 10,
    children: [
      const ThemedHeading('Stages', 16),
      LayoutBuilder(
        builder: (context, box) {
          // As many cards in a row as fit, each on whole points.
          final count = max(
            1,
            ((box.maxWidth + _cardGap) / (_cardMinimum + _cardGap)).floor(),
          );
          final width = min(
            _cardMaximum,
            ((box.maxWidth - _cardGap * (count - 1)) / count).floorToDouble(),
          );
          return Wrap(
            spacing: _cardGap,
            runSpacing: _cardGap,
            children: [
              for (final stage in Garden.stages)
                SizedBox(
                  width: width,
                  child: _StageCard(
                    stage: stage,
                    reached: done >= stage.from,
                    isCurrent: stage == current,
                  ),
                ),
            ],
          );
        },
      ),
    ],
  );
}

class _StageCard extends StatelessWidget {
  const _StageCard({
    required this.stage,
    required this.reached,
    required this.isCurrent,
  });

  final GardenStage stage;
  final bool reached;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    final from = stage.from;
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: '${stage.name}, from $from tasks',
      value: isCurrent
          ? 'Now'
          : reached
          ? 'Reached'
          : 'Not yet',
      child: DecoratedBox(
        key: ValueKey('garden-stage-${stage.index}'),
        decoration: BoxDecoration(
          color: theme.surface2.withValues(
            alpha: theme.surface2.a * (reached ? 1 : 0.5),
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isCurrent ? theme.accent : theme.line,
            width: isCurrent ? 2 : 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: 4,
            children: [
              Opacity(
                opacity: reached ? 1 : 0.25,
                child: SizedBox(
                  height: 96,
                  child: GardenDrawing(growth: stage.index.toDouble()),
                ),
              ),
              WholeCenter(
                child: Text(
                  stage.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme
                      .body(12, weight: FontWeight.w600)
                      .copyWith(color: reached ? theme.ink : theme.muted),
                ),
              ),
              WholeCenter(
                child: Text(
                  from == 0 ? 'Start' : '$from ${from == 1 ? 'task' : 'tasks'}',
                  style: theme.body(10).copyWith(color: theme.muted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
