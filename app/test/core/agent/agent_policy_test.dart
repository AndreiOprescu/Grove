import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:grove/core/agent/agent_models.dart';
import 'package:grove/core/agent/agent_policy.dart';
import 'package:grove/core/agent/agent_services.dart';
import 'package:grove/core/parsing/markdown_spans.dart';
import 'package:grove/core/parsing/note_parser.dart';
import 'package:grove/core/parsing/reference_parser.dart';

// The rules for running `claude` (ADR 0004): which tools it gets, how its
// answer is read, and how its text is made safe for a note.

const gmail = 'mcp__claude_ai_Gmail__';

/// An `init` line as `claude --output-format stream-json --verbose` prints
/// it first.
String initLine({
  List<String> tools = const [],
  List<Map<String, Object?>> servers = const [],
}) => jsonEncode({
  'type': 'system',
  'subtype': 'init',
  'cwd': '/tmp/x',
  'session_id': 'abc',
  'tools': tools,
  'mcp_servers': servers,
  'model': 'claude',
});

const gmailTools = [
  '${gmail}search_threads',
  '${gmail}get_thread',
  '${gmail}create_draft',
  '${gmail}send_message',
  '${gmail}list_labels',
];

/// The value after [flag] in [args].
String valueOf(List<String> args, String flag) {
  final at = args.indexOf(flag);
  expect(at, greaterThanOrEqualTo(0), reason: flag);
  return args[at + 1];
}

/// The `--output-format json` answer of `claude -p`.
String answer({
  String subtype = 'success',
  bool isError = false,
  Object? structured,
  String result = '',
}) => jsonEncode({
  'type': 'result',
  'subtype': subtype,
  'is_error': isError,
  'result': result,
  'structured_output': ?structured,
  'permission_denials': <Object?>[],
});

