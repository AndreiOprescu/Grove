import 'package:flutter_test/flutter_test.dart';
import 'package:grove/core/parsing/note_parser.dart';

// Port of Tests/GroveCoreTests/NoteParserTests.swift.
void main() {
  group('tags', () {
    test('finds tags in text', () {
      expect(NoteParser.tags('Plan #work and #Home-2 today'), [
        'work',
        'Home-2',
      ]);
    });

    test('a heading is not a tag', () {
      expect(NoteParser.tags('# Title\n## Plan\n###Odd'), isEmpty);
    });

    test('numbers and links are not tags', () {
      expect(
        NoteParser.tags('issue #123, see http://a.b/c#top, mail a#b'),
        isEmpty,
      );
    });

    test('code, mentions and images are skipped', () {
      const text =
          '`#code` and [[Task #1|ID1]] and ![a #pic](grove-image:X) and #real';
      expect(NoteParser.tags(text), ['real']);
    });

    test('same tag in any case counts once', () {
      expect(NoteParser.tags('#Work #work #WORK #play'), ['Work', 'play']);
    });

    test('a tag at the start of a line', () {
      expect(NoteParser.tags('#idea\nmore'), ['idea']);
    });

    test('letters outside ASCII count as word letters', () {
      expect(NoteParser.tags('#café and é#nope'), ['café']);
    });
  });

  group('check boxes', () {
    test('finds check box lines', () {
      const body =
          '## Plan\n- [ ] Call Sam\n- [x] Send file\n  - [X] Nested\ntext\n- [ ] ';
      final boxes = NoteParser.checkboxes(body);
      expect(boxes.map((b) => b.line), [1, 2, 3]);
      expect(boxes.map((b) => b.text), ['Call Sam', 'Send file', 'Nested']);
      expect(boxes.map((b) => b.checked), [false, true, true]);
      expect(boxes.every((b) => b.taskId == null), isTrue);
    });

    test('reads the hidden task marker', () {
      const body = '- [ ] Call Sam ⟦t:ABC-123⟧\n- [x] Done thing ⟦t:Z9⟧';
      final boxes = NoteParser.checkboxes(body);
      expect(boxes.map((b) => b.taskId), ['ABC-123', 'Z9']);
      // The marker is not part of the text.
      expect(boxes.map((b) => b.text), ['Call Sam', 'Done thing']);
    });

    test('adding a marker to a line', () {
      const body = 'a\n- [ ] Call Sam\nb';
      final out = NoteParser.addingMarker(body, line: 1, taskId: 'T1');
      expect(out, 'a\n- [ ] Call Sam ⟦t:T1⟧\nb');
      // A line that has a marker keeps it.
      expect(NoteParser.addingMarker(out, line: 1, taskId: 'T2'), out);
    });

    test('ticking a line', () {
      const body = '- [ ] One ⟦t:A⟧\n- [x] Two';
      expect(
        NoteParser.settingChecked(body, line: 0, checked: true),
        '- [x] One ⟦t:A⟧\n- [x] Two',
      );
      expect(
        NoteParser.settingChecked(body, line: 1, checked: false),
        '- [ ] One ⟦t:A⟧\n- [ ] Two',
      );
      // A line that is not a check box is left alone.
      expect(
        NoteParser.settingChecked('plain', line: 0, checked: true),
        'plain',
      );
    });

    test('the marker is hidden from search and titles', () {
      expect(
        NoteParser.withoutMarkers('- [ ] Call ⟦t:A1⟧ now'),
        '- [ ] Call now',
      );
    });
  });
}
