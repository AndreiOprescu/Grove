// The real door to `claude` (ADR 0004), with small system programs in its
// place: /bin/cat gives back its input, /bin/pwd shows its folder, and
// /bin/sleep runs until it is stopped. No shell is used.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:grove/core/agent/agent_policy.dart';
import 'package:grove/core/agent/agent_runner.dart';
import 'package:grove/services/claude_cli_runner.dart';

import '../data/helpers.dart' show tempDir;

const _posixOnly = 'Mac and Linux programs';

void main() {
  group('locate', () {
    late Directory home;

    setUp(() => home = tempDir('grove-home-'));

    ClaudeCliRunner runner({List<String> systemPaths = const []}) =>
        ClaudeCliRunner(
          environment: {'HOME': home.path, 'PATH': '/usr/bin'},
          windows: false,
          systemPaths: systemPaths,
        );

    File claudeIn(String dir, {bool executable = true}) {
      Directory(dir).createSync(recursive: true);
      final f = File('$dir/claude')..writeAsStringSync('');
      if (executable) Process.runSync('chmod', ['+x', f.path]);
      return f;
    }

    test('finds claude in ~/.local/bin', () async {
      final f = claudeIn('${home.path}/.local/bin');
      expect(await runner().locate(), f.path);
    }, skip: Platform.isWindows ? _posixOnly : null);

    test('null when claude is in no known place', () async {
      expect(await runner().locate(), isNull);
    });

    test('a file that cannot run, or a folder, does not count', () async {
      claudeIn('${home.path}/.local/bin', executable: false);
      Directory('${home.path}/other/claude').createSync(recursive: true);
      expect(
        await runner(systemPaths: ['${home.path}/other/claude']).locate(),
        isNull,
      );
    }, skip: Platform.isWindows ? _posixOnly : null);

    test('the next known place when the home folder has none', () async {
      final f = claudeIn('${home.path}/brew/bin');
      expect(await runner(systemPaths: [f.path]).locate(), f.path);
    }, skip: Platform.isWindows ? _posixOnly : null);

    test('the known places: never the PATH', () {
      final mac = ClaudeCliRunner(
        environment: {'HOME': '/Users/ann', 'PATH': '/somewhere/bin'},
        windows: false,
      );
      expect(mac.candidates, [
        '/Users/ann/.local/bin/claude',
        '/opt/homebrew/bin/claude',
        '/usr/local/bin/claude',
      ]);
      final pc = ClaudeCliRunner(
        environment: {'USERPROFILE': r'C:\Users\ann'},
        windows: true,
      );
      // Only the .exe: a .cmd file would need a shell.
      expect(pc.candidates, [r'C:\Users\ann\.local\bin\claude.exe']);
    });
  });

  group('the environment of a run', () {
    test('only the few names a program needs; PATH gets the folder of '
        'claude and the system folders', () {
      final r = ClaudeCliRunner(
        environment: {
          'HOME': '/Users/ann',
          'USER': 'ann',
          'LANG': 'en_GB.UTF-8',
          'PATH': '/usr/bin:/custom',
          'ANTHROPIC_API_KEY': 'secret',
          'AWS_SECRET_ACCESS_KEY': 'secret',
          'GITHUB_TOKEN': 'secret',
        },
        windows: false,
      );
      expect(r.runEnvironment('/Users/ann/.local/bin/claude'), {
        'HOME': '/Users/ann',
        'USER': 'ann',
        'LANG': 'en_GB.UTF-8',
        'PATH':
            '/Users/ann/.local/bin:/usr/bin:/custom:/bin:/usr/sbin:/sbin:'
            '/opt/homebrew/bin:/usr/local/bin',
      });
    });

    test('Windows: the folders of the profile, and the folder of claude '
        'first in the path, with ;', () {
      final r = ClaudeCliRunner(
        environment: {
          'Path': r'C:\Windows',
          'USERPROFILE': r'C:\Users\ann',
          'APPDATA': r'C:\Users\ann\AppData\Roaming',
          'SystemRoot': r'C:\Windows',
          'GITHUB_TOKEN': 'secret',
        },
        windows: true,
      );
      expect(r.runEnvironment(r'C:\Users\ann\.local\bin\claude.exe'), {
        'USERPROFILE': r'C:\Users\ann',
        'APPDATA': r'C:\Users\ann\AppData\Roaming',
        'SystemRoot': r'C:\Windows',
        'Path': r'C:\Users\ann\.local\bin;C:\Windows',
      });
    });

    test('the process gets that and nothing of this app', () async {
      final r = ClaudeCliRunner(
        environment: {
          'HOME': '/tmp',
          'PATH': '/usr/bin',
          'GROVE_SECRET': 'secret',
        },
        windows: false,
      );
      final out = await r
          .start(
            '/usr/bin/env',
            const [],
            stdin: '',
            timeout: const Duration(seconds: 20),
          )
          .done;
      final names = {
        for (final l in out.stdout.split('\n'))
          if (l.contains('=')) l.substring(0, l.indexOf('=')),
      };
      expect(names, containsAll(['HOME', 'PATH']));
      expect(names.difference(ClaudeCliRunner.keptNames.toSet()), isEmpty);
      expect(out.stdout, isNot(contains('secret')));
    }, skip: Platform.isWindows ? _posixOnly : null);
  });

  group('start', () {
    final runner = ClaudeCliRunner(killWait: const Duration(seconds: 1));

    test('writes stdin and reads stdout', () async {
      final out = await runner
          .start(
            '/bin/cat',
            const [],
            stdin: 'Héllo agent\nline two',
            timeout: const Duration(seconds: 20),
          )
          .done;
      expect(out.exitCode, 0);
      expect(out.stdout, 'Héllo agent\nline two');
      expect(out.timedOut, isFalse);
      expect(out.cancelled, isFalse);
    });

    test('runs in the folder of the chat, made when missing, and keeps '
        'it', () async {
      final root = tempDir('grove-ws-');
      final folder = '${root.path}/chat';
      final out = await runner
          .start(
            '/bin/pwd',
            const [],
            stdin: 'ignored',
            timeout: const Duration(seconds: 20),
            folder: folder,
          )
          .done;
      expect(out.stdout.trim(), Directory(folder).resolveSymbolicLinksSync());
      expect(Directory(folder).existsSync(), isTrue);
      expect(out.files, isEmpty);
      expect(out.folderProblem, isNull);
    });

    test('the linked files go to inputs/; the files the agent made are '
        'listed', () async {
      final root = tempDir('grove-ws-');
      final folder = '${root.path}/chat';
      final linked = File('${root.path}/plan.txt')..writeAsStringSync('plan');
      final out = await runner
          .start(
            '/bin/sh',
            const [
              '-c',
              'cat inputs/plan.txt > notes.md; mkdir d; echo x > d/b.txt',
            ],
            stdin: '',
            timeout: const Duration(seconds: 20),
            folder: folder,
            files: [AgentFile(path: linked.path, name: 'plan.txt')],
          )
          .done;
      expect(out.exitCode, 0);
      expect(File('$folder/inputs/plan.txt').readAsStringSync(), 'plan');
      expect(File('$folder/notes.md').readAsStringSync(), 'plan');
      expect(out.files, ['d/b.txt', 'notes.md']);
    });

    test('links and files Claude Code would load are removed, before the run '
        'and after it', () async {
      final root = tempDir('grove-ws-');
      final folder = Directory('${root.path}/chat')..createSync();
      File('${folder.path}/.mcp.json').writeAsStringSync('{}');
      Link('${folder.path}/home').createSync(root.path);
      final out = await runner
          .start(
            '/bin/sh',
            const [
              '-c',
              'ls -a; ln -s / root; mkdir .claude; echo x > CLAUDE.md; '
                  'echo ok > ok.md',
            ],
            stdin: '',
            timeout: const Duration(seconds: 20),
            folder: folder.path,
          )
          .done;
      // The run did not see them.
      expect(out.stdout, isNot(contains('.mcp.json')));
      expect(out.stdout, isNot(contains('home')));
      final left = [for (final e in folder.listSync()) e.path.split('/').last];
      expect(left, ['ok.md']);
      expect(out.files, ['ok.md']);
      // The link was removed, not what it points to.
      expect(root.existsSync(), isTrue);
    });

    test('too much output stops the run', () async {
      final small = ClaudeCliRunner(
        killWait: const Duration(milliseconds: 300),
        maxOutput: 100000,
      );
      final out = await small
          .start(
            '/usr/bin/yes',
            const [],
            stdin: '',
            timeout: const Duration(seconds: 20),
          )
          .done;
      expect(out.overflow, isTrue);
      expect(out.stdout.length, lessThanOrEqualTo(100000));
    });

    test('runs in a new empty temp folder, deleted at the end', () async {
      final out = await runner
          .start(
            '/bin/pwd',
            const [],
            stdin: 'ignored',
            timeout: const Duration(seconds: 20),
          )
          .done;
      final dir = out.stdout.trim();
      expect(dir.split('/').last, startsWith('grove-agent-'));
      expect(Directory(dir).existsSync(), isFalse);
    });

    test('stops at its time limit', () async {
      final watch = Stopwatch()..start();
      final out = await runner
          .start(
            '/bin/sleep',
            const ['30'],
            stdin: '',
            timeout: const Duration(milliseconds: 200),
          )
          .done;
      expect(out.timedOut, isTrue);
      expect(out.cancelled, isFalse);
      expect(watch.elapsed, lessThan(const Duration(seconds: 10)));
    });

    test('cancel stops it; a second cancel does nothing', () async {
      final p = runner.start(
        '/bin/sleep',
        const ['30'],
        stdin: '',
        timeout: const Duration(seconds: 20),
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));
      p
        ..cancel()
        ..cancel();
      final out = await p.done;
      expect(out.cancelled, isTrue);
      expect(out.timedOut, isFalse);
    });

    test('cancel stops the processes it started too, also one that '
        'ignores SIGTERM', () async {
      // A shell in the place of claude: it starts a second shell that
      // ignores SIGTERM, and that one starts sleep (which ignores it too),
      // like claude starts its MCP servers. The second line is the pid of
      // sleep.
      const script =
          '/bin/sh -c \'trap "" TERM; /bin/sleep 30 & echo \$!; wait\' & '
          'echo \$!; wait';
      final p = runner.start(
        '/bin/sh',
        const ['-c', script],
        stdin: '',
        timeout: const Duration(seconds: 20),
      );
      await Future<void>.delayed(const Duration(milliseconds: 500));
      p.cancel();
      final out = await p.done;
      expect(out.cancelled, isTrue);
      final pids = ClaudeCliRunner.parsePids(out.stdout);
      expect(pids, hasLength(2));
      Future<bool> alive(int pid) async =>
          (await Process.run('/bin/kill', ['-0', '$pid'])).exitCode == 0;
      for (
        var i = 0;
        i < 50 && (await Future.wait(pids.map(alive))).any((a) => a);
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      for (final pid in pids) {
        expect(await alive(pid), isFalse, reason: 'pid $pid');
      }
    });

    test('the pids of pgrep: one a line, others left out', () {
      expect(ClaudeCliRunner.parsePids('123\n 456 \n\nabc\n-1\n0\n'), [
        123,
        456,
      ]);
      expect(ClaudeCliRunner.parsePids(''), isEmpty);
    });

    test('a program that does not exist: an output, not a throw', () async {
      final out = await runner
          .start(
            '/no/such/claude',
            const [],
            stdin: '',
            timeout: const Duration(seconds: 5),
          )
          .done;
      expect(out.exitCode, -1);
      expect(out.stdout, isEmpty);
      expect(out.stderr, isNotEmpty);
    });

    test('the probe gives the first line and stops the process', () async {
      // cat prints the probe prompt back as its first line.
      final line = await runner.probeInit('/bin/cat', const []);
      expect(line, AgentPolicy.probePrompt);
    });

    test('a probe that prints nothing gives null', () async {
      final quick = ClaudeCliRunner(
        probeTimeout: const Duration(milliseconds: 300),
        killWait: const Duration(milliseconds: 300),
      );
      expect(await quick.probeInit('/bin/sleep', const ['30']), isNull);
      expect(await quick.probeInit('/no/such/claude', const []), isNull);
    });

    test('the null runner has no claude, no services and no problem', () async {
      expect(await NullAgentRunner().settingsProblem(), isNull);
      expect(await NullAgentRunner().listServices('/no/claude'), isNull);
      expect(await NullAgentRunner().locate(), isNull);
    });
  }, skip: Platform.isWindows ? _posixOnly : null);

  group('the Claude Code settings of the person', () {
    late Directory home;
    late ClaudeCliRunner runner;

    setUp(() {
      home = tempDir('grove-home-');
      Directory('${home.path}/.claude').createSync();
      runner = ClaudeCliRunner(
        environment: {'HOME': home.path, 'USERPROFILE': home.path},
      );
    });

    test('no settings files: fine', () async {
      Directory('${home.path}/.claude').deleteSync();
      expect(await runner.settingsProblem(), isNull);
    });

    test('rules that do not reach files: fine', () async {
      File('${home.path}/.claude/settings.json')
          .writeAsStringSync('{"permissions": {"allow": ["WebSearch"]}}');
      expect(await runner.settingsProblem(), isNull);
    });

    test('a file tool allowed in settings.json or settings.local.json is a '
        'problem that names the file', () async {
      File(
        '${home.path}/.claude/settings.local.json',
      ).writeAsStringSync('{"permissions": {"allow": ["Read(//Users/**)"]}}');
      expect(await runner.settingsProblem(), contains('settings.local.json'));
      File(
        '${home.path}/.claude/settings.json',
      ).writeAsStringSync('{"permissions": {"additionalDirectories": ["/"]}}');
      expect(await runner.settingsProblem(), contains('settings.json'));
    });
  });
}
