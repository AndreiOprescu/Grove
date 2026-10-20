// Port of Tests/GroveTests/EditorStoreTests.swift.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const gone = '11111111-2222-3333-4444-555555555555';

List<String> suggested(AppStore s, String query, {ItemRef? excluding}) => [
  for (final m in s.mentionSuggestions(query, excluding: excluding)) m.title,
];

void main() {
  group('the [[ list', () {
    test('an empty query lists today, then the inbox', () {
      final s = makeStore();
      s.selectedDay = DayKey.today();
      expect(s.quickAdd('Inbox thing'), isNotNull);
      final today = s.quickAdd('Plan the thing today')!;
      final all = suggested(s, '');
      expect(all.first, 'Plan the thing');
      expect(all, contains('Inbox thing'));
      expect(suggested(s, '', excluding: ItemRef(ItemType.task, today.id)), [
        'Inbox thing',
      ]);
    });

    test('the list holds at most eight rows', () {
      final s = makeStore();
      for (var i = 1; i <= 12; i++) {
        expect(s.quickAdd('Thing $i'), isNotNull);
      }
      expect(s.mentionSuggestions('').length, 8);
      expect(s.mentionSuggestions('thing').length, 8);
    });

    test('typing narrows the list by a prefix of any word', () {
      final s = makeStore();
      expect(s.quickAdd('Buy oat milk'), isNotNull);
      expect(s.quickAdd('Call mum'), isNotNull);
      expect(suggested(s, 'mil'), ['Buy oat milk']);
      expect(suggested(s, 'zzz'), isEmpty);
    });

    test('notes and events are listed with their kind', () {
      final s = makeStore();
      s.repos.notes.save(Note(title: 'Garden plan', body: 'roses'));
      final hit = s.mentionSuggestions('garden').first;
      expect(hit.kind, 'Note');
      expect(hit.ref.type, ItemType.note);
    });

    test('the item being edited is left out of the search list', () {
      final s = makeStore();
      final t = s.quickAdd('Buy milk')!;
      expect(
        suggested(s, 'buy', excluding: ItemRef(ItemType.task, t.id)),
        isEmpty,
      );
    });
  });

  group('opening a mention', () {
    test('opening a task mention selects the task and its day', () {
      final s = makeStore();
      final tomorrow = DayKey.today().adding(days: 1);
      final t = s.quickAdd('Call mum tomorrow')!;
      s.selectedDay = DayKey.today();
      s.openMention(id: t.id, title: 'Call mum');
      expect(s.selectedTaskId, t.id);
      expect(s.selectedDay, tomorrow);
    });

    test('opening a gone mention shows a toast', () {
      final s = makeStore();
      s.openMention(id: gone, title: 'Old thing');
      expect(s.toast, 'That item is gone.');
      expect(s.selectedTaskId, isNull);
    });

    test('a mention without an id is found by its title', () {
      final s = makeStore();
      final t = s.quickAdd('Buy milk')!;
      s.openMention(id: null, title: 'Buy milk');
      expect(s.selectedTaskId, t.id);
    });
  });

  group('services and images', () {
    test('services say which items are live and find their titles', () {
      final s = makeStore();
      final t = s.quickAdd('Buy milk')!;
      final svc = s.editorServices();
      expect(svc.isLive(t.id), isTrue);
      expect(svc.title(t.id), 'Buy milk');
      expect(svc.isLive(gone), isFalse);
      expect(svc.title(gone), isNull);
    });

    // The Swift store also keeps the decoded picture in a cache. The Dart
    // store gives the bytes; the screen decodes and caches them.
    test('a stored image comes back', () {
      final s = makeStore();
      final bytes = Uint8List.fromList([137, 80, 78, 71, 1, 2, 3]);
      final svc = s.editorServices();
      final id = svc.storeImage((
        mime: 'image/png',
        data: bytes,
        width: 40,
        height: 30,
      ))!;
      expect(svc.loadImage(id), bytes);
      expect(s.image(id), bytes);
      s.repos.attachments.delete(id);
      expect(svc.loadImage(id), isNull);
    });

    // The screen checks that the data is a picture before it calls the store.
    test('an image that is not there is not loaded', () {
      final s = makeStore();
      expect(s.editorServices().loadImage('nope'), isNull);
    });
  });
}
