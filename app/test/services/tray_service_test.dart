import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  late AppStore store;
  late FakeTray tray;
  late int minute;
  late List<String> log;

  TrayService service() {
    final s = TrayService(
      store: store,
      gateway: tray,
      showWindow: () => log.add('show'),
      quit: () => log.add('quit'),
      minute: () => minute,
    );
    addTearDown(s.dispose);
    return s;
  }

  void addBlock(String id, String title, int start, int end) =>
      store.repos.events.save(
        EventItem(
          id: id,
          title: title,
          start: WallTime(day: DayKey.today(), minute: start),
          end: WallTime(day: DayKey.today(), minute: end),
          color: 'accent3',
        ),
      );

  setUp(() {
    store = makeStore();
    tray = FakeTray();
    minute = 9 * 60 + 30;
    log = [];
  });

  test('the menu shows now, next, the growth and the commands', () {
    addBlock('a', 'Standup', 9 * 60, 10 * 60);
    addBlock('b', 'Write report', 10 * 60, 11 * 60);
    expect(service().start(), isTrue);

    expect(tray.visible, isTrue);
    expect(tray.lines, [
      '(Now: Standup)',
      '(Next: Write report in 30 min)',
      '(Nothing planned today)',
      '---',
      'Open Grove',
      'New task',
      '---',
      'Quit Grove',
    ]);
    expect(tray.tooltip, 'Grove · Now: Standup');
  });

  test('an empty day', () {
    service().start();
    expect(tray.lines.take(3), [
      '(Nothing planned right now)',
      '(Nothing else today)',
      '(Nothing planned today)',
    ]);
    expect(tray.tooltip, 'Grove · Nothing planned right now');
  });

  test('a system with no tray: the service does nothing', () {
    tray.supported = false;
    final s = service();
    expect(s.start(), isFalse);
    store.quickAdd('Buy milk today');
    s.refresh();
    expect(tray.menus, 0);
  });

  test('"Open Grove" shows the window', () {
    service().start();
    tray.tap('Open Grove');
    expect(log, ['show']);
  });

  test('a click on the icon shows the window', () {
    service().start();
    tray.clickIcon();
    expect(log, ['show']);
  });

  test('"New task" shows the window and asks for the quick-add box', () {
    service().start();
    store.screen = Screen.notes;
    final before = store.quickAddRequest;
    tray.tap('New task');
    expect(log, ['show']);
    expect(store.quickAddRequest, before + 1);
    expect(store.screen, Screen.today);
  });

  test('"Quit Grove" quits', () {
    service().start();
    tray.tap('Quit Grove');
    expect(log, ['quit']);
  });

  testWidgets('a change in the store shows in the menu after a moment', (
    tester,
  ) async {
    store = makeStore();
    final s = service()..start();
    expect(tray.lines[2], '(Nothing planned today)');

    final task = store.quickAdd('Buy milk today')!;
    store.quickAdd('Call mum today');
    // Many changes, one new menu.
    final before = tray.menus;
    await tester.pump(TrayService.settle);
    expect(tray.menus, before + 1);
    expect(tray.lines[2], '(0% of today grown)');

    store.toggleDone(taskId: task.id);
    await tester.pump(TrayService.settle);
    expect(tray.lines[2], '(50% of today grown)');
    s.dispose();
  });

  testWidgets('time moves the lines, and the same lines make no new menu', (
    tester,
  ) async {
    store = makeStore();
    addBlock('a', 'Standup', 9 * 60, 10 * 60);
    final s = service()..start();
    expect(tray.menus, 1);

    await tester.pump(const Duration(seconds: 31));
    expect(tray.menus, 1);

    minute = 10 * 60;
    await tester.pump(const Duration(seconds: 30));
    expect(tray.menus, 2);
    expect(tray.lines.first, '(Nothing planned right now)');

    // After dispose, nothing moves.
    s.dispose();
    expect(tray.visible, isFalse);
    minute = 9 * 60;
    store.quickAdd('Buy milk today');
    await tester.pump(const Duration(minutes: 2));
    expect(tray.menus, 2);
  });

  test('a long title is cut in the tooltip', () {
    addBlock('a', 'A' * 300, 9 * 60, 10 * 60);
    service().start();
    expect(tray.tooltip.length, TrayService.tooltipLimit);
    expect(tray.tooltip, endsWith('…'));
  });
}
