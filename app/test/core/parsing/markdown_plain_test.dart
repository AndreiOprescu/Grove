import 'package:flutter_test/flutter_test.dart';
import 'package:grove/core/parsing/markdown_plain.dart';

void main() {
  const id = '11111111-2222-3333-4444-555555555555';
  String plain(String s) => MarkdownPlain.text(s);

  test('inline marks go, the words stay', () {
    expect(plain('a **b** *c* `d` e'), 'a b c d e');
    expect(plain('***x***'), 'x');
    expect(
      plain('~~gone~~ <u>under</u> ==hi== =={green}go=='),
      'gone under hi go',
    );
    expect(plain('**a ~~b <u>c</u>~~**'), 'a b c');
  });

  test('marks that make no format stay', () {
    expect(plain('a == b'), 'a == b');
    expect(plain('2 * 3 * 4'), '2 * 3 * 4');
    expect(plain('**unclosed'), '**unclosed');
  });

  test('empty pairs go', () {
    expect(plain('a **** b ~~~~ <u></u> ===='), 'a  b   ');
  });

  test('headings and quotes lose their marks, lists keep theirs', () {
    expect(
      plain('## Title\n> wise\n- one\n- [ ] two'),
      'Title\nwise\n- one\n- [ ] two',
    );
  });

  test('a link keeps its words and a bare address stays', () {
    expect(plain('see [the **docs**](https://a.b/c) now'), 'see the docs now');
    expect(plain('go to https://a.b/c'), 'go to https://a.b/c');
  });

  test('mentions, images and task marks read as searchText did', () {
    const body =
        'call [[Dentist|$id]] and [[Plain]] ![front door](grove-image:$id) done ⟦t:$id⟧';
    expect(plain(body), 'call Dentist and Plain front door done');
  });

  test('a divider line becomes empty', () {
    expect(plain('a\n---\nb'), 'a\n\nb');
  });

  test('tags and lists by name are kept', () {
    expect(plain('**Buy** milk #home /groceries'), 'Buy milk #home /groceries');
  });

  test('code keeps what is inside it', () {
    expect(plain('`**x**`'), '**x**');
  });
}
