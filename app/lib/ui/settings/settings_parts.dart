// The small parts of the Settings window: a section with a title, a row
// with a name and a control, a switch and a slider.
import 'package:flutter/material.dart';

import '../theme/grove_theme.dart';

/// A group of settings with a title, as a section of the form of the Mac
/// app.
class SettingsSection extends StatelessWidget {
  const SettingsSection({super.key, this.title, required this.children});

  /// No title line when null.
  final String? title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    final title = this.title;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 6,
      children: [
        if (title != null)
          Semantics(
            header: true,
            child: Text(
              title,
              style: theme
                  .body(12, weight: FontWeight.w600)
                  .copyWith(color: theme.muted),
            ),
          ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: theme.surface2,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: theme.line),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 10,
              children: children,
            ),
          ),
        ),
      ],
    );
  }
}

/// A name at the left and its control at the right.
class SettingsRow extends StatelessWidget {
  const SettingsRow({super.key, required this.label, required this.control});

  final String label;
  final Widget control;

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    return Row(
      spacing: 12,
      children: [
        Expanded(
          // The control says the name to a screen reader.
          child: ExcludeSemantics(
            child: Text(
              label,
              style: theme.body(13).copyWith(color: theme.ink),
            ),
          ),
        ),
        control,
      ],
    );
  }
}

/// The small grey text under a setting.
class SettingsCaption extends StatelessWidget {
  const SettingsCaption(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    return Text(text, style: theme.body(11).copyWith(color: theme.muted));
  }
}

/// An on and off switch.
class GroveSwitch extends StatelessWidget {
  const GroveSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    required this.label,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  /// What a screen reader says.
  final String label;

  static const size = Size(36, 20);
  static const _time = Duration(milliseconds: 120);

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    void flip() => onChanged(!value);
    return Semantics(
      container: true,
      toggled: value,
      label: label,
      onTap: flip,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: flip,
          child: AnimatedContainer(
            duration: _time,
            width: size.width,
            height: size.height,
            padding: const EdgeInsets.all(3),
            decoration: ShapeDecoration(
              color: value ? theme.accent : theme.surface,
              shape: StadiumBorder(
                side: BorderSide(color: value ? theme.accent : theme.line),
              ),
            ),
            child: AnimatedAlign(
              duration: _time,
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              child: SizedBox.square(
                dimension: 14,
                child: DecoratedBox(
                  decoration: ShapeDecoration(
                    color: value ? theme.solidSurface : theme.muted,
                    shape: const CircleBorder(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A switch with its name in front.
class SettingsSwitchRow extends StatelessWidget {
  const SettingsSwitchRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    required this.switchKey,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Key switchKey;

  @override
  Widget build(BuildContext context) => SettingsRow(
    label: label,
    control: GroveSwitch(
      key: switchKey,
      value: value,
      onChanged: onChanged,
      label: label,
    ),
  );
}

/// A slider with its name and its value in a line above it.
class SettingsSlider extends StatelessWidget {
  const SettingsSlider({
    super.key,
    required this.sliderKey,
    required this.label,
    required this.valueText,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final Key sliderKey;
  final String label;

  /// The value in words: "100%", "64 pt".
  final String valueText;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    return MergeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 2,
        children: [
          Row(
            spacing: 12,
            children: [
              Expanded(
                child: Text(
                  label,
                  style: theme.body(13).copyWith(color: theme.ink),
                ),
              ),
              ExcludeSemantics(
                child: Text(
                  valueText,
                  style: theme.number(12).copyWith(color: theme.muted),
                ),
              ),
            ],
          ),
          SizedBox(
            height: 24,
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 4,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                activeTrackColor: theme.accent,
                inactiveTrackColor: theme.line,
                thumbColor: theme.accent,
                overlayColor: theme.accent.withValues(alpha: 0.12),
                thumbShape: const RoundSliderThumbShape(
                  enabledThumbRadius: 7,
                  elevation: 0,
                  pressedElevation: 0,
                ),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                trackShape: const RoundedRectSliderTrackShape(),
              ),
              child: Slider(
                key: sliderKey,
                value: value.clamp(min, max),
                min: min,
                max: max,
                onChanged: onChanged,
                semanticFormatterCallback: (_) => valueText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
