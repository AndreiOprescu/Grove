// The font files in the app (docs/questions.md, Q-1 and Q-2): the same
// letters on Android, iOS, macOS and Windows.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/ui/theme/fonts.dart';
import 'package:grove/ui/theme/grove_theme.dart';
import 'package:grove/ui/theme/theme_spec.dart';

String _tag(ByteData data, int at) =>
    String.fromCharCodes([for (var k = 0; k < 4; k++) data.getUint8(at + k)]);

/// The design axes of a TrueType file (its `fvar` table). A font with one
/// fixed shape has none.
Set<String> axesOf(ByteData data) {
  final tables = data.getUint16(4);
  for (var i = 0; i < tables; i++) {
    final record = 12 + i * 16;
    if (_tag(data, record) != 'fvar') continue;
    final table = data.getUint32(record + 8);
    final first = table + data.getUint16(table + 4);
    final count = data.getUint16(table + 8);
    final size = data.getUint16(table + 10);
    return {for (var a = 0; a < count; a++) _tag(data, first + a * size)};
  }
  return {};
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// family → its files, as the app bundle lists them (from pubspec.yaml).
  late Map<String, List<Map<String, Object?>>> bundled;

  setUpAll(() async {
    final text = await rootBundle.loadString('FontManifest.json');
    final families = (jsonDecode(text) as List<Object?>)
        .cast<Map<String, Object?>>();
    bundled = {
      for (final entry in families)
        entry['family']! as String: (entry['fonts']! as List<Object?>)
            .cast<Map<String, Object?>>(),
    };
  });

  group('font files', () {
    test('the app has the 7 approved families', () {
      expect(GroveFonts.all, {
        'Newsreader',
        'Nunito',
        'Inter',
        'Archivo',
        'JetBrains Mono',
        'Libre Baskerville',
        'Courier Prime',
      });
      for (final family in GroveFonts.all) {
        expect(bundled.keys, contains(family));
      }
    });

    test('every font of every theme is a file in the app', () {
      for (final id in ThemeId.values) {
        for (final brightness in Brightness.values) {
          final t = GroveTheme.make(id, brightness);
          for (final style in [t.heading(20), t.body(13), t.number(12)]) {
            expect(GroveFonts.all, contains(style.fontFamily), reason: '$id');
          }
        }
      }
    });

    test('each file is a real font with the axes the theme uses', () async {
      const axes = {
        'Newsreader': {'opsz', 'wght'},
        'Nunito': {'wght'},
        'Inter': {'opsz', 'wght'},
        'Archivo': {'wdth', 'wght'},
        'JetBrains Mono': {'wght'},
        'Libre Baskerville': {'wght'},
        'Courier Prime': <String>{},
      };
      expect(axes.keys.toSet(), GroveFonts.all);
      for (final family in GroveFonts.all) {
        for (final font in bundled[family]!) {
          final data = await rootBundle.load(font['asset']! as String);
          // 0x00010000 starts a TrueType file.
          expect(data.getUint32(0), 0x00010000, reason: family);
          expect(data.lengthInBytes, greaterThan(50000), reason: family);
          expect(axesOf(data), axes[family], reason: family);
        }
      }
    });

    test('Vintage has an italic title file and two weights of text', () {
      expect(bundled['Libre Baskerville'], hasLength(1));
      expect(bundled['Libre Baskerville']!.single['style'], 'italic');
      expect(bundled['Courier Prime']!.map((f) => f['weight'] ?? 400), [
        400,
        700,
      ]);
    });
  });

  group('font licences', () {
    test('each family has the text of its licence', () async {
      final entries = await fontLicenses().toList();
      expect(entries, hasLength(GroveFonts.all.length));
      expect(entries.expand((e) => e.packages).toSet(), GroveFonts.all);
      for (final entry in entries) {
        final text = entry.paragraphs.map((p) => p.text).join('\n');
        expect(text, contains('Copyright'), reason: '${entry.packages}');
        expect(text, contains('SIL OPEN FONT LICENSE Version 1.1'));
      }
    });

    test('the licence page of the app lists them, one time each', () async {
      registerFontLicenses();
      registerFontLicenses();
      final entries = await LicenseRegistry.licenses.toList();
      for (final family in GroveFonts.all) {
        expect(
          entries.where((e) => e.packages.contains(family)),
          hasLength(1),
          reason: family,
        );
      }
    });
  });
}
