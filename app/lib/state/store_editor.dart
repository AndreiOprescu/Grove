part of 'app_store.dart';

/// What the rich text editor reads and writes in the store.
extension AppStoreEditor on AppStore {
  /// [excluding] is the item whose text is being edited. It is left out of the
  /// `[[` list. [noteId] is set for the text of a note. Only then can the
  /// editor make tasks from words.
  EditorServices editorServices({ItemRef? excluding, String? noteId}) =>
      EditorServices(
        suggest: (query) => mentionSuggestions(query, excluding: excluding),
        isLive: (id) => _try(() => repos.refs.resolveTitle('', id: id)) != null,
        title: (id) => _try(() => repos.refs.resolveTitle('', id: id))?.title,
        open: (id, title) => openMention(id: id, title: title),
        storeImage: (image) => _try(
          () => repos.attachments.add(
            mime: image.mime,
            data: image.data,
            width: image.width,
            height: image.height,
          ),
        )?.id,
        loadImage: image,
        notify: showToast,
        makeTask: noteId == null
            ? null
            : (words) => makeTask(from: words, inNote: noteId),
        addToPlanner: noteId == null
            ? null
            : (line) => addToPlanner(line: line, inNote: noteId),
      );

  List<MentionSuggestion> mentionSuggestions(
    String query, {
    ItemRef? excluding,
  }) {
    const wanted = 8;
    final trimmed = trimSpaces(query);
    final out = <MentionSuggestion>[];
    if (trimmed.isEmpty) {
      // Nothing typed yet: today's open tasks first, then the inbox.
      final tasks = [
        ...openTasks(TaskPlacement.day(selectedDay)),
        ...openTasks(TaskPlacement.inbox),
      ];
      for (final t in tasks) {
        final ref = ItemRef(ItemType.task, t.id);
        if (ref == excluding) continue;
        out.add(MentionSuggestion(ref: ref, title: t.title, kind: 'Task'));
      }
    } else {
      final hits =
          _try(() => repos.search.search(trimmed, limit: wanted + 1)) ??
          const <SearchHit>[];
      for (final hit in hits) {
        if (hit.ref == excluding) continue;
        out.add(
          MentionSuggestion(
            ref: hit.ref,
            title: hit.title,
            kind: _kindName(hit.ref.type),
          ),
        );
      }
    }
    return out.take(wanted).toList();
  }

  String _kindName(ItemType type) => switch (type) {
    ItemType.task => 'Task',
    ItemType.note => 'Note',
    ItemType.event => 'Event',
  };

  /// Opens the item a mention points at.
  void openMention({required String? id, required String title}) {
    final target = _try(() => repos.refs.resolveTitle(title, id: id));
    if (target == null) {
      showToast('That item is gone.');
      return;
    }
    open(target.ref);
  }

  void open(ItemRef ref) {
    switch (ref.type) {
      case ItemType.task:
        final t = task(ref.id);
        if (t == null) return;
        selectedTaskId = t.id;
        final day = t.planDate;
        if (day != null) {
          showDay(day);
        } else {
          // The task panel shows there, in place of the note.
          screen = Screen.today;
        }
      case ItemType.event:
        final e = event(ref.id);
        if (e == null) return;
        selection = {e.id};
        showDay(e.start.day);
      case ItemType.note:
        openNote(ref.id);
    }
  }

  /// The bytes of a stored image. Null when it is gone.
  Uint8List? image(String id) => _try(() => repos.attachments.get(id))?.data;
}
