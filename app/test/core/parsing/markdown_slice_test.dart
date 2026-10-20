import 'package:flutter_test/flutter_test.dart';
import 'package:grove/core/parsing/markdown_edit.dart';

void main() {
  const id = '11111111-2222-3333-4444-555555555555';

  /// The slice of `text` from `from` to `to`.
  String slice(String text, int from, int to) =>
      MarkdownSlice.of(text, Utf16Range(from, to - from));

  /// The slice over the first `part` of `text`, and `more` letters on.
  String over(String text, String part, [int? length]) {
    final at = text.indexOf(part);
    return slice(text, at, at + (length ?? part.length));
  }

  test('nothing selected is an empty slice', () {
    expect(slice('**a**', 2, 2), '');
  });

  test('a whole text stays as it is', () {
    const text = 'a **bold** and *it* ~~x~~ <u>u</u> ==h==';
    expect(slice(text, 0, text.length), text);
  });

  test('half of a bold word keeps bold on that half', () {
    expect(over('**bold**', 'bo'), '**bo**');
    expect(over('**bold**', 'ld'), '**ld**');
  });

  test('every format the slice cuts through closes and opens again', () {
    // From the b of the bold to the c of the italic.
    expect(over('**ab** *cd*', 'b', 6), '**b** *c*');
    expect(over('**a *b c* d**', 'b', 3), '***b c***');
    expect(over('=={green}hi there==', 'there'), '=={green}there==');
    expect(over('`some code`', 'code'), '`code`');
  });

  test('a cut link keeps its address', () {
    expect(over('[the docs](https://a.b/c)', 'docs'), '[docs](https://a.b/c)');
  });

  test('a mention and an image are taken whole', () {
    const text = 'see [[Buy milk|$id]] now';
    expect(over(text, 'Buy', 2), '[[Buy milk|$id]]');
    const pic = 'a ![door](grove-image:$id) b';
    expect(over(pic, 'door', 1), '![door](grove-image:$id)');
  });

  test('the hidden task mark is left out', () {
    const text = '- [ ] call the bank ⟦t:$id⟧\nnext';
    expect(slice(text, 0, text.length), '- [ ] call the bank\nnext');
    expect(over(text, 'call', 4), 'call');
  });

  test('a whole line keeps its line mark', () {
    expect(over('## Title\nmore', 'Title'), '## Title');
    expect(over('- [x] done', 'done'), '- [x] done');
    expect(over('> wise words', 'wise words'), '> wise words');
    expect(over('- one\n- two', 'one', 9), '- one\n- two');
  });

  test('a part of a line has no line mark', () {
    expect(over('## Title', 'Tit'), 'Tit');
    expect(over('- buy milk', 'buy'), 'buy');
    expect(over('- one\n- two', 'ne', 8), 'ne\n- two');
  });

  test('a line break at the end of the slice stays', () {
    expect(slice('one\ntwo', 0, 4), 'one\n');
    expect(slice('**one**\ntwo', 2, 8), '**one**\n');
  });

  test('a divider and an empty line come along', () {
    expect(slice('a\n---\n\nb', 0, 8), 'a\n---\n\nb');
  });
}
