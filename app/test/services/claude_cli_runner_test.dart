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
    test('PATH gets the folder of claude and the system folders', () {
      final r = ClaudeCliRunner(
        environment: {'HOME': '/Users/ann', 'PATH': '/usr/bin:/custom'},
        windows: false,
      );
      expect(r.runEnvironment('/Users/ann/.local/bin/claude'), {
        'PATH':
            '/Users/ann/.local/bin:/usr/bin:/custom:/bin:/usr/sbin:/sbin:'
            '/opt/homebrew/bin:/usr/local/bin',
      });
    });

    test('Windows: the folder of claude goes first, with ;', () {
      final r = ClaudeCliRunner(
        environment: {'Path': r'C:\Windows'},
        windows: true,
      );
      expect(r.runEnvironment(r'C:\Users\ann\.local\bin\claude.exe'), {
        'Path': r'C:\Users\ann\.local\bin;C:\Windows',
      });
    });
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

    test('the null runner has no claude', () async {
      expect(await NullAgentRunner().locate(), isNull);
    });
  }, skip: Platform.isWindows ? _posixOnly : null);
}
