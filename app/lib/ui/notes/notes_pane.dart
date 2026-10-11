// Port of Sources/Grove/Notes/NotesPane.swift: the notes in the left panel.
// A click opens a note. A drag onto the planner gives it a time.
import 'package:flutter/material.dart';
import 'package:grove/state/state.dart' hide MotionRules;

import '../planner/payload_drag.dart';
import '../tasks/task_widgets.dart';
import '../theme/grove_theme.dart';
import '../theme/panel.dart';
import '../theme/symbols.dart';
import 'day_panel.dart';
import 'notes_view.dart';

class NotesPane extends StatelessWidget {
  const NotesPane({super.key, required this.store});

  final AppStore store;

  static String count(int n) => switch (n) {
    0 => 'No notes',
    1 => '1 note',
    _ => '$n notes',
  };

  @override
  Widget build(BuildContext context) => StoreBuilder(
    store: store,
    builder: (context) {
      final theme = GroveTheme.of(context);
      final notes = store.notes();
      return Panel(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 10,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                spacing: 8,
                children: [
                  const Expanded(
                    child: ThemedHeading('Notes', 20, weight: FontWeight.w600),
                  ),
                  Text(
                    count(notes.length),
                    key: const ValueKey('notes-pane-count'),
                    style: theme.body(11).copyWith(color: theme.muted),
                  ),
                ],
              ),
              Expanded(
                child: notes.isEmpty
                    ? Align(
                        alignment: Alignment.topLeft,
                        child: Text(
                          'No notes yet.',
                          style: theme.body(12).copyWith(color: theme.muted),
                        ),
                      )
                    : ListView.separated(
                        itemCount: notes.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 4),
                        itemBuilder: (context, i) {
                          final note = notes[i];
                          final title = note.title.isEmpty
                              ? 'Untitled'
                              : note.title;
                          return PayloadDrag(
                            key: ValueKey('pane-note-${note.id}'),
                            payload: DragPayload.note(note.id),
                            label: title,
                            child: NoteTap(
                              label: title,
                              onTap: () => store.openNote(note.id),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: theme.surface2.withValues(alpha: 0.6),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 7,
                                  ),
                                  child: Row(
                                    spacing: 6,
                                    children: [
                                      Icon(
                                        symbolIcon(noteIcon(note)),
                                        size: 11,
                                        color: theme.accent,
                                      ),
                                      Expanded(
                                        child: Text(
                                          title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: theme
                                              .body(13)
                                              .copyWith(color: theme.ink),
                                        ),
                                      ),
                                      if (note.pinned)
                                        Icon(
                                          symbolIcon('pin.fill'),
                                          size: 9,
                                          color: theme.accent2,
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
              Text(
                'Drag a note onto the planner to give it a time.',
                style: theme.body(11).copyWith(color: theme.muted),
              ),
            ],
          ),
        ),
      );
    },
  );
}
