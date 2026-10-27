import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:grove/core/agent/agent_services.dart';
import 'package:grove/core/agent/mcp_tool_rules.dart';

// The services of the person (ADR 0008): which MCP tools only read, and the
// servers and tools the probe found.

const gmail = 'mcp__claude_ai_Gmail__';
const drive = 'mcp__claude_ai_Google_Drive__';

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

void main() {
  group('a server rule', () {
    test('is mcp__ and the name with odd characters as _', () {
      expect(
        McpToolRules.serverRule('claude.ai Gmail'),
        'mcp__claude_ai_Gmail',
      );
      expect(
        McpToolRules.serverRule('claude.ai Google Drive'),
        'mcp__claude_ai_Google_Drive',
      );
      expect(McpToolRules.serverRule('my-files_2'), 'mcp__my-files_2');
      expect(McpToolRules.serverRule('a/b:c(é)'), 'mcp__a_b_c___');
    });
  });

  group('a read tool', () {
    test('starts with a read verb and has no write word', () {
      for (final name in [
        '${gmail}search_threads',
        '${gmail}get_thread',
        '${gmail}getMessage',
        '${gmail}list_messages',
        '${gmail}read_message',
        '${gmail}fetch_attachment',
        '${gmail}get_profile',
        '${gmail}get-message-by-id',
        '${gmail}findEmailsFromQuery',
        '${drive}search_files',
        '${drive}describe_file',
        '${drive}view_document',
        '${drive}lookup_user',
        '${drive}count_items',
        '${drive}query_sheet',
        'mcp__notion__get_settings',
        'mcp__notion__get_address',
      ]) {
        expect(McpToolRules.isReadTool(name), isTrue, reason: name);
      }
    });

    test('the server name may come first in the tool name', () {
      expect(
        McpToolRules.isReadTool(
          '${gmail}gmail_search_messages',
          server: 'claude.ai Gmail',
        ),
        isTrue,
      );
      expect(
        McpToolRules.isReadTool('mcp__Notion__notion-search', server: 'Notion'),
        isTrue,
      );
      // Without the server, the first word is not a verb.
      expect(McpToolRules.isReadTool('${gmail}gmail_search_messages'), isFalse);
    });

    test('a write word anywhere, or an unknown verb, is not a read tool', () {
      for (final name in [
        '${gmail}send_message',
        '${gmail}create_draft',
        '${gmail}list_drafts',
        '${gmail}list_labels',
        '${gmail}get_and_mark_read',
        '${gmail}list_and_snooze',
        '${gmail}getMessageAndArchive',
        '${gmail}get_and_forward',
        '${gmail}mark_as_read',
        '${gmail}message_get',
        '${gmail}trash_thread',
        '${gmail}reply_all',
        '${drive}upload_file',
        '${drive}move_file',
        '${drive}delete_file',
        '${drive}get_file_then_update',
        '${drive}list_updated_files',
        '${drive}search_and_remove',
        'mcp__cal__update_event',
        'mcp__cal__get_event_and_set_status',
        'mcp__cal__insert_event',
        'mcp__cal__patch_event',
        'mcp__cal__put_item',
        'mcp__cal__post_message',
        'mcp__cal__add_guest',
        'mcp__cal__edit_note',
        'mcp__cal__write_page',
        'mcp__cal__modify_page',
        'mcp__cal__run_query',
        'mcp__cal__do_it',
      ]) {
        expect(McpToolRules.isReadTool(name), isFalse, reason: name);
      }
    });

    test('odd names are not read tools', () {
      for (final name in [
        '',
        'Read',
        'WebFetch',
        'mcp__',
        'mcp__x',
        'mcp__x__',
        '${gmail}get.message',
        '${gmail}get message',
        '${gmail}gmail',
      ]) {
        expect(McpToolRules.isReadTool(name), isFalse, reason: name);
      }
      // A tool of another server when the server is named.
      expect(
        McpToolRules.isReadTool('mcp__other__get_thread', server: 'Gmail'),
        isFalse,
      );
    });
  });

  group('the services of the probe', () {
    test('sorts each server: its read tools and its other tools', () {
      final s = AgentServices.parseInit(
        initLine(
          tools: [
            'WebSearch',
            'Read',
            '${gmail}search_threads',
            '${gmail}send_message',
            '${drive}search_files',
            '${drive}create_file',
            'mcp__lost__get_x',
          ],
          servers: [
            {'name': 'claude.ai Gmail', 'status': 'connected'},
            {'name': 'claude.ai Google Drive', 'status': 'needs-auth'},
            {'name': 'my-files', 'status': 'failed'},
          ],
        ),
      )!;
      expect(s.ready, isTrue);
      expect(
        [for (final x in s.servers) x.name],
        ['claude.ai Gmail', 'claude.ai Google Drive', 'my-files'],
      );
      final g = s.server('claude.ai Gmail')!;
      expect(g.status, 'connected');
      expect(g.readTools, ['${gmail}search_threads']);
      expect(g.otherTools, ['${gmail}send_message']);
      expect(g.usable, isTrue);
      final d = s.server('claude.ai Google Drive')!;
      expect(d.readTools, ['${drive}search_files']);
      expect(d.usable, isFalse);
      expect(s.server('my-files')!.usable, isFalse);
      // A tool of no server is never allowed.
      expect(s.strayTools, ['mcp__lost__get_x']);
    });

    test('a server that is still starting: not ready', () {
      AgentServices parse(List<Map<String, Object?>> servers) =>
          AgentServices.parseInit(initLine(servers: servers))!;
      expect(
        parse([
          {'name': 'a', 'status': 'connected'},
          {'name': 'b', 'status': 'needs-auth'},
          {'name': 'c', 'status': 'failed'},
          {'name': 'd', 'status': 'disabled'},
        ]).ready,
        isTrue,
      );
      for (final odd in [
        {'name': 'x', 'status': 'pending'},
        {'name': 'x', 'status': 'starting'},
        {'name': 'x'},
        {'status': 'connected'},
      ]) {
        expect(parse([odd]).ready, isFalse, reason: '$odd');
      }
    });

    test('two servers with the same rule are never usable', () {
      final s = AgentServices.parseInit(
        initLine(
          tools: ['${gmail}search_threads'],
          servers: [
            {'name': 'claude.ai Gmail', 'status': 'connected'},
            {'name': 'claude_ai_Gmail', 'status': 'connected'},
          ],
        ),
      )!;
      for (final x in s.servers) {
        expect(x.clash, isTrue);
        expect(x.usable, isFalse);
        expect(x.readTools, isEmpty);
      }
    });

    test('a server name that starts another one: tools go to the longest', () {
      final s = AgentServices.parseInit(
        initLine(
          tools: ['mcp__a__get_x', 'mcp__a__b__get_y'],
          servers: [
            {'name': 'a', 'status': 'connected'},
            {'name': 'a  b', 'status': 'connected'},
          ],
        ),
      )!;
      expect(s.server('a')!.readTools, ['mcp__a__get_x']);
      expect(s.server('a  b')!.readTools, ['mcp__a__b__get_y']);
    });

    test('a line that is not the init event gives null', () {
      expect(AgentServices.parseInit(''), isNull);
      expect(AgentServices.parseInit('{broken'), isNull);
      expect(AgentServices.parseInit('[1, 2]'), isNull);
      expect(
        AgentServices.parseInit(jsonEncode({'type': 'assistant'})),
        isNull,
      );
    });

    test('keeps in the prefs as JSON and reads back the same', () {
      final s = AgentServices.parseInit(
        initLine(
          tools: ['${gmail}search_threads', '${gmail}send_message'],
          servers: [
            {'name': 'claude.ai Gmail', 'status': 'connected'},
          ],
        ),
      )!;
      final back = AgentServices.fromJson(jsonDecode(jsonEncode(s.toJson())));
      expect(back, s);
      expect(AgentServices.fromJson('nonsense'), isNull);
      expect(AgentServices.fromJson({'servers': 3}), isNull);
    });

    test('the status in plain words', () {
      expect(AgentService.statusText('connected'), 'Connected');
      expect(AgentService.statusText('needs-auth'), 'Needs sign-in');
      expect(AgentService.statusText('failed'), 'Failed to start');
      expect(AgentService.statusText('disabled'), 'Off in Claude Code');
      expect(AgentService.statusText('pending'), 'Starting');
      expect(AgentService.statusText('odd'), 'odd');
    });
  });
}
