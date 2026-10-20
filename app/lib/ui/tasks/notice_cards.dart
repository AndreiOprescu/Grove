// Port of Sources/Grove/Tasks/NoticeCards.swift.
import 'package:flutter/material.dart';
import 'package:grove/data/data.dart' show RollOverItem;
import 'package:grove/state/state.dart' hide MotionRules;

import '../theme/grove_theme.dart';
import '../theme/panel.dart';
import 'task_widgets.dart';

/// The look of the two small cards at the top of the task list.
class _Notice extends StatelessWidget {
  const _Notice({required this.label, required this.children});

  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    return Semantics(
      container: true,
      label: label,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.surface2,
          borderRadius: BorderRadius.circular(theme.radius),
          border: Border.all(
            color: theme.line,
            width: theme.hairlines ? 0.5 : 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            spacing: 8,
            children: children,
          ),
        ),
      ),
    );
  }
}

Widget _title(IconData icon, Color tint, String text) => Row(
  spacing: 6,
  children: [
    Icon(icon, size: 15, color: tint),
    Expanded(child: ThemedHeading(text, 15)),
  ],
);

/// First launch (PLAN §9): says what the three sample tasks are for.
class WelcomeCard extends StatelessWidget {
  const WelcomeCard({super.key, required this.store});

  final AppStore store;

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    return _Notice(
      label: 'Welcome to Grove',
      children: [
        _title(Icons.eco, theme.accent, 'Welcome to Grove'),
        Text(
          "Three sample tasks wait on today's list. Each one shows a trick.",
          style: theme.body(12).copyWith(color: theme.muted),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            CardButton(
              label: 'Got it',
              primary: true,
              onTap: store.dismissWelcome,
            ),
            CardButton(label: 'Remove samples', onTap: store.removeSamples),
          ],
        ),
      ],
    );
  }
}

/// End of day (PLAN §5.1.7): open tasks that had a time block yesterday.
class RollOverCard extends StatelessWidget {
  const RollOverCard({super.key, required this.store, required this.items});

  final AppStore store;
  final List<RollOverItem> items;

  static String title(int count) =>
      count == 1 ? '1 thing from yesterday' : '$count things from yesterday';

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    final small = theme.body(12).copyWith(color: theme.muted);
    return _Notice(
      label: title(items.length),
      children: [
        _title(Icons.wb_twilight, theme.accent2, title(items.length)),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          spacing: 2,
          children: [
            for (final item in items.take(3))
              Text(
                item.task.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: small,
              ),
            if (items.length > 3)
              Text('and ${items.length - 3} more', style: small),
          ],
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            CardButton(
              label: 'Move to today',
              primary: true,
              onTap: store.moveRollOver,
            ),
            CardButton(label: 'Leave', onTap: store.leaveRollOver),
          ],
        ),
      ],
    );
  }
}
