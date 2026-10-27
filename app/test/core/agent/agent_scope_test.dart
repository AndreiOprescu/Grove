import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:grove/core/agent/agent_scope.dart';

// The folder of the agent (ADR 0008): one folder per chat under
// "Agent workspace", ids that are uuids, paths that stay inside, the check
// after each run, and the check of the Claude Code settings of the person.

const id = '0F8FAD5B-D9CB-469F-A165-70867728950E';

void main() {
  group('ids and folders', () {
    test('an id is a uuid, in any case', () {
      expect(AgentScope.isId(id), isTrue);
      expect(AgentScope.isId(id.toLowerCase()), isTrue);
      for (final bad in [
        '',
        'X',
        '..',
        '../$id',
        '$id/..',
        '$id ',
        '0F8FAD5B-D9CB-469F-A165-70867728950',
        '0F8FAD5B_D9CB_469F_A165_70867728950E',
        '0F8FAD5B-D9CB-469F-A165-70867728950G',
      ]) {
        expect(AgentScope.isId(bad), isFalse, reason: bad);
      }
    });

    test('the folder of a chat is under the root; no folder for an odd id', () {
      expect(AgentScope.root('/data'), '/data/Agent workspace');
      expect(AgentScope.folder('/data', id), '/data/Agent workspace/$id');
      expect(
        AgentScope.folder(r'C:\data', id, sep: r'\'),
        'C:\\data\\Agent workspace\\$id',
      );
      expect(AgentScope.folder('/data', '../../etc'), isNull);
      expect(AgentScope.folder('/data', ''), isNull);
    });

    test('inside: under the root, never the root itself, never with ..', () {
      const root = '/data/Agent workspace';
      expect(AgentScope.isInside(root, '$root/$id'), isTrue);
      expect(AgentScope.isInside(root, '$root/$id/inputs/a.txt'), isTrue);
      expect(AgentScope.isInside('$root/', '$root/$id'), isTrue);
      expect(AgentScope.isInside(root, '$root/./$id'), isTrue);
      expect(AgentScope.isInside(root, root), isFalse);
      expect(AgentScope.isInside(root, '$root/'), isFalse);
      expect(AgentScope.isInside(root, '$root/$id/../../x'), isFalse);
      expect(AgentScope.isInside(root, '$root/..'), isFalse);
      expect(AgentScope.isInside(root, '/data/Agent workspace2/x'), isFalse);
      expect(AgentScope.isInside(root, '/data/x'), isFalse);
      expect(AgentScope.isInside(root, 'relative/x'), isFalse);
      expect(AgentScope.isInside(r'C:\d\A', r'C:\d\A\x', sep: r'\'), isTrue);
      expect(AgentScope.isInside(r'C:\d\A', r'C:\d\B\x', sep: r'\'), isFalse);
    });
  });

  group('the check after a run', () {
    test('lists the files the agent made, not the inputs, sorted', () {
      final a = AgentScope.audit(const [
        AgentEntry('notes.md', AgentEntryKind.file, 10),
        AgentEntry('inputs', AgentEntryKind.folder),
        AgentEntry('inputs/plan.txt', AgentEntryKind.file, 5),
        AgentEntry('drafts', AgentEntryKind.folder),
        AgentEntry('drafts/b.md', AgentEntryKind.file, 1),
        AgentEntry('a.txt', AgentEntryKind.file, 1),
      ]);
      expect(a.files, ['a.txt', 'drafts/b.md', 'notes.md']);
      expect(a.remove, isEmpty);
      expect(a.count, 4);
      expect(a.bytes, 17);
      expect(a.overCap, isFalse);
    });

    test('drops links and odd entries, and files Claude Code would load', () {
      final a = AgentScope.audit(const [
        AgentEntry('home', AgentEntryKind.link),
        AgentEntry('pipe', AgentEntryKind.other),
        AgentEntry('.mcp.json', AgentEntryKind.file, 5),
        AgentEntry('.claude', AgentEntryKind.folder),
        AgentEntry('.claude/settings.json', AgentEntryKind.file, 5),
        AgentEntry('CLAUDE.md', AgentEntryKind.file, 5),
        AgentEntry('sub', AgentEntryKind.folder),
        AgentEntry('sub/CLAUDE.local.md', AgentEntryKind.file, 5),
        AgentEntry('sub/.mcp.json', AgentEntryKind.file, 5),
        AgentEntry('ok.md', AgentEntryKind.file, 5),
      ]);
      expect(a.remove, [
        'home',
        'pipe',
        '.mcp.json',
        '.claude',
        'CLAUDE.md',
        'sub/CLAUDE.local.md',
        'sub/.mcp.json',
      ]);
      // The files under a removed folder go with it.
      expect(a.files, ['ok.md']);
      expect(a.count, 1);
    });

    test('over 500 files or 200 MB is over the cap', () {
      final many = [
        for (var i = 0; i <= AgentScope.maxFiles; i++)
          AgentEntry('f$i.txt', AgentEntryKind.file, 1),
      ];
      expect(AgentScope.audit(many).overCap, isTrue);
      expect(AgentScope.audit(many.sublist(1)).overCap, isFalse);
      expect(
        AgentScope.audit(const [
          AgentEntry('big.bin', AgentEntryKind.file, AgentScope.maxBytes + 1),
        ]).overCap,
        isTrue,
      );
      expect(AgentScope.tooBig, contains('500 files'));
    });

    test('only plain text files open from Grove; others show in Finder', () {
      for (final ok in ['a.md', 'b.TXT', 'd.json', 'e.markdown']) {
        expect(AgentScope.canOpen(ok), isTrue, reason: ok);
      }
      // A table opens in a spreadsheet app, which could run a formula.
      for (final no in [
        'run.command',
        'x.app',
        'y.html',
        'z.sh',
        'c.csv',
        'f.tsv',
        'md',
        '',
      ]) {
        expect(AgentScope.canOpen(no), isFalse, reason: no);
      }
    });
  });

  group('the settings of the person', () {
    String settings(Map<String, Object?> json) => jsonEncode(json);
    String? problem(String? text) =>
        AgentScope.settingsProblem('~/.claude/settings.json', text);

    test('no file, or rules that do not reach files, are fine', () {
      expect(problem(null), isNull);
      expect(problem(settings({})), isNull);
      expect(
        problem(
          settings({
            'permissions': {
              'allow': ['Bash(git status)', 'WebSearch', 'mcp__x__get_y'],
              'deny': ['Read(~/.ssh/**)'],
              'additionalDirectories': <String>[],
            },
          }),
        ),
        isNull,
      );
    });

    test('a file tool in allow is a problem', () {
      for (final rule in [
        'Read',
        'Read(//Users/ann/**)',
        'Write(~/x)',
        'Edit',
        'MultiEdit',
        'Glob',
        'Grep(*)',
        'NotebookEdit',
        ' Read ',
      ]) {
        final p = problem(
          settings({
            'permissions': {
              'allow': [rule],
            },
          }),
        );
        expect(p, isNotNull, reason: rule);
        expect(p, contains('~/.claude/settings.json'));
        expect(p, contains(rule.trim()));
        expect(p, contains('Use my services'));
      }
    });

    test('a whole MCP server or a wildcard in allow is a problem', () {
      for (final rule in ['mcp__claude_ai_Gmail', 'mcp__x__*', '*']) {
        expect(
          problem(
            settings({
              'permissions': {
                'allow': [rule],
              },
            }),
          ),
          isNotNull,
          reason: rule,
        );
      }
    });

    test('extra folders or project MCP servers are a problem', () {
      expect(
        problem(
          settings({
            'permissions': {
              'additionalDirectories': ['~/Documents'],
            },
          }),
        ),
        contains('~/Documents'),
      );
      expect(
        problem(settings({'enableAllProjectMcpServers': true})),
        isNotNull,
      );
      expect(
        problem(
          settings({
            'enabledMcpjsonServers': ['x'],
          }),
        ),
        isNotNull,
      );
    });

    test('a file Grove cannot read is a problem: better safe', () {
      expect(problem('{broken'), contains('could not read'));
      expect(problem('[1]'), contains('could not read'));
    });
  });
}
