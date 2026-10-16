// The bar of a level: how full the step to the next level is.
import 'dart:math';

import 'package:flutter/widgets.dart';

import '../theme/grove_theme.dart';

class SkillBar extends StatelessWidget {
  /// [name]: the start of the keys, so a test can find the bar and its fill.
  const SkillBar({
    super.key,
    required this.name,
    required this.fill,
    this.height = 8,
    this.color,
  });

  final String name;

  /// 0 to 1.
  final double fill;
  final double height;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    final f = max(0.0, min(1.0, fill));
    return SizedBox(
      key: ValueKey('$name-bar'),
      height: height,
      child: LayoutBuilder(
        builder: (context, box) => DecoratedBox(
          decoration: ShapeDecoration(
            color: theme.surface2,
            shape: StadiumBorder(side: BorderSide(color: theme.line)),
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              key: ValueKey('$name-fill'),
              // An empty bar shows no fill. A small one still shows a dot.
              width: f == 0
                  ? 0
                  : max(height, (box.maxWidth * f).roundToDouble()),
              height: height,
              child: DecoratedBox(
                decoration: ShapeDecoration(
                  color: color ?? theme.accent,
                  shape: const StadiumBorder(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
