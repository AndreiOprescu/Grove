// Port of Tests/GroveTests/TaskDescriptionTests.swift.
// The block layout tests (`PlannerLayoutRules`) stay with the planner view
// (Track B).
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

PlannerBlock blockOf(AppStore s, String taskId) => s
    .blocks(DayRange.single(DayKey.today()))
    .firstWhere((b) => b.taskId == taskId);

void main() {
  test('summary text is one short line', () {
    expect(SummaryText.clean('  hello  '), 'hello');
    expect(SummaryText.clean('one\ntwo\r\nthree'), 'one two three');
    expect(SummaryText.clean('a' * 500).length, SummaryText.maxLength);
    expect(SummaryText.clean('   '), '');
  });

  test('saving a summary stores it, and typing is one undo step', () {
    final s = makeStore();
    final a = s.quickAdd('A')!;
    s.setSummary(a.id, 'f');
    s.setSummary(a.id, 'fl');
    s.setSummary(a.id, 'flights');
    expect(s.task(a.id)?.summary, 'flights');
    s.undo();
    expect(s.task(a.id)?.summary, '');
    s.redo();
    expect(s.task(a.id)?.summary, 'flights');
  });

  test('saving the same summary changes nothing', () {
    final s = makeStore();
    final a = s.quickAdd('A')!;
    s.setSummary(a.id, 'x');
    final before = s.undoName;
    s.setSummary(a.id, ' x ');
    expect(s.undoName, before);
    s.setSummary(a.id, '');
    expect(s.task(a.id)?.summary, '');
  });

  test('a block carries the summary of its task', () {
    final s = makeStore();
    final a = s.quickAdd('Plan trip today 10am for 1h')!;
    s.setSummary(a.id, 'Flights and hotel');
    final block = blockOf(s, a.id);
    expect(block.summary, 'Flights and hotel');
    expect(block.title, 'Plan trip');
  });

  test('a click on a task block opens its panel', () {
    final s = makeStore();
    final a = s.quickAdd('Plan trip today 10am for 1h')!;
    final block = blockOf(s, a.id);
    expect(s.selectedTaskId, isNull);
    s.selectBlock(block, extend: false);
    expect(s.selection, {block.id});
    expect(s.selectedTaskId, a.id);
  });

  test('an extending click builds a selection and leaves the panel alone', () {
    final s = makeStore();
    final a = s.quickAdd('A today 10am for 1h')!;
    final b = s.quickAdd('B today 12pm for 1h')!;
    final ba = blockOf(s, a.id), bb = blockOf(s, b.id);
    s.selectBlock(ba, extend: false);
    s.selectBlock(bb, extend: true);
    expect(s.selection, {ba.id, bb.id});
    expect(s.selectedTaskId, a.id);
    s.selectBlock(bb, extend: true);
    expect(s.selection, {ba.id});
  });
}
