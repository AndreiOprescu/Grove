import 'package:flutter_test/flutter_test.dart';
import 'package:grove/state/state.dart';

import '../state/support.dart' show makeStore;
import 'support.dart';

void main() {
  test(
    'work in the app on two devices, offline, syncs to the same data',
    () async {
      final remote = MemoryRemote();
      final a = Device(remote), b = Device(remote);
      final storeA = makeStore(repos: a.repos);
      final storeB = makeStore(repos: b.repos);

      final milk = storeA.quickAdd('Buy milk #home')!;
      final note = storeA.newNote(title: 'Trip', body: 'Pack the tent');
      await settle([a, b]);
      expect(storeB.repos.tasks.get(milk.id)!.title, 'Buy milk');
      expect(storeB.repos.notes.get(note.id)!.body, 'Pack the tent');

      // Both go offline and work.
      a.later();
      storeA.addSubtask(to: milk.id, title: 'Oat, not cow');
      storeA.quickAdd('Call mum tomorrow 6pm for 20m');
      b.later();
      storeB.toggleDone(taskId: milk.id);
      storeB.renameNote(note.id, to: 'Camping trip');
      storeB.quickAdd('Water the plants #home');

      await settle([a, b]);

      expectSame([a, b]);
      expect(a.repos.tasks.get(milk.id)!.status, TaskStatus.done);
      expect(a.repos.tasks.subtasks(milk.id).single.title, 'Oat, not cow');
      expect(a.repos.notes.get(note.id)!.title, 'Camping trip');
      expect(a.repos.tags.all().length, 1);
      // The milk task is done now, so only one open task has the tag.
      expect(a.repos.tags.tagsForTask(milk.id), ['home']);
      expect(a.repos.tasks.withTag('home').single.title, 'Water the plants');
      expect(b.repos.events.all().single.title, 'Call mum');
    },
  );

  test('an undo is a new change and travels too', () async {
    final remote = MemoryRemote();
    final a = Device(remote), b = Device(remote);
    final storeA = makeStore(repos: a.repos);
    final t = storeA.quickAdd('Buy milk')!;
    await settle([a, b]);

    a.later();
    storeA.deleteTask(t.id);
    await settle([a, b]);
    expect(b.repos.tasks.all(), isEmpty);

    a.later();
    storeA.undo();
    await settle([a, b]);
    expect(b.repos.tasks.get(t.id)!.title, 'Buy milk');
    expectSame([a, b]);
  });
}
