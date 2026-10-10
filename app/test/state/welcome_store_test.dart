// Port of Tests/GroveTests/WelcomeStoreTests.swift.
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

AppStore seeded({FakeNotifier? notifier}) {
  final repos = Repos(Database.inMemory());
  FirstRun.seedIfNew(repos, today: DayKey.today());
  return makeStore(
    repos: repos,
    notifier: notifier ?? FakeNotifier(status: NotifyAuthorization.notAsked),
  );
}

void main() {
  test('a store on an empty database shows no card', () {
    final s = makeStore(notifier: FakeNotifier());
    expect(s.welcomeVisible, isFalse);
  });

  test('a store on a seeded database shows the card', () {
    final s = seeded();
    expect(s.welcomeVisible, isTrue);
    expect(s.repos.tasks.all().length, 3);
  });

  test('"Got it" hides the card and keeps the tasks', () {
    final s = seeded();
    s.dismissWelcome();
    expect(s.welcomeVisible, isFalse);
    expect(s.repos.tasks.all().length, 3);
    expect(FirstRun.welcomeVisible(s.repos), isFalse);
  });

  test('"Got it" asks for notifications once', () async {
    final fake = FakeNotifier(status: NotifyAuthorization.notAsked);
    final s = seeded(notifier: fake);
    s.dismissWelcome();
    await s.welcomeAsk;
    expect(fake.asked, 1);
    expect(s.notifyStatus, NotifyAuthorization.allowed);
  });

  test('it does not ask again when the system already answered', () async {
    final fake = FakeNotifier(status: NotifyAuthorization.denied);
    final s = seeded(notifier: fake);
    s.dismissWelcome();
    await s.welcomeAsk;
    expect(fake.asked, 0);
    expect(s.notifyStatus, NotifyAuthorization.denied);
  });

  test('remove samples deletes them as one undo step', () {
    final s = seeded();
    s.removeSamples();
    expect(s.welcomeVisible, isFalse);
    expect(s.repos.tasks.all(), isEmpty);
    expect(s.undoName, 'Remove Samples');
    s.undo();
    expect(s.repos.tasks.all().length, 3);
  });

  test('remove samples keeps the tasks the person added', () {
    final s = seeded();
    s.repos.tasks.save(
      TaskItem(title: 'Mine', bucket: TaskBucket.day, planDate: DayKey.today()),
    );
    s.removeSamples();
    expect(titles(s.repos.tasks.all()), ['Mine']);
  });

  test('remove samples also asks for notifications', () async {
    final fake = FakeNotifier(status: NotifyAuthorization.notAsked);
    final s = seeded(notifier: fake);
    s.removeSamples();
    await s.welcomeAsk;
    expect(fake.asked, 1);
  });

  test('a sample the owner already deleted does not break remove', () {
    final s = seeded();
    final first = FirstRun.sampleTaskIds(s.repos).first;
    s.deleteTask(first);
    s.removeSamples();
    expect(s.repos.tasks.all(), isEmpty);
  });
}
