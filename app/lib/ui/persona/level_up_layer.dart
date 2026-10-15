// A small pop-up at the top of the window when a skill reaches a new level.
// It shows over every screen and goes away by itself (`AppStore.levelUp`).
import 'package:flutter/widgets.dart';
import 'package:grove/state/state.dart' hide MotionRules;

import '../tasks/task_widgets.dart' show StoreBuilder;
import '../theme/grove_theme.dart';

class LevelUpLayer extends StatelessWidget {
  const LevelUpLayer({super.key, required this.store, required this.child});

  final AppStore store;
  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.passthrough,
    children: [
      child,
      Positioned.fill(
        child: IgnorePointer(
          child: StoreBuilder(
            store: store,
            builder: (context) => _popUp(context),
          ),
        ),
      ),
    ],
  );

  Widget _popUp(BuildContext context) {
    final up = store.levelUp;
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween(
                  begin: const Offset(0, -0.6),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
            child: up == null
                ? const SizedBox.shrink()
                : _card(context, up.skillName, up.level),
          ),
        ),
      ),
    );
  }

  Widget _card(BuildContext context, String skill, int level) {
    final theme = GroveTheme.of(context);
    final text = '$skill reached level $level';
    return Semantics(
      key: const ValueKey('level-up'),
      liveRegion: true,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: theme.accent,
          shape: const StadiumBorder(),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 8,
            children: [
              Text('★', style: theme.body(14).copyWith(color: theme.bg)),
              Text(
                text,
                style: theme
                    .body(13, weight: FontWeight.w700)
                    .copyWith(color: theme.bg),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
