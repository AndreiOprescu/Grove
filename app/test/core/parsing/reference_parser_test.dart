import 'package:flutter_test/flutter_test.dart';
import 'package:grove/core/parsing/reference_parser.dart';

// Port of Tests/GroveCoreTests/ReferenceParserTests.swift.
void main() {
  const idA = '3F2A9B1C-0D4E-4F5A-8B6C-7D8E9F0A1B2C';
  const idB = 'A1B2C3D4-E5F6-4A7B-8C9D-0E1F2A3B4C5D';

  List<String> parsed(String text) =>
      ReferenceParser.mentions(text)
          .map((m) => '${m.title}|${m.id ?? '-'}')
          .toList();

  group('mentions', () {
    test('plain title mention', () {
      expect(parsed('see [[Buy milk]] today'), ['Buy milk|-']);
    });

    test('mention with id', () {
      expect(parsed('see [[Buy milk|$idA]]'), ['Buy milk|$idA']);
    });

    test('several mentions keep their order', () {
      expect(parsed('[[One]] and [[Two|$idA]] and [[One]]'), [
        'One|-',
        'Two|$idA',
        'One|-',
      ]);
    });

    test('spaces around the title are trimmed', () {
      expect(parsed('[[  Buy milk  ]]'), ['Buy milk|-']);
    });

    test('empty mention is ignored', () {
      expect(parsed('[[]] and [[   ]] and [[|$idA]]'), isEmpty);
    });

    test('mention cannot span lines', () {
      expect(parsed('[[Buy\nmilk]]'), isEmpty);
    });

    test('inner mention wins when nested', () {
      expect(parsed('[[a [[b]] c]]'), ['b|-']);
    });

    test('a bar without a real id stays in the title', () {
      expect(parsed('[[Yes|No]]'), ['Yes|No|-']);
      expect(parsed('[[Tea|]]'), ['Tea||-']);
    });

    test('links and images are not mentions', () {
      expect(
        parsed('[site](https://example.com) ![pic](grove-image:$idA) [x]'),
        isEmpty,
      );
    });

    test('range covers the whole mention', () {
      const text = 'a [[Buy milk|$idA]] b';
      final m = ReferenceParser.mentions(text);
      expect(m.length, 1);
      expect(text.substring(m.first.start, m.first.end), '[[Buy milk|$idA]]');
    });
  });

  group('writing mentions', () {
    test('mention text', () {
      expect(
        ReferenceParser.mention(title: 'Buy milk', id: idA),
        '[[Buy milk|$idA]]',
      );
      expect(ReferenceParser.mention(title: 'Buy milk'), '[[Buy milk]]');
    });

    test('mention text cleans titles that would break the syntax', () {
      expect(ReferenceParser.mention(title: 'a [b] | c\nd'), '[[a b c d]]');
      expect(
        ReferenceParser.mention(title: ' [] ', id: idA),
        '[[Untitled|$idA]]',
      );
    });

    test('rewriting changes only the matching id', () {
      const text = 'x [[Old|$idA]] y [[Other|$idB]] z [[Old]]';
      final out = ReferenceParser.rewriting(text, id: idA, title: 'Fresh');
      expect(out, 'x [[Fresh|$idA]] y [[Other|$idB]] z [[Old]]');
    });

    test('rewriting with no match returns the same text', () {
      const text = 'nothing [[here]]';
      expect(ReferenceParser.rewriting(text, id: idA, title: 'X'), text);
    });
  });

  group('images', () {
    test('image ids in order without duplicates', () {
      const text =
          '![a](grove-image:$idA) text ![](grove-image:$idB) ![again](grove-image:$idA)';
      expect(ReferenceParser.imageIds(text), [idA, idB]);
    });

    test('other image links are not attachments', () {
      expect(
        ReferenceParser.imageIds(
          '![a](https://example.com/a.png) ![b](grove-image:nope)',
        ),
        isEmpty,
      );
    });

    test('image markup', () {
      expect(
        ReferenceParser.imageMarkup(id: idA, alt: 'My shot'),
        '![My shot](grove-image:$idA)',
      );
      expect(
        ReferenceParser.imageMarkup(id: idA, alt: 'a]\nb'),
        '![a b](grove-image:$idA)',
      );
    });
  });

  group('search text', () {
    test('search text drops ids and keeps words', () {
      const body =
          'call [[Dentist|$idA]] and [[Plain]] ![front door](grove-image:$idB) done ⟦t:$idA⟧';
      expect(
        ReferenceParser.searchText(body),
        'call Dentist and Plain front door done',
      );
    });
  });
}
