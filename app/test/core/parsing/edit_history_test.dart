import 'package:flutter_test/flutter_test.dart';
import 'package:grove/core/parsing/edit_history.dart';

EditSnapshot snap(String text) =>
    EditSnapshot(text, Utf16Range(text.length, 0));

void main() {
  final t0 = DateTime(2026, 10, 15, 9);
  DateTime at(int ms) => t0.add(Duration(milliseconds: ms));

  test('undo goes back, redo goes forward', () {
    final h = EditHistory();
    expect(h.canUndo, isFalse);
    h.record(snap('a'), snap('ab'), at: at(0));
    h.record(snap('ab'), snap('ab!'), at: at(5000));
    expect(h.undo()?.text, 'ab');
    expect(h.undo()?.text, 'a');
    expect(h.undo(), isNull);
    expect(h.canRedo, isTrue);
    expect(h.redo()?.text, 'ab');
    expect(h.redo()?.text, 'ab!');
    expect(h.redo(), isNull);
  });

  test('quick typing is one step', () {
    final h = EditHistory();
    h.record(snap(''), snap('a'), typing: true, at: at(0));
    h.record(snap('a'), snap('ab'), typing: true, at: at(300));
    h.record(snap('ab'), snap('abc'), typing: true, at: at(600));
    expect(h.undo()?.text, '');
    expect(h.canUndo, isFalse);
  });

  test('a pause, a format or a break starts a new step', () {
    final h = EditHistory();
    h.record(snap(''), snap('a'), typing: true, at: at(0));
    h.record(snap('a'), snap('ab'), typing: true, at: at(5000));
    h.record(snap('ab'), snap('**ab**'), at: at(5100));
    h.record(snap('**ab**'), snap('**ab**c'), typing: true, at: at(5200));
    h.breakGroup();
    h.record(snap('**ab**c'), snap('**ab**cd'), typing: true, at: at(5300));
    expect(h.undo()?.text, '**ab**c');
    expect(h.undo()?.text, '**ab**');
    expect(h.undo()?.text, 'ab');
    expect(h.undo()?.text, 'a');
    expect(h.undo()?.text, '');
  });

  test('a new change clears redo', () {
    final h = EditHistory();
    h.record(snap('a'), snap('ab'), at: at(0));
    h.undo();
    h.record(snap('a'), snap('ax'), at: at(10));
    expect(h.canRedo, isFalse);
    expect(h.undo()?.text, 'a');
  });

  test('the selection comes back too', () {
    final h = EditHistory();
    h.record(
      const EditSnapshot('abc', Utf16Range(1, 1)),
      const EditSnapshot('ac', Utf16Range(1, 0)),
      at: at(0),
    );
    expect(h.undo()?.selection, const Utf16Range(1, 1));
    expect(h.redo()?.selection, const Utf16Range(1, 0));
  });

  test('clear forgets everything and the limit drops the oldest', () {
    final h = EditHistory(limit: 2);
    h.record(snap('a'), snap('b'), at: at(0));
    h.record(snap('b'), snap('c'), at: at(5000));
    h.record(snap('c'), snap('d'), at: at(10000));
    expect(h.undo()?.text, 'c');
    expect(h.undo()?.text, 'b');
    expect(h.undo(), isNull);
    h.clear();
    expect(h.canUndo || h.canRedo, isFalse);
  });

  test('a change that only ends the last step changes that step', () {
    final h = EditHistory();
    h.record(snap('ab'), snap('ab****'), typing: true, at: at(0));
    h.record(snap('ab****'), snap('ab**x**'), typing: true, at: at(100));
    h.amendLast(snap('ab**x**'), snap('ab**xy**'));
    expect(h.undo()?.text, 'ab');
    expect(h.canUndo, isFalse);
  });

  test('a step that ends where it began is dropped', () {
    final h = EditHistory();
    h.record(snap('a'), snap('ab'), at: at(0));
    h.record(snap('ab'), snap('ab****'), typing: true, at: at(5000));
    h.amendLast(snap('ab****'), snap('ab'));
    expect(h.undo()?.text, 'a');
    expect(h.canUndo, isFalse);
  });

  test('a change that does not follow the last step is a new step', () {
    final h = EditHistory();
    h.record(snap('a'), snap('ab'), at: at(0));
    h.amendLast(snap('x'), snap('xy'));
    expect(h.undo()?.text, 'x');
    expect(h.undo()?.text, 'a');
  });

  test('the next undo and redo can be read without taking them', () {
    final h = EditHistory();
    expect((h.nextUndo, h.nextRedo), (null, null));
    h.record(snap('a'), snap('ab'), at: at(0));
    expect(h.nextUndo?.text, 'a');
    h.undo();
    expect(h.nextRedo?.text, 'ab');
    expect(h.canRedo, isTrue);
  });
}
