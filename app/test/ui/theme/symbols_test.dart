// The engine names pictures with the SF Symbol names of the Mac app. The
// screens map each name to an icon. See docs/tracks.md, "Requests to Track B".
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/core/parsing/palette_rules.dart';
import 'package:grove/state/state.dart';
import 'package:grove/ui/shell/left_dock.dart';
import 'package:grove/ui/theme/symbols.dart';

void main() {
  group('symbol names', () {
    test('the three left panels have their icons', () {
      expect(symbolIcon('note.text'), Icons.sticky_note_2_outlined);
      expect(symbolIcon('checklist'), Icons.checklist);
      expect(symbolIcon('target'), Icons.track_changes);
      for (final pane in LeftPane.values) {
        expect(paneIcon(pane), symbolIcon(pane.icon));
      }
    });

    test('every name the engine uses has an icon', () {
      final names = {
        for (final pane in LeftPane.values) pane.icon,
        for (final mood in Mood.values) mood.symbol,
        for (final command in PaletteRules.commands) command.symbol,
        // the rows the palette makes from tasks, events and notes
        'calendar',
        'note.text',
        'circle',
        'checkmark.circle.fill',
      };
      for (final name in names) {
        expect(hasSymbolIcon(name), isTrue, reason: name);
        expect(symbolIcon(name), isNot(unknownSymbolIcon), reason: name);
      }
    });

    test('a name with no icon gives the stand-in, not an error', () {
      expect(hasSymbolIcon('no.such.symbol'), isFalse);
      expect(symbolIcon('no.such.symbol'), unknownSymbolIcon);
    });

    test('names that differ have icons that differ in one list', () {
      final moods = Mood.values.map((m) => symbolIcon(m.symbol)).toSet();
      expect(moods, hasLength(Mood.values.length));
      final panes = LeftPane.values.map((p) => symbolIcon(p.icon)).toSet();
      expect(panes, hasLength(LeftPane.values.length));
    });
  });
}
