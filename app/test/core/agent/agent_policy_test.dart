import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:grove/core/agent/agent_models.dart';
import 'package:grove/core/agent/agent_policy.dart';
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
    final emailOff = AgentPolicy.args(email: false);
    final init = AgentPolicy.parseInit(
      initLine(
        tools: [...gmailTools, 'mcp__claude_ai_Google_Drive__search_files'],
        servers: [
          {'name': 'claude.ai Gmail', 'status': 'connected'},
          {'name': 'claude.ai Google Drive', 'status': 'connected'},
          {'name': 'my-files', 'status': 'failed'},
        ],
      ),
    )!;
    final emailOn = AgentPolicy.args(
      email: true,
      gmailReadTools: init.gmailReadTools,
      otherConnectorTools: init.denied,
      otherServers: init.otherServers,
    );

    test('always print mode, a stream of JSON lines with the schema, no '
        'session, no asking, and a step limit', () {
      for (final args in [emailOff, emailOn]) {
        expect(args.first, '-p');
        expect(valueOf(args, '--output-format'), 'stream-json');
        expect(args, contains('--verbose'));
        expect(valueOf(args, '--json-schema'), AgentPolicy.resultSchema);
        expect(args, contains('--no-session-persistence'));
        expect(valueOf(args, '--permission-mode'), 'dontAsk');
        expect(valueOf(args, '--max-turns'), '60');
      }
      expect(
        valueOf(AgentPolicy.args(email: false, maxTurns: 5), '--max-turns'),
        '5',
      );
    });

    test(
      'never Bash, Write or Edit, and nothing that runs or changes files',
      () {
        for (final args in [emailOff, emailOn, AgentPolicy.probeArgs()]) {
          for (final a in args) {
            for (final bad in [
              'Bash',
              'Write',
              'Edit',
              'NotebookEdit',
              'bypassPermissions',
              '--dangerously-skip-permissions',
            ]) {
              expect(a.contains(bad), isFalse, reason: '$bad in $a');
            }
          }
        }
      },
    );

    test('email off: web only, no connector, and none of the settings of '
        'the person', () {
      expect(valueOf(emailOff, '--tools'), 'WebSearch,WebFetch');
      expect(valueOf(emailOff, '--allowedTools'), 'WebSearch,WebFetch');
      expect(valueOf(emailOff, '--setting-sources'), '');
      expect(emailOff, contains('--strict-mcp-config'));
      expect(emailOff.any((a) => a.contains('mcp__')), isFalse);
      expect(emailOff, isNot(contains('--disallowedTools')));
    });

    test('email on: no WebFetch anywhere, Gmail read tools allowed, the '
        'rest denied, hooks off', () {
      expect(emailOn.any((a) => a.contains('WebFetch')), isFalse);
      expect(valueOf(emailOn, '--tools'), 'WebSearch');
      expect(valueOf(emailOn, '--allowedTools').split(','), [
        'WebSearch',
        '${gmail}search_threads',
        '${gmail}get_thread',
      ]);
      expect(
        valueOf(emailOn, '--disallowedTools').split(','),
        unorderedEquals([
          '${gmail}create_draft',
          '${gmail}send_message',
          '${gmail}list_labels',
          'mcp__claude_ai_Google_Drive__search_files',
          // Every other server as a whole, also tools the probe did not
          // list, and the servers of the person (stdio).
          'mcp__claude_ai_Google_Drive',
          'mcp__my-files',
        ]),
      );
      expect(valueOf(emailOn, '--setting-sources'), 'user');
      expect(jsonDecode(valueOf(emailOn, '--settings')), {
        'disableAllHooks': true,
      });
      expect(emailOn, isNot(contains('--strict-mcp-config')));
    });

    test('email on: a write tool passed as a read tool is still denied', () {
      final args = AgentPolicy.args(
        email: true,
        gmailReadTools: ['${gmail}search_threads', '${gmail}send_message'],
      );
      expect(
        valueOf(args, '--allowedTools'),
        'WebSearch,${gmail}search_threads',
      );
      expect(valueOf(args, '--disallowedTools'), '${gmail}send_message');
    });

    test('a server rule is mcp__ and the name with odd characters as _', () {
      expect(AgentPolicy.serverRule('claude.ai Gmail'), 'mcp__claude_ai_Gmail');
      // The Gmail tools start with the rule of the Gmail server.
      expect(
        AgentPolicy.gmailPrefix,
        '${AgentPolicy.serverRule(AgentPolicy.gmailServer)}__',
      );
      expect(
        AgentPolicy.serverRule('claude.ai Google Drive'),
        'mcp__claude_ai_Google_Drive',
      );
      expect(AgentPolicy.serverRule('my-files_2'), 'mcp__my-files_2');
      expect(AgentPolicy.serverRule('a/b:c(é)'), 'mcp__a_b_c___');
    });

    test('email on: the Gmail server itself is never denied (a deny beats '
        'an allow)', () {
      final args = AgentPolicy.args(
        email: true,
        gmailReadTools: ['${gmail}search_threads'],
        otherServers: ['claude.ai Gmail', 'claude_ai_Gmail', 'Notion'],
      );
      final denied = valueOf(args, '--disallowedTools').split(',');
      expect(denied, ['mcp__Notion']);
      expect(
        valueOf(args, '--allowedTools'),
        'WebSearch,${gmail}search_threads',
      );
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

  group('the init line', () {
    test('sorts the Gmail tools: read words in, a write word anywhere out', () {
      final init = AgentPolicy.parseInit(
        initLine(
          tools: [
            ...gmailTools,
            '${gmail}read_message',
            '${gmail}fetch_attachment',
            '${gmail}list_drafts',
            '${gmail}mark_as_read',
            '${gmail}get_and_forward',
            '${gmail}gmail_search_messages',
            'mcp__claude_ai_Google_Calendar__list_events',
          ],
          servers: [
            {'name': 'claude.ai Gmail', 'status': 'connected'},
          ],
        ),
      )!;
      expect(init.gmailReadTools, [
        '${gmail}search_threads',
        '${gmail}get_thread',
        '${gmail}read_message',
        '${gmail}fetch_attachment',
        '${gmail}gmail_search_messages',
      ]);
      expect(init.gmailOtherTools, [
        '${gmail}create_draft',
        '${gmail}send_message',
        // "labels" is not a known word. Better safe: listing labels is denied.
        '${gmail}list_labels',
        '${gmail}list_drafts',
        // A read word that is not the verb does not make a tool read-only.
        '${gmail}mark_as_read',
        '${gmail}get_and_forward',
      ]);
      expect(init.otherConnectorTools, [
        'mcp__claude_ai_Google_Calendar__list_events',
      ]);
      expect(init.gmailStatus, 'connected');
      expect(init.gmailReady, isTrue);
    });

    test('a Gmail tool is read-only only when every word of its name is a '
        'known read word, and the first one is a read verb', () {
      for (final name in [
        'search_threads',
        'get_thread',
        'getMessage',
        'list_messages',
        'read_message',
        'fetch_attachment',
        'gmail_search_messages',
        'gmail_read_thread',
        'get_profile',
        'get-message-by-id',
        'findEmailsFromQuery',
      ]) {
        expect(
          AgentPolicy.isGmailReadTool('$gmail$name'),
          isTrue,
          reason: name,
        );
      }
      for (final name in [
        'get_and_mark_read',
        'list_and_snooze',
        'create_draft',
        'send_message',
        'list_labels',
        'list_drafts',
        'mark_as_read',
        'message_get',
        'get_message_v2',
        'get.message',
        'getMessageAndArchive',
        'gmail',
        '',
      ]) {
        expect(
          AgentPolicy.isGmailReadTool('$gmail$name'),
          isFalse,
          reason: name,
        );
      }
      // Not a Gmail tool at all.
      expect(AgentPolicy.isGmailReadTool('mcp__other__get_thread'), isFalse);
    });

    test('a connection that is still starting: the probe is not ready', () {
      AgentInit init(List<Map<String, Object?>> servers) =>
          AgentPolicy.parseInit(
            initLine(tools: ['${gmail}search_threads'], servers: servers),
          )!;
      final settled = init([
        {'name': 'claude.ai Gmail', 'status': 'connected'},
        {'name': 'claude.ai Drive', 'status': 'needs-auth'},
        {'name': 'local', 'status': 'failed'},
        {'name': 'off', 'status': 'disabled'},
      ]);
      expect(settled.ready, isTrue);
      expect(settled.gmailReady, isTrue);
      expect(settled.otherServers, ['claude.ai Drive', 'local', 'off']);
      for (final odd in [
        {'name': 'local', 'status': 'pending'},
        {'name': 'local', 'status': 'starting'},
        {'name': 'local'},
        {'status': 'connected'},
        {'name': 'claude.ai Gmail', 'status': 'pending'},
      ]) {
        final i = init([
          {'name': 'claude.ai Gmail', 'status': 'connected'},
          odd,
        ]);
        expect(i.ready, isFalse, reason: '$odd');
      }
      expect(AgentPolicy.connectionsStarting, contains('Try again'));
    });

    test('another server named like Gmail makes Gmail not ready', () {
      final init = AgentPolicy.parseInit(
        initLine(
          tools: ['${gmail}search_threads'],
          servers: [
            {'name': 'claude.ai Gmail', 'status': 'connected'},
            {'name': 'claude_ai_Gmail', 'status': 'connected'},
          ],
        ),
      )!;
      expect(init.gmailReady, isFalse);
    });

    test('built-in tools are not connector tools', () {
      final init = AgentPolicy.parseInit(
        initLine(tools: ['Bash', 'Read', 'mcp__other__do_it']),
      )!;
      expect(init.gmailReadTools, isEmpty);
      expect(init.otherConnectorTools, ['mcp__other__do_it']);
      expect(init.denied, ['mcp__other__do_it']);
    });

    test('Gmail that needs a login, or is missing, is not ready', () {
      final login = AgentPolicy.parseInit(
        initLine(
          servers: [
            {'name': 'claude.ai Gmail', 'status': 'needs-auth'},
          ],
        ),
      )!;
      expect(login.gmailStatus, 'needs-auth');
      expect(login.gmailReady, isFalse);
      final none = AgentPolicy.parseInit(initLine())!;
      expect(none.gmailStatus, isNull);
      expect(none.gmailReady, isFalse);
      // Tools without a connected server do not count.
      final odd = AgentPolicy.parseInit(
        initLine(tools: ['${gmail}search_threads']),
      )!;
      expect(odd.gmailReady, isFalse);
      expect(AgentPolicy.gmailNotReady, contains('Connect Gmail in claude.ai'));
    });

    test('a line that is not the init event gives null', () {
      expect(AgentPolicy.parseInit(''), isNull);
      expect(AgentPolicy.parseInit('{broken'), isNull);
      expect(AgentPolicy.parseInit('[1, 2]'), isNull);
      expect(AgentPolicy.parseInit(jsonEncode({'type': 'assistant'})), isNull);
    });
  });

  group('the schema and the prompt', () {
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

    test(
      'the prompt has the task, the rules, and says if email is allowed',
      () {
        final off = AgentPolicy.prompt(
          'Plan the trip',
          'To Rome in May',
          'Keep it short',
          emailAccess: false,
        );
        expect(off, contains('Plan the trip'));
        expect(off, contains('To Rome in May'));
        expect(off, contains('Keep it short'));
        expect(off, contains('never send'));
        expect(off, contains('untrusted'));
        expect(off, contains('cannot read email'));
        final on = AgentPolicy.prompt(
          'Reply to Ana',
          '',
          '',
          emailAccess: true,
        );
        expect(on, contains('Gmail'));
        expect(on, isNot(contains('cannot read email')));
      },
    );
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
