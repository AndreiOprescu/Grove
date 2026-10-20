// The Persona screen: a drawn person who stands for the user, the good,
// okay and rough days, a bar for each skill, and the newest points. The
// skills grow when tasks and goal blocks with a reward are ticked done
// (CONTEXT.md, "Persona").
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:grove/core/model/day_key.dart';
import 'package:grove/core/services/persona.dart';
import 'package:grove/state/state.dart' hide MotionRules;

import '../shell/shell_layout.dart';
import '../tasks/task_widgets.dart';
import '../theme/grove_theme.dart';
import '../theme/panel.dart';
import 'day_bars.dart';
import 'persona_painter.dart';
import 'skill_bar.dart';

class PersonaView extends StatefulWidget {
  const PersonaView({super.key, required this.store});

  final AppStore store;

  /// The page is never wider than this.
  static const maxWidth = 980.0;

  /// The height of the person.
  static const drawingHeight = 300.0;

  /// From this width on, the person has a column of its own.
  static const twoColumns = 760.0;

  /// The width of the person's column.
  static const heroWidth = 340.0;

  /// The lines of the newest points.
  static const recentCount = 12;

  static String hiddenLine(int n) =>
      n == 1 ? '1 hidden skill' : '$n hidden skills';

  /// "today", "yesterday" or a short date.
  static String dayLabel(DayKey day, DayKey today) {
    if (day == today) return 'today';
    if (day == today.adding(days: -1)) return 'yesterday';
    return NotesRules.shortDate(day);
  }

  @override
  State<PersonaView> createState() => _PersonaViewState();
}

class _PersonaViewState extends State<PersonaView> {
  AppStore get _store => widget.store;

  /// The name field is open.
  bool _naming = false;

  /// The field for a new skill is open.
  bool _adding = false;

  /// The skill whose name field is open.
  String? _renaming;

  bool _showHidden = false;

  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _edit(VoidCallback open, String text) => setState(() {
    _naming = false;
    _adding = false;
    _renaming = null;
    open();
    _text.text = text;
    _text.selection = TextSelection(baseOffset: 0, extentOffset: text.length);
  });

  void _close() => setState(() {
    _naming = false;
    _adding = false;
    _renaming = null;
  });

