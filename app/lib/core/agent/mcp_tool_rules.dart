/// Which tools of an MCP server only read (ADR 0008).
///
/// Grove allows the agent only the tools whose names say they read. A name
/// is cut into words at `_`, `-` and a capital letter (`getMessage`). The
/// first word, after the words of the server name, must be a read verb
/// ("get", "list", "search"...), and no word may be a write word ("send",
/// "update", "draft"...) or join two actions ("and", "then"). A name Grove
/// is not sure of is not a read tool: better safe.
abstract final class McpToolRules {
  static final _notRuleChar = RegExp('[^A-Za-z0-9_-]');

  /// The `--allowedTools` / `--disallowedTools` rule of a whole MCP server:
  /// `mcp__` and the name, with each character other than a letter, a
  /// digit, `_` or `-` as `_`. That is how `claude` names the tools:
  /// "claude.ai Gmail" gives `mcp__claude_ai_Gmail__search_threads`.
  static String serverRule(String server) =>
      'mcp__${server.replaceAll(_notRuleChar, '_')}';

  /// The verbs that only read. The first word of a read tool is one of them.
  static const readVerbs = {
    'get',
    'list',
    'search',
    'find',
    'query',
    'read',
    'fetch',
    'describe',
    'view',
    'lookup',
    'count',
  };

  /// The words that change something, send something, or start something.
  /// A tool with one of them, in any form ("sends", "updated", "setting"),
  /// is never a read tool.
  static const writeWords = {
    // The words of the plan.
    'send', 'create', 'update', 'delete', 'modify', 'move', 'trash',
    'archive', 'label', 'reply', 'forward', 'draft', 'write', 'add',
    'remove', 'set', 'put', 'post', 'patch', 'upload', 'insert', 'edit',
    // More of them.
    'mark', 'unmark', 'snooze', 'star', 'unstar', 'flag', 'unflag', 'copy',
    'share', 'unshare', 'invite', 'accept', 'decline', 'cancel', 'book',
    'buy', 'pay', 'purchase', 'transfer', 'run', 'exec', 'execute',
    'eval', 'shell', 'command', 'script', 'submit', 'approve', 'reject',
    'merge', 'publish', 'unpublish', 'schedule', 'reschedule', 'import',
    'export', 'download', 'sync', 'rename', 'replace', 'restore', 'clear',
    'reset', 'enable', 'disable', 'start', 'stop', 'kill', 'launch',
    'apply', 'save', 'commit', 'push', 'deploy', 'trigger', 'invoke', 'call',
    'mute', 'unmute', 'subscribe', 'unsubscribe', 'watch', 'unwatch',
    'follow', 'unfollow', 'assign', 'unassign', 'close', 'reopen',
    'complete', 'resolve', 'dismiss', 'ack', 'acknowledge', 'respond',
    'rsvp', 'comment', 'upsert', 'append', 'attach', 'detach', 'link',
    'unlink', 'tag', 'untag', 'pin', 'unpin', 'unarchive', 'untrash',
    'empty', 'purge', 'drop', 'destroy', 'erase', 'wipe', 'grant', 'revoke',
    'block', 'unblock', 'ban', 'kick', 'join', 'leave', 'login', 'logout',
    'authorize', 'notify', 'remind', 'react', 'vote', 'generate',
    'convert', 'print', 'install', 'uninstall', 'register', 'unregister',
    'sign', 'confirm', 'transition', 'make', 'perform', 'and', 'then',
  };

  /// [writeWords] and their forms: s, es, d, ed, ing, er, ers, and with
  /// the last letter twice (setting, dropped).
  static final Set<String> _writeForms = {
    for (final w in writeWords) ...{
      w,
      for (final end in const ['s', 'es', 'd', 'ed', 'ing', 'er', 'ers']) ...{
        '$w$end',
        '${w.substring(0, w.length - 1)}$end',
        '$w${w[w.length - 1]}$end',
      },
    },
  };

  static final _toolChars = RegExp(r'^[A-Za-z0-9_-]+$');
  static final _camel = RegExp('(?<=[a-z0-9])(?=[A-Z])');
  static final _split = RegExp(r'[^a-z0-9]+');

  /// The words of [text], lower case.
  static List<String> words(String text) => [
    for (final w in text.replaceAll(_camel, '_').toLowerCase().split(_split))
      if (w.isNotEmpty) w,
  ];

  /// [name] is an MCP tool that only reads. With [server], the name must be
  /// a tool of that server, and the words of the server name may come
  /// first (`gmail_search_messages` of "claude.ai Gmail").
  static bool isReadTool(String name, {String? server}) {
    if (!name.startsWith('mcp__')) return false;
    final String tool;
    if (server != null) {
      final prefix = '${serverRule(server)}__';
      if (!name.startsWith(prefix)) return false;
      tool = name.substring(prefix.length);
    } else {
      final rest = name.substring('mcp__'.length);
      final cut = rest.indexOf('__');
      if (cut <= 0) return false;
      tool = rest.substring(cut + 2);
    }
    if (!_toolChars.hasMatch(tool)) return false;
    final all = words(tool);
    if (all.any(_writeForms.contains)) return false;
    final skip = server == null ? const <String>{} : words(server).toSet();
    final verb = all.skipWhile(skip.contains).firstOrNull;
    return verb != null && readVerbs.contains(verb);
  }
}