void main() {
  group('the arguments', () {
    final services = AgentServices.parseInit(
      initLine(
        tools: [
          ...gmailTools,
          'mcp__claude_ai_Google_Drive__search_files',
          'mcp__stray__get_x',
        ],
        servers: [
          {'name': 'claude.ai Gmail', 'status': 'connected'},
          {'name': 'claude.ai Google Drive', 'status': 'connected'},
          {'name': 'my-files', 'status': 'failed'},
        ],
      ),
    )!;
    final local = AgentPolicy.args();
    final localFiles = AgentPolicy.args(files: true);
    final withServices = AgentPolicy.args(
      services: services,
      on: const {'claude.ai Gmail'},
    );
    final all = [local, localFiles, withServices];

    test('always print mode, a stream of JSON lines with the schema, no '
        'session, no asking, and a step limit', () {
      for (final args in all) {
        expect(args.first, '-p');
        expect(valueOf(args, '--output-format'), 'stream-json');
        expect(args, contains('--verbose'));
        expect(valueOf(args, '--json-schema'), AgentPolicy.resultSchema);
        expect(args, contains('--no-session-persistence'));
        expect(valueOf(args, '--permission-mode'), 'dontAsk');
        expect(valueOf(args, '--max-turns'), '60');
      }
      expect(valueOf(AgentPolicy.args(maxTurns: 5), '--max-turns'), '5');
    });

    test('never a command tool, never more folders, never a bypass', () {
      for (final args in [...all, AgentPolicy.probeArgs()]) {
        for (final a in args) {
          for (final bad in [
            'Bash',
            'PowerShell',
            'NotebookEdit',
            'bypassPermissions',
            '--dangerously-skip-permissions',
            '--add-dir',
            '--mcp-config',
          ]) {
            expect(a.contains(bad), isFalse, reason: '$bad in $a');
          }
        }
      }
    });

    test('Glob and Grep are never allowed by name: that would let them see '
        'outside the folder', () {
      for (final args in all) {
        final allowed = valueOf(args, '--allowedTools').split(',');
        for (final rule in allowed) {
          expect(rule.startsWith('Glob'), isFalse, reason: rule);
          expect(rule.startsWith('Grep'), isFalse, reason: rule);
        }
        // The file tools are allowed only in the folder of the chat.
        for (final tool in ['Read', 'Write', 'Edit']) {
          expect(allowed, contains('$tool(./**)'));
          expect(allowed, isNot(contains(tool)));
        }
      }
    });

    test('locked: restricted mode, the file tools, the web, no MCP', () {
      expect(local, contains('--restricted'));
      expect(local, contains('--strict-mcp-config'));
      expect(
        valueOf(local, '--tools'),
        'Read,Write,Edit,Glob,Grep,WebSearch,WebFetch,TodoWrite',
      );
      expect(
        valueOf(local, '--allowedTools'),
        'Read(./**),Write(./**),Edit(./**),WebSearch,WebFetch,TodoWrite',
      );
      expect(local, isNot(contains('--setting-sources')));
      expect(local, isNot(contains('--disallowedTools')));
      expect(local.any((a) => a.contains('mcp__')), isFalse);
    });

    test('locked with linked files: no WebFetch, so a file cannot make it '
        'send data to a web address', () {
      expect(localFiles, contains('--restricted'));
      expect(localFiles.any((a) => a.contains('WebFetch')), isFalse);
      expect(
        valueOf(localFiles, '--tools'),
        'Read,Write,Edit,Glob,Grep,WebSearch,TodoWrite',
      );
    });

    test('with services: the user settings with hooks off, no WebFetch, the '
        'read tools of the servers that are on, the rest denied', () {
      final args = withServices;
      expect(args, isNot(contains('--restricted')));
      expect(args, isNot(contains('--strict-mcp-config')));
      expect(valueOf(args, '--setting-sources'), 'user');
      expect(jsonDecode(valueOf(args, '--settings')), {
        'disableAllHooks': true,
      });
      expect(args.any((a) => a.contains('WebFetch')), isFalse);
      expect(
        valueOf(args, '--tools'),
        'Read,Write,Edit,Glob,Grep,WebSearch,TodoWrite',
      );
      expect(valueOf(args, '--allowedTools').split(','), [
        'Read(./**)',
        'Write(./**)',
        'Edit(./**)',
        'WebSearch',
        'TodoWrite',
        '${gmail}search_threads',
        '${gmail}get_thread',
      ]);
      expect(
        valueOf(args, '--disallowedTools').split(','),
        unorderedEquals([
          '${gmail}create_draft',
          '${gmail}send_message',
          '${gmail}list_labels',
          // Every server that is off as a whole, also tools the probe did
          // not list, and the servers of the person (stdio).
          'mcp__claude_ai_Google_Drive',
          'mcp__my-files',
          // A tool of no server.
          'mcp__stray__get_x',
        ]),
      );
    });

    test('a server that is on but not connected is denied as a whole', () {
      final s = AgentServices.parseInit(
        initLine(
          tools: ['${gmail}search_threads'],
          servers: [
            {'name': 'claude.ai Gmail', 'status': 'needs-auth'},
          ],
        ),
      )!;
      final args = AgentPolicy.args(services: s, on: const {'claude.ai Gmail'});
      expect(valueOf(args, '--allowedTools'), isNot(contains('mcp__')));
      expect(valueOf(args, '--disallowedTools'), 'mcp__claude_ai_Gmail');
      expect(AgentPolicy.usable(s, const {'claude.ai Gmail'}), isEmpty);
    });

    test('a write tool in the read list (old prefs) is still denied', () {
      const s = AgentServices(
        servers: [
          AgentService(
            name: 'claude.ai Gmail',
            status: 'connected',
            readTools: ['${gmail}search_threads', '${gmail}send_message'],
          ),
        ],
      );
      final args = AgentPolicy.args(services: s, on: const {'claude.ai Gmail'});
      expect(
        valueOf(args, '--allowedTools'),
        endsWith('TodoWrite,${gmail}search_threads'),
      );
      expect(valueOf(args, '--disallowedTools'), '${gmail}send_message');
    });

    test('the usable services: on, connected, with a read tool', () {
      expect(
        AgentPolicy.usable(services, const {
          'claude.ai Gmail',
          'claude.ai Google Drive',
          'my-files',
          'gone',
        }),
        ['claude.ai Gmail', 'claude.ai Google Drive'],
      );
      expect(AgentPolicy.usable(services, const {}), isEmpty);
    });

    test('the probe lists the tools of the person and calls no tool', () {
      final args = AgentPolicy.probeArgs();
      expect(args.first, '-p');
      expect(valueOf(args, '--output-format'), 'stream-json');
      expect(args, contains('--verbose'));
      expect(valueOf(args, '--tools'), '');
      expect(valueOf(args, '--setting-sources'), 'user');
      expect(valueOf(args, '--max-turns'), '1');
      expect(args, contains('--no-session-persistence'));
      expect(valueOf(args, '--permission-mode'), 'dontAsk');
      expect(jsonDecode(valueOf(args, '--settings')), {
        'disableAllHooks': true,
      });
    });
  });

  group('the schema', () {
    test('the schema needs a summary and allows only the known fields', () {
      final schema = jsonDecode(AgentPolicy.resultSchema) as Map;
      expect(schema['type'], 'object');
      expect(schema['required'], ['summary']);
      expect(schema['additionalProperties'], false);
      expect((schema['properties'] as Map).keys.toSet(), {
        'summary',
        'steps',
        'document',
        'email_draft',
        'text_draft',
        'questions',
        'sources',
        'plan_changes',
        'new_tasks',
      });
    });
  });

  group('the answer', () {
    final good = {
      'summary': 'Wrote the plan.',
      'steps': ['Searched the web', 'Wrote it'],
      'document': {'title': 'Trip', 'markdown': '# Trip'},
      'email_draft': {'to': 'ana@x.com', 'subject': 'Hi', 'body': 'Hello'},
      'questions': ['Which hotel?'],
      'sources': ['https://example.com'],
    };

    test('reads structured_output', () {
      final out = AgentPolicy.parse(answer(structured: good));
      final result = (out as AgentOk).result;
      expect(result.summary, 'Wrote the plan.');
      expect(result.steps, hasLength(2));
      expect(
        result.document,
        const AgentDocument(title: 'Trip', markdown: '# Trip'),
      );
      expect(
        result.emailDraft,
        const EmailDraft(to: 'ana@x.com', subject: 'Hi', body: 'Hello'),
      );
      expect(result.textDraft, isNull);
      expect(result.questions, ['Which hotel?']);
      expect(AgentResult.fromJson(result.toJson()), result);
    });

    test('falls back to JSON in the result text', () {
      final out = AgentPolicy.parse(answer(result: jsonEncode(good)));
      expect((out as AgentOk).result.summary, 'Wrote the plan.');
      final fenced = AgentPolicy.parse(
        answer(result: '```json\n${jsonEncode(good)}\n```'),
      );
      expect((fenced as AgentOk).result.summary, 'Wrote the plan.');
    });

    test('an empty draft counts as no draft', () {
      final out = AgentPolicy.parse(
        answer(
          structured: {
            'summary': 'Done',
            'email_draft': {'to': '', 'subject': '', 'body': ''},
            'text_draft': {'to': 'Mum', 'body': ' '},
          },
        ),
      );
      final result = (out as AgentOk).result;
      expect(result.emailDraft, isNull);
      expect(result.textDraft, isNull);
    });

    test('too many steps gives a plain message', () {
      final out = AgentPolicy.parse(
        answer(subtype: 'error_max_turns', isError: true),
      );
      expect((out as AgentFailed).message, 'The agent needed too many steps.');
    });

    test('an error gives a plain message', () {
      final out = AgentPolicy.parse(
        answer(isError: true, result: 'Not logged in · Please run /login'),
      );
      expect((out as AgentFailed).message, contains('Not logged in'));
      final other = AgentPolicy.parse(
        answer(subtype: 'error_during_execution'),
      );
      expect(other, isA<AgentFailed>());
    });

    test('broken output, or no summary, fails', () {
      for (final stdout in [
        '',
        'not json',
        '{"type": "result"',
        '[]',
        answer(),
        answer(result: 'Just some words'),
        answer(structured: {'steps': <String>[]}),
        answer(structured: {'summary': 3}),
        answer(
          structured: {
            'summary': 'x',
            'steps': [1, 2],
          },
        ),
      ]) {
        expect(AgentPolicy.parse(stdout), isA<AgentFailed>(), reason: stdout);
      }
    });
  });

  group('safe for a note', () {
    test('check boxes do not become tasks', () {
      const md =
          '- [ ] Buy milk\n'
          '- [x] Done thing\n'
          '  - [X] Nested\n'
          '* [ ] Star box\n'
          'Keep - [ ] in the middle';
      final safe = AgentPolicy.safeForNote(md);
      expect(NoteParser.checkboxes(safe), isEmpty);
      expect(safe, contains('Buy milk'));
      expect(safe, contains('Keep - [ ] in the middle'));
      expect(safe.split('\n'), hasLength(5));
    });

    test('mentions and hidden task marks do not make links', () {
      const md =
          'See [[Secret note]] and [[Plan|0A1B2C3D-0000-4000-8000-000000000000]] '
          'and [[[x]]]. ⟦t:ABC⟧ [ [ok]]';
      final safe = AgentPolicy.safeForNote(md);
      expect(ReferenceParser.mentions(safe), isEmpty);
      expect(safe, isNot(contains('[[')));
      expect(safe, isNot(contains('⟦')));
      expect(safe, contains('Secret note'));
      expect(NoteParser.withoutMarkers(safe), safe);
    });

    test('plain Markdown stays as it is', () {
      const md = '# Title\n\n## Part\n\n- one\n- two\n\nC# and F# # 3';
      expect(AgentPolicy.safeForNote(md), md);
    });

    test('a #word does not become a Grove tag', () {
      const md =
          '#Work and #home-life, (#x) #12 #déjà_vu\n'
          'Done.#late ##two `#code` [#in](x)';
      final safe = AgentPolicy.safeForNote(md);
      expect(NoteParser.tags(safe), isEmpty);
      expect(
        MarkdownSpans.scan(safe).where((s) => s.kind.type == SpanType.tag),
        isEmpty,
      );
      // The words are still there to read.
      expect(safe.replaceAll('\u200B', ''), contains('#Work and #home-life'));
    });

    test('links of the agent are plain text, not links', () {
      const md =
          'See [the site](https://evil.example/x?a=1) or '
          'https://evil.example/y, http://a.b and HTTPS://SHOUT.example.\n'
          '- https://example.com/plan\n'
          '[two](http://x.y) ![pic](https://img.example/p.png)';
      final safe = AgentPolicy.safeForNote(md);
      final kinds = MarkdownSpans.scan(safe).map((s) => s.kind.type);
      expect(kinds, isNot(contains(SpanType.link)));
      expect(kinds, isNot(contains(SpanType.linkWords)));
      // The address can still be read.
      final plain = safe.replaceAll('\u200B', '');
      expect(plain, contains('the site (https://evil.example/x?a=1)'));
      expect(plain, contains('https://example.com/plan'));
      expect(plain, contains('two (http://x.y)'));
    });
  });

  group('mail and messages links', () {
    test('mailto: with spaces, & and new lines', () {
      final uri = AgentPolicy.mailtoUri(
        const EmailDraft(
          to: 'ana@x.com, bo@y.org',
          subject: 'Tom & Jerry',
          body: 'Hi Ana,\nSee you at 5 & bring snacks?',
        ),
      );
      expect(uri.scheme, 'mailto');
      expect(
        uri.toString(),
        'mailto:ana@x.com,bo@y.org'
        '?subject=Tom%20%26%20Jerry'
        '&body=Hi%20Ana%2C%0D%0ASee%20you%20at%205%20%26%20bring%20snacks%3F',
      );
    });

    test('sms: a phone number keeps only its digits and the plus', () {
      final uri = AgentPolicy.smsUri(
        const TextDraft(to: '+40 712 (345) 678', body: 'On my way & late\nX'),
      );
      expect(uri.scheme, 'sms');
      expect(
        uri.toString(),
        'sms:+40712345678?body=On%20my%20way%20%26%20late%0AX',
      );
    });

    test('sms: a name is encoded too', () {
      final uri = AgentPolicy.smsUri(
        const TextDraft(to: 'Mum & Dad', body: 'Hi'),
      );
      expect(uri.toString(), 'sms:Mum%20%26%20Dad?body=Hi');
    });
  });
}
