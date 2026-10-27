import 'dart:convert';

import 'mcp_tool_rules.dart';

/// One MCP server of the person, as the probe found it (ADR 0008).
class AgentService {
  const AgentService({
    required this.name,
    required this.status,
    this.readTools = const [],
    this.otherTools = const [],
    this.clash = false,
  });

  /// The name `claude` gives it, like "claude.ai Gmail".
  final String name;

  /// "connected", "needs-auth", "failed", "disabled" or "pending".
  final String status;

  /// Its tools that only read ([McpToolRules.isReadTool]).
  final List<String> readTools;

  /// Its other tools. Never allowed.
  final List<String> otherTools;

  /// Another server has the same rule ([McpToolRules.serverRule]), so
  /// Grove cannot tell their tools apart. Never usable.
  final bool clash;

  /// The agent can use it: connected, with a read tool, and no clash.
  bool get usable => status == 'connected' && !clash && readTools.isNotEmpty;

  /// [status] in plain words.
  static String statusText(String status) => switch (status) {
    'connected' => 'Connected',
    'needs-auth' => 'Needs sign-in',
    'failed' => 'Failed to start',
    'disabled' => 'Off in Claude Code',
    'pending' => 'Starting',
    _ => status,
  };

  Map<String, Object?> toJson() => {
    'name': name,
    'status': status,
    'read': readTools,
    'other': otherTools,
    if (clash) 'clash': true,
  };

  static AgentService? fromJson(Object? json) {
    if (json case {
      'name': final String name,
      'status': final String status,
      'read': final List<Object?> read,
      'other': final List<Object?> other,
    }) {
      return AgentService(
        name: name,
        status: status,
        readTools: read.whereType<String>().toList(),
        otherTools: other.whereType<String>().toList(),
        clash: json['clash'] == true,
      );
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is AgentService &&
      other.name == name &&
      other.status == status &&
      _same(other.readTools, readTools) &&
      _same(other.otherTools, otherTools) &&
      other.clash == clash;

  @override
  int get hashCode => Object.hash(
    name,
    status,
    Object.hashAll(readTools),
    Object.hashAll(otherTools),
    clash,
  );
}

bool _same<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// The MCP servers of the person and their tools, read from the `init`
/// event of the probe (ADR 0008).
class AgentServices {
  const AgentServices({
    this.servers = const [],
    this.strayTools = const [],
    this.ready = true,
  });

  final List<AgentService> servers;

  /// `mcp__` tools of no server. Never allowed.
  final List<String> strayTools;

  /// Every server had stopped starting: the lists are whole.
  final bool ready;

  AgentService? server(String name) {
    for (final s in servers) {
      if (s.name == name) return s;
    }
    return null;
  }

  /// The statuses of a server that has stopped starting.
  static const _settled = {'connected', 'needs-auth', 'failed', 'disabled'};

  /// Reads the `init` event, the first line of the probe. Null when the
  /// line is not that event. Built-in tools are left out. A tool goes to
  /// the server with the longest rule it starts with.
  static AgentServices? parseInit(String line) {
    final Object? json;
    try {
      json = jsonDecode(line);
    } on FormatException {
      return null;
    }
    if (json is! Map<String, Object?> ||
        json['type'] != 'system' ||
        json['subtype'] != 'init') {
      return null;
    }
    var ready = true;
    final named = <(String, String)>[];
    if (json['mcp_servers'] case final List<Object?> list) {
      for (final s in list) {
        final name = s is Map<String, Object?> ? s['name'] : null;
        final status = s is Map<String, Object?> ? s['status'] : null;
        if (name is! String ||
            name.isEmpty ||
            status is! String ||
            !_settled.contains(status)) {
          ready = false;
        }
        if (name is String && name.isNotEmpty) {
          named.add((name, status is String ? status : ''));
        }
      }
    }
    final rules = [for (final (n, _) in named) McpToolRules.serverRule(n)];
    final clash = [
      for (final r in rules) rules.where((x) => x == r).length > 1,
    ];
    final read = [for (final _ in named) <String>[]];
    final other = [for (final _ in named) <String>[]];
    final stray = <String>[];
    final tools = json['tools'];
    for (final t in tools is List<Object?> ? tools : const <Object?>[]) {
      if (t is! String || !t.startsWith('mcp__')) continue;
      var best = -1;
      for (final (i, r) in rules.indexed) {
        if (t.startsWith('${r}__') &&
            (best < 0 || r.length > rules[best].length)) {
          best = i;
        }
      }
      if (best < 0) {
        stray.add(t);
      } else if (!clash[best] &&
          McpToolRules.isReadTool(t, server: named[best].$1)) {
        read[best].add(t);
      } else {
        other[best].add(t);
      }
    }
    return AgentServices(
      servers: [
        for (final (i, (name, status)) in named.indexed)
          AgentService(
            name: name,
            status: status,
            readTools: read[i],
            otherTools: other[i],
            clash: clash[i],
          ),
      ],
      strayTools: stray,
      ready: ready,
    );
  }

  Map<String, Object?> toJson() => {
    'servers': [for (final s in servers) s.toJson()],
    'stray': strayTools,
    'ready': ready,
  };

  /// What [toJson] wrote. Null for anything else.
  static AgentServices? fromJson(Object? json) {
    if (json case {
      'servers': final List<Object?> list,
      'stray': final List<Object?> stray,
    }) {
      final servers = <AgentService>[];
      for (final s in list) {
        final service = AgentService.fromJson(s);
        if (service == null) return null;
        servers.add(service);
      }
      return AgentServices(
        servers: servers,
        strayTools: stray.whereType<String>().toList(),
        ready: json['ready'] != false,
      );
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is AgentServices &&
      _same(other.servers, servers) &&
      _same(other.strayTools, strayTools) &&
      other.ready == ready;

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(servers), Object.hashAll(strayTools), ready);
}
