import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The login email of the Supabase project: `supabase/templates/login_code.html`
/// of the repo. The owner pastes it in the dashboard, in "Confirm signup" and
/// in "Magic Link" (`docs/acceptance/F11-login.md`).
File templateFile() {
  var dir = Directory.current;
  while (!Directory('${dir.path}/supabase/migrations').existsSync()) {
    final parent = dir.parent;
    if (parent.path == dir.path) fail('No supabase folder.');
    dir = parent;
  }
  return File('${dir.path}/supabase/templates/login_code.html');
}

void main() {
  late String html;

  setUpAll(() {
    final file = templateFile();
    if (!file.existsSync()) fail('No file ${file.path}.');
    html = file.readAsStringSync();
  });

  test('the email shows the code', () {
    expect(html, contains('{{ .Token }}'));
  });

  test('the code is the only value Supabase fills in', () {
    // The link of the email cannot open Grove (Q-9), so the email has no
    // link. `{{ .ConfirmationURL }}` and the others must not come back.
    final values = RegExp(r'\{\{[^}]*\}\}').allMatches(html);
    expect({for (final m in values) m.group(0)}, {'{{ .Token }}'});
  });

  test('the email loads nothing from the internet and runs nothing', () {
    final lower = html.toLowerCase();
    for (final part in const [
      'http:',
      'https:',
      '<img',
      '<script',
      '<link',
      '<a ',
      'url(',
      '@import',
    ]) {
      expect(lower, isNot(contains(part)), reason: part);
    }
  });

  test('the email has colours for a light and for a dark mail app', () {
    expect(html, contains('name="color-scheme" content="light dark"'));
    expect(html, contains('prefers-color-scheme: dark'));
  });

  test('the email is a whole page and is small', () {
    expect(html.trimLeft().toLowerCase(), startsWith('<!doctype html>'));
    expect(html.trimRight(), endsWith('</html>'));
    // Gmail cuts an email above 102 KB.
    expect(html.length, lessThan(20000));
  });
}
