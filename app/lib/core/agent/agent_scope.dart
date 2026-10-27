import 'dart:convert';

/// The folder of the agent (ADR 0008).
///
/// - Each chat has its own folder, `<dataDir>/Agent workspace/<chat id>/`.
///   `claude` runs in it, may change files only in it, and the folder stays
///   after the run so the person can open what the agent made.
/// - The files the person linked are copied into its `inputs/` folder.
/// - Before and after each run the folder is checked ([audit]): links,
///   odd entries and the files Claude Code would load as settings
///   (`.mcp.json`, `.claude/`, `CLAUDE.md`, `CLAUDE.local.md`) are removed,
///   so a run cannot plant a tool or a rule for the next one.
/// - [settingsProblem] checks the Claude Code settings of the person: a run
///   that loads them must not get file tools or folders from them.
///
/// Pure Dart: the store and the runner do the reading and writing.
abstract final class AgentScope {
  /// The name of the folder of all the agent folders, in the data folder.
  static const rootName = 'Agent workspace';

  /// The folder of the linked files in the folder of a chat.
  static const inputs = 'inputs';

  /// The most files a folder may have, and the most bytes.
  static const maxFiles = 500;
  static const maxBytes = 200 * 1024 * 1024;

  static const tooBig =
      'The agent folder of this chat has more than 500 files or 200 MB. '
      'Delete some of its files, then try again.';

  static final _id = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
    r'[0-9a-fA-F]{12}$',
  );

  /// [id] is a uuid, the only name a chat folder may have.
  static bool isId(String id) => _id.hasMatch(id);

  static String _trim(String path, String sep) {
    var p = path;
    while (p.length > 1 && p.endsWith(sep)) {
      p = p.substring(0, p.length - 1);
    }
    return p;
  }

  /// The folder of all the agent folders.
  static String root(String dataDir, {String sep = '/'}) =>
      '${_trim(dataDir, sep)}$sep$rootName';

  /// The folder of the chat [id], or null when [id] is not a uuid.
  static String? folder(String dataDir, String id, {String sep = '/'}) =>
      isId(id) ? '${root(dataDir, sep: sep)}$sep$id' : null;

  /// The parts of [path], without `.` and empty parts (the first one stays:
  /// it tells an absolute path). Null when a part is `..`.
  static List<String>? _parts(String path, String sep) {
    final out = <String>[];
    for (final (i, p) in path.split(sep).indexed) {
      if (p == '..') return null;
      if (p == '.' || (p.isEmpty && i > 0)) continue;
      out.add(p);
    }
    return out;
  }

  /// [path] is under [root], and not [root] itself. A path with `..` is
  /// never inside.
  static bool isInside(String root, String path, {String sep = '/'}) {
    final r = _parts(root, sep), p = _parts(path, sep);
    if (r == null || p == null || r.isEmpty || p.length <= r.length) {
      return false;
    }
    for (var i = 0; i < r.length; i++) {
      if (r[i] != p[i]) return false;
    }
    return true;
  }

  /// The names Claude Code loads from the folder it runs in. Never in an
  /// agent folder, in any case (a Mac disk does not tell case apart).
  static const _loaded = {
    '.mcp.json',
    '.claude',
    'claude.md',
    'claude.local.md',
  };

  /// What to remove from a folder, and what it has: [entries] are its
  /// entries, with paths relative to it and `/` between parts, each folder
  /// before what is in it.
  static AgentAudit audit(List<AgentEntry> entries) {
    final remove = <String>[], files = <String>[];
    var count = 0, bytes = 0;
    for (final e in entries) {
      if (remove.any((r) => e.path.startsWith('$r/'))) continue;
      final name = e.path.split('/').last;
      if (e.kind == AgentEntryKind.link ||
          e.kind == AgentEntryKind.other ||
          _loaded.contains(name.toLowerCase())) {
        remove.add(e.path);
        continue;
      }
      if (e.kind != AgentEntryKind.file) continue;
      count++;
      bytes += e.bytes;
      if (e.path.split('/').first != inputs) files.add(e.path);
    }
    files.sort();
    return AgentAudit(files: files, remove: remove, count: count, bytes: bytes);
  }

  /// The kinds of files Grove opens for the person: plain text only. Any
  /// other file the agent made shows in the Finder, never runs.
  static const _plain = {'md', 'markdown', 'txt', 'csv', 'tsv', 'json'};

  static bool canOpen(String name) {
    final dot = name.lastIndexOf('.');
    if (dot <= 0) return false;
    return _plain.contains(name.substring(dot + 1).toLowerCase());
  }

  /// The tools that reach files. Allowed by name in the settings of the
  /// person, they would reach files outside the folder.
  static const _fileTools = {
    'Read',
    'Write',
    'Edit',
    'MultiEdit',
    'Glob',
    'Grep',
    'NotebookEdit',
    'NotebookRead',
    'LS',
  };

  /// Why the Claude Code settings file [name] with the text [text] (null:
  /// no file) must not load in a run with services, or null when it may.
  ///
  /// It must not allow a file tool, a whole MCP server or a wildcard, add
  /// folders, or turn on the MCP servers of a project folder. A file that
  /// does not read as settings is a problem too: better safe.
  static String? settingsProblem(String name, String? text) {
    if (text == null) return null;
    String problem(String what) =>
        '$name $what. Then the agent could reach more than its own folder '
        'and the tools you turned on. Change that file, or turn off "Use my '
        'services".';
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException {
      return 'Grove could not read $name. Fix that file, or turn off "Use '
          'my services".';
    }
    if (json is! Map<String, Object?>) {
      return 'Grove could not read $name. Fix that file, or turn off "Use '
          'my services".';
    }
    final perms = json['permissions'];
    if (perms is Map<String, Object?>) {
      if (perms['allow'] case final List<Object?> allow) {
        for (final rule in allow.whereType<String>()) {
          final tool = rule.split('(').first.trim();
          final server =
              tool.startsWith('mcp__') &&
              (!tool.substring(5).contains('__') || tool.endsWith('__'));
          if (_fileTools.contains(tool) || tool.contains('*') || server) {
            return problem('allows "${rule.trim()}"');
          }
        }
      }
      if (perms['additionalDirectories'] case final List<Object?> dirs
          when dirs.isNotEmpty) {
        return problem('adds the folders ${dirs.join(', ')}');
      }
    }
    if (json['enableAllProjectMcpServers'] == true) {
      return problem('turns on the MCP servers of every folder');
    }
    if (json['enabledMcpjsonServers'] case final List<Object?> s
        when s.isNotEmpty) {
      return problem('turns on the MCP servers ${s.join(', ')}');
    }
    return null;
  }
}

enum AgentEntryKind { file, folder, link, other }

/// One entry of an agent folder, for [AgentScope.audit].
class AgentEntry {
  const AgentEntry(this.path, this.kind, [this.bytes = 0]);

  /// Relative to the folder, with `/` between parts.
  final String path;
  final AgentEntryKind kind;
  final int bytes;
}

/// What [AgentScope.audit] found.
class AgentAudit {
  const AgentAudit({
    required this.files,
    required this.remove,
    required this.count,
    required this.bytes,
  });

  /// The files the agent made (not the inputs), sorted.
  final List<String> files;

  /// The entries to remove, in the order they came.
  final List<String> remove;

  /// The files that stay, inputs too, and their bytes.
  final int count;
  final int bytes;

  bool get overCap =>
      count > AgentScope.maxFiles || bytes > AgentScope.maxBytes;
}