  @override
  Widget build(BuildContext context) => StoreBuilder(
    store: _store,
    builder: (context) {
      final phone =
          ShellRules.layoutFor(MediaQuery.sizeOf(context).width) ==
          ShellLayout.phone;
      final side = phone ? 12.0 : 24.0;
      final points = _store.skillPoints;
      return SingleChildScrollView(
        child: WholeCenter(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: PersonaView.maxWidth),
            child: Padding(
              padding: EdgeInsets.fromLTRB(side, 6, side, phone ? 12 : 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 18,
                children: [
                  _header(context, phone),
                  LayoutBuilder(
                    builder: (context, box) => _top(
                      context,
                      points,
                      wide: box.maxWidth >= PersonaView.twoColumns,
                    ),
                  ),
                  _recent(context),
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
        ThemedHeading('Persona', phone ? 22 : 28),
        Text(
          'Your skills grow each time you finish a task or a goal block.',
          style: theme.body(12).copyWith(color: theme.muted),
        ),
      ],
    );
  }

  /// Wide: the person on the left, the days and the skills on the right.
  /// Narrow: one column.
  Widget _top(
    BuildContext context,
    Map<String, int> points, {
    required bool wide,
  }) {
    final days = DayBars(store: _store);
    if (!wide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 18,
        children: [_hero(context, points), days, _skills(context, points)],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 18,
      children: [
        SizedBox(width: PersonaView.heroWidth, child: _hero(context, points)),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 18,
            children: [days, _skills(context, points)],
          ),
        ),
      ],
    );
  }

  // The person

  Widget _hero(BuildContext context, Map<String, int> points) {
    final theme = GroveTheme.of(context);
    final total = points.values.fold(0, (a, b) => a + b);
    final level = SkillLevel.persona(total);
    final name = _store.personaName;
    return Semantics(
      container: true,
      label: 'Persona $name, level ${level.level}',
      child: Panel(
        key: const ValueKey('persona-hero'),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            spacing: 12,
            children: [
              const SizedBox(
                height: PersonaView.drawingHeight,
                child: RepaintBoundary(child: PersonaDrawing()),
              ),
              _name(context, name),
              WholeCenter(
                child: Text(
                  'Level ${level.level} · $total points',
                  key: const ValueKey('persona-level'),
                  style: theme.body(13).copyWith(color: theme.muted),
                ),
              ),
              WholeCenter(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: SkillBar(name: 'persona', fill: level.fill),
                ),
              ),
              WholeCenter(
                child: Text(
                  '${level.needed - level.into} more points to level '
                  '${level.level + 1}',
                  style: theme.body(12).copyWith(color: theme.muted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _name(BuildContext context, String name) {
    final theme = GroveTheme.of(context);
    if (_naming) {
      return WholeCenter(
        child: SizedBox(
          width: 240,
          child: GroveField(
            key: const ValueKey('persona-name-field'),
            controller: _text,
            placeholder: PersonaRules.defaultName,
            label: 'Name',
            maxLength: PersonaRules.maxNameLength,
            boxed: true,
            autofocus: true,
            style: theme.body(18, weight: FontWeight.w600),
            onSubmitted: (v) {
              _store.renamePersona(v);
              _close();
            },
            onEscape: _close,
          ),
        ),
      );
    }
    return WholeCenter(
      child: Tooltip(
        message: 'Change the name',
        child: GestureDetector(
          key: const ValueKey('persona-name'),
          behavior: HitTestBehavior.opaque,
          onTap: () => _edit(() => _naming = true, name),
          child: MouseRegion(
            cursor: SystemMouseCursors.text,
            child: ThemedHeading(name, 24),
          ),
        ),
      ),
    );
  }

  // The skills

  Widget _skills(BuildContext context, Map<String, int> points) {
    final theme = GroveTheme.of(context);
    final all = _store.skills;
    final hidden = all.where((s) => s.hidden).length;
    final shown = [
      for (final s in all)
        if (!s.hidden || _showHidden) s,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 10,
      children: [
        const ThemedHeading('Skills', 16),
        LayoutBuilder(
          builder: (context, box) {
            const gap = 10.0;
            final count = max(1, ((box.maxWidth + gap) / (260 + gap)).floor());
            final width = ((box.maxWidth - gap * (count - 1)) / count)
                .floorToDouble();
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final s in shown)
                  SizedBox(
                    width: width,
                    child: _skillCard(context, s, points[s.id] ?? 0),
                  ),
              ],
            );
          },
        ),
        Wrap(
          spacing: 16,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (_adding)
              SizedBox(
                width: 220,
                child: GroveField(
                  key: const ValueKey('persona-new-skill'),
                  controller: _text,
                  placeholder: 'Skill name',
                  label: 'New skill',
                  maxLength: PersonaRules.maxNameLength,
                  boxed: true,
                  autofocus: true,
                  onSubmitted: (v) {
                    _store.addSkill(v);
                    _close();
                  },
                  onEscape: _close,
                ),
              )
            else
              TextTap(
                key: const ValueKey('persona-add-skill'),
                label: 'Add skill',
                onTap: () => _edit(() => _adding = true, ''),
              ),
            if (hidden > 0) ...[
              Text(
                PersonaView.hiddenLine(hidden),
                style: theme.body(12).copyWith(color: theme.muted),
              ),
              TextTap(
                key: const ValueKey('persona-show-hidden'),
                label: _showHidden ? 'Put away' : 'Show',
                onTap: () => setState(() => _showHidden = !_showHidden),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _skillCard(BuildContext context, SkillItem skill, int points) {
    final theme = GroveTheme.of(context);
    final level = SkillLevel.of(points);
    final key = 'persona-skill-${skill.id}';
    final renaming = _renaming == skill.id;
    return Semantics(
      container: true,
      label: '${skill.name}, level ${level.level}',
      value: '${level.into} of ${level.needed} points',
      child: Opacity(
        opacity: skill.hidden ? 0.5 : 1,
        child: DecoratedBox(
          key: ValueKey(key),
          decoration: BoxDecoration(
            color: theme.surface2,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: theme.line),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 6, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 8,
              children: [
                Row(
                  spacing: 8,
                  children: [
                    Expanded(
                      child: renaming
                          ? GroveField(
                              key: ValueKey('$key-name-field'),
                              controller: _text,
                              placeholder: skill.name,
                              label: 'Skill name',
                              maxLength: PersonaRules.maxNameLength,
                              boxed: true,
                              autofocus: true,
                              onSubmitted: (v) {
                                _store.renameSkill(skill.id, v);
                                _close();
                              },
                              onEscape: _close,
                            )
                          : Text(
                              skill.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme
                                  .body(14, weight: FontWeight.w600)
                                  .copyWith(color: theme.ink),
                            ),
                    ),
                    Text(
                      'Level ${level.level}',
                      style: theme
                          .body(12, weight: FontWeight.w600)
                          .copyWith(color: theme.accent),
                    ),
                    Builder(
                      builder: (context) => IconTap(
                        key: ValueKey('$key-menu'),
                        icon: Icons.more_horiz,
                        label: 'More for ${skill.name}',
                        onTap: () => _menu(context, skill),
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: SkillBar(name: key, fill: level.fill),
                ),
                Text(
                  '${level.into} / ${level.needed}',
                  style: theme.body(11).copyWith(color: theme.muted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _menu(BuildContext context, SkillItem skill) {
    final box = context.findRenderObject()! as RenderBox;
    showGroveMenu(context, box.localToGlobal(Offset(0, box.size.height)), [
      MenuLine('Rename…', () => _edit(() => _renaming = skill.id, skill.name)),
      MenuLine(
        skill.hidden ? 'Show again' : 'Hide',
        () => _store.setSkillHidden(skill.id, hidden: !skill.hidden),
      ),
    ]);
  }

  // The newest points

  Widget _recent(BuildContext context) {
    final theme = GroveTheme.of(context);
    final lines = _store.recentEarnings(limit: PersonaView.recentCount);
    final names = {for (final s in _store.skills) s.id: s.name};
    final today = _store.clockToday;
    final small = theme.body(12).copyWith(color: theme.muted);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 10,
      children: [
        const ThemedHeading('Newest points', 16),
        if (lines.isEmpty)
          Text('No points yet. Finish a task with a reward.', style: small)
        else
          Panel(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final e in lines)
                    Padding(
                      key: ValueKey('persona-earning-${e.id}'),
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        spacing: 10,
                        children: [
                          SizedBox(
                            width: 120,
                            child: Text(
                              '+${e.points} ${names[e.skillId] ?? ''}'.trim(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme
                                  .body(13, weight: FontWeight.w600)
                                  .copyWith(color: theme.accent),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              e.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.body(13).copyWith(color: theme.ink),
                            ),
                          ),
                          ?_day(e, today, small),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget? _day(EarningItem e, DayKey today, TextStyle style) {
    final day = e.earnedAt.length < 10
        ? null
        : DayKey.parse(e.earnedAt.substring(0, 10));
    return day == null
        ? null
        : Text(PersonaView.dayLabel(day, today), style: style);
  }
}
