// The small windows of "+" in a chat of the agent: pick a note or an open
// task to link (ADR 0005). The agent may read what is linked, and nothing
// else of the notes and tasks (unless the plan switch is on).
import 'package:flutter/material.dart';
import 'package:grove/state/state.dart' hide MotionRules;

import '../planner/planner_dialogs.dart';
import '../tasks/task_widgets.dart';
import '../theme/grove_theme.dart';
import '../theme/panel.dart';

/// Shows the list of notes. Gives the link of the picked one, or null.
Future<AgentLink?> pickAgentNote(BuildContext context, AppStore store) =>
    showDialog<AgentLink>(
      context: context,
      builder: (context) => AgentPicker(
        title: 'Link a note',
        empty: 'No notes.',
        items: (query) => [
          for (final n in store.notes(query: query))
            AgentLink(
              kind: AgentLinkKind.note,
              id: n.id,
              name: n.title.trim().isEmpty ? 'Untitled' : n.title,
            ),
        ],
      ),
    );

/// Shows the list of open tasks. Gives the link of the picked one, or
/// null.
Future<AgentLink?> pickAgentTask(BuildContext context, AppStore store) =>
    showDialog<AgentLink>(
      context: context,
      builder: (context) => AgentPicker(
        title: 'Link a task',
        empty: 'No open tasks.',
        items: (query) {
          final open = store.allOpenTasks();
          final words = query.trim().toLowerCase();
          return [
            for (final t in [...open.noDay, ...open.byDay])
              if (words.isEmpty || t.title.toLowerCase().contains(words))
                AgentLink(kind: AgentLinkKind.task, id: t.id, name: t.title),
          ];
        },
      ),
    );

/// A window with a search field and a list. A click on a line picks it.
class AgentPicker extends StatefulWidget {
  const AgentPicker({
    super.key,
    required this.title,
    required this.empty,
    required this.items,
  });

  final String title;

  /// The line when the list is empty.
  final String empty;

  /// The lines for the text in the search field.
  final List<AgentLink> Function(String query) items;

  /// The list shows no more lines than this.
  static const maxLines = 50;

  @override
  State<AgentPicker> createState() => _AgentPickerState();
}

class _AgentPickerState extends State<AgentPicker> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _pick(AgentLink link) => Navigator.of(context).pop(link);

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    final items = widget.items(_query.text).take(AgentPicker.maxLines);
    return PlannerSheet(
      width: 420,
      spacing: 10,
      children: [
        ThemedHeading(widget.title, 15),
        GroveField(
          key: const ValueKey('agent-pick-search'),
          controller: _query,
          placeholder: 'Search',
          boxed: true,
          autofocus: true,
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) {
            if (items.isNotEmpty) _pick(items.first);
          },
          onEscape: () => Navigator.of(context).pop(),
        ),
        if (items.isEmpty)
          Text(widget.empty, style: theme.body(13).copyWith(color: theme.muted))
        else
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final link in items)
                  _Line(
                    key: ValueKey('agent-pick-${link.id}'),
                    label: link.name,
                    onTap: () => _pick(link),
                  ),
              ],
            ),
          ),
        dialogButtons([
          DialogButton(
            key: const ValueKey('agent-pick-cancel'),
            label: 'Cancel',
            onTap: () => Navigator.of(context).pop(),
          ),
        ]),
      ],
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = GroveTheme.of(context);
    return Semantics(
      container: true,
      button: true,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.body(13).copyWith(color: theme.ink),
            ),
          ),
        ),
      ),
    );
  }
}
