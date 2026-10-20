// Port of Sources/Grove/Theme/CheckBox.swift, without the burst.
import 'dart:math';

import 'package:flutter/material.dart';

import 'grove_theme.dart';

/// The box in front of a task (PLAN §6.2): round in Grove and Minimal,
/// square in Futuristic and Vintage. It only draws. The button around it
/// does the work.
class CheckBox extends StatelessWidget {
  const CheckBox({super.key, required this.isOn, this.size = 17});

  final bool isOn;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    final radius = theme.squareChecks ? max(2.0, size * 0.16) : size / 2;
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: isOn ? theme.accent : null,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: isOn ? theme.accent : theme.muted,
              width: 1.5,
            ),
            boxShadow: [
              if (theme.glow && isOn)
                BoxShadow(
                  color: theme.accent.withValues(alpha: 0.55),
                  blurRadius: 5,
                ),
            ],
          ),
          child: isOn
              ? Center(
                  child: Icon(
                    Icons.check,
                    size: size * 0.7,
                    weight: 900,
                    color: theme.bg,
                  ),
                )
              : null,
        ),
      ),
    );
  }
}
