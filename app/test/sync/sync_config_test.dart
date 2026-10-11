import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:grove/sync/sync.dart';

void main() {
  group('The keys of the Supabase project', () {
    test('a web address and a key: the sync is on', () {
      expect(
        const SyncConfig(url: 'https://abc.supabase.co', anonKey: 'key').isSet,
        isTrue,
      );
      expect(
        const SyncConfig(url: ' http://127.0.0.1:54321 ', anonKey: 'k').isSet,
        isTrue,
      );
    });

    test('a missing or broken value: the sync is off', () {
      const off = [
        SyncConfig(url: '', anonKey: ''),
        SyncConfig(url: 'https://abc.supabase.co', anonKey: ''),
        SyncConfig(url: 'https://abc.supabase.co', anonKey: '  '),
        SyncConfig(url: '', anonKey: 'key'),
        SyncConfig(url: 'abc.supabase.co', anonKey: 'key'),
        SyncConfig(url: 'ftp://abc.supabase.co', anonKey: 'key'),
        SyncConfig(url: 'https://', anonKey: 'key'),
      ];
      for (final c in off) {
        expect(c.isSet, isFalse, reason: '"${c.url}" "${c.anonKey}"');
      }
    });

    test('the tests run with no keys', () {
      expect(SyncConfig.fromEnvironment.isSet, isFalse);
    });

    test('the example file has the two names, and no value', () {
      final text = File('config/supabase.example.json').readAsStringSync();
      expect(jsonDecode(text), {'SUPABASE_URL': '', 'SUPABASE_ANON_KEY': ''});
    });

    test('git does not keep the file with the real keys', () {
      final rules = File('../.gitignore').readAsLinesSync();
      expect(rules, contains('app/config/supabase.json'));
    });
  });
}
