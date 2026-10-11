// Which links Grove may open in the browser (Q-16 of `docs/questions.md`):
// only `http` and `https`.
import 'package:flutter_test/flutter_test.dart';
import 'package:grove/ui/editor/editor_tools.dart';

void main() {
  test('an http or https address opens', () {
    expect(webLink('https://grove.example/a?b=1#c'), isNotNull);
    expect(
      webLink('https://grove.example/a?b=1#c').toString(),
      'https://grove.example/a?b=1#c',
    );
    expect(webLink('http://grove.example'), Uri.parse('http://grove.example'));
    expect(webLink('  https://grove.example  ')!.host, 'grove.example');
    expect(webLink('HTTPS://Grove.Example/Path')!.scheme, 'https');
  });

  test('another scheme does nothing', () {
    for (final text in [
      'file:///etc/passwd',
      'ftp://grove.example/a',
      'mailto:me@grove.example',
      'tel:112',
      'javascript:alert(1)',
      'data:text/html,hello',
      'grove-image:11111111-2222-3333-4444-555555555555',
      'x-apple.systempreferences:com.apple.preference.notifications',
      'intent://grove.example#Intent;scheme=https;end',
    ]) {
      expect(webLink(text), isNull, reason: text);
    }
  });

  test('a text that is not a web address does nothing', () {
    for (final text in [
      '',
      '   ',
      'grove.example',
      'https://',
      'https:///path',
      'http:grove.example',
      'https://exa mple.com',
      '//grove.example/a',
    ]) {
      expect(webLink(text), isNull, reason: text);
    }
  });
}
