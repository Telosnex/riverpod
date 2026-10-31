// Checks that a patch branch is "red test, then fix, then green".
//
// Usage (from the repository root, with a Flutter that resolves upstream's
// workspace, such as Flutter master):
//   dart telosnex/verify_patch.dart <patch-branch> [--base upstream/master]
//       [--flutter <path to flutter/bin>] [--timeout <seconds>]
//       [--platform <vm|chrome|...>] [--name <regexp>]
//
// --platform passes `-p` to `dart test`. Use it for a fix that only
// changes behavior on the web (dart2js). --name passes `-n`, to run only
// the patch's own tests when other tests in the same files already fail on
// upstream.
//
// The patch branch must have one commit on top of --base. The script:
// 1. Makes a temporary worktree at the patch branch.
// 2. Runs the test files that the commit adds or changes: they must pass.
// 3. Puts back the --base version of every other file in the commit (the
//    fix), and runs the same tests again: at least one must fail or time
//    out.
// It prints GREEN/RED for each run and exits 1 unless both are as expected.
import 'dart:async';
import 'dart:io';

Future<void> main(List<String> args) async {
  if (args.isEmpty || args.first.startsWith('-')) {
    stderr.writeln(
      'Usage: dart telosnex/verify_patch.dart <patch-branch> '
      '[--base upstream/master] [--flutter <flutter/bin>] [--timeout <s>]',
    );
    exit(64);
  }
  final branch = args.first;
  String option(String name, String fallback) {
    final i = args.indexOf(name);
    return i >= 0 && i + 1 < args.length ? args[i + 1] : fallback;
  }

  final base = option('--base', 'upstream/master');
  final flutterBin = option(
    '--flutter',
    '${Platform.environment['HOME']}/dev/flutter-upstream-pr/bin',
  );
  final timeout = Duration(seconds: int.parse(option('--timeout', '300')));
  final platform = option('--platform', 'vm');
  final name = option('--name', '');

  final count = await _git(['rev-list', '--count', '$base..$branch']);
  if (count != '1') {
    stderr.writeln(
      '$branch must have exactly one commit on $base (has $count).',
    );
    exit(1);
  }
  final files = (await _git(['diff', '--name-status', '$base...$branch']))
      .split('\n')
      .where((l) => l.isNotEmpty)
      .map((l) => l.split('\t'))
      .toList();
  final tests = [
    for (final f in files)
      if (f.first != 'D' && f.last.endsWith('_test.dart')) f.last,
  ];
  final fix = [
    for (final f in files)
      if (!f.last.endsWith('_test.dart') &&
          f.last.endsWith('.dart') &&
          f.last.contains('/lib/'))
        (status: f.first, path: f.last),
  ];
  if (tests.isEmpty || fix.isEmpty) {
    stderr.writeln(
      '$branch needs both test files and lib/ changes '
      '(tests: ${tests.length}, lib files: ${fix.length}).',
    );
    exit(1);
  }

  final dir = Directory.systemTemp.createTempSync('verify_patch_').path;
  await _git(['worktree', 'add', '-q', '--detach', dir, branch]);
  try {
    final byPackage = <String, List<String>>{};
    for (final t in tests) {
      final i = t.indexOf('/test/');
      byPackage
          .putIfAbsent(t.substring(0, i), () => [])
          .add(t.substring(i + 1));
    }

    stdout.writeln(
      '$branch: ${tests.length} test file(s), '
      '${fix.length} fix file(s)',
    );
    final green = await _runAll(
      dir,
      byPackage,
      flutterBin,
      timeout,
      platform,
      name,
    );
    stdout.writeln('with the fix:    ${green ? 'GREEN' : 'RED'}');

    for (final f in fix) {
      if (f.status == 'A') {
        File('$dir/${f.path}').deleteSync();
      } else {
        await _git(['-C', dir, 'checkout', base, '--', f.path]);
      }
    }
    final redPassed = await _runAll(
      dir,
      byPackage,
      flutterBin,
      timeout,
      platform,
      name,
    );
    stdout.writeln('without the fix: ${redPassed ? 'GREEN' : 'RED'}');

    final ok = green && !redPassed;
    stdout.writeln(ok ? 'OK: red, then green.' : 'NOT OK.');
    exitCode = ok ? 0 : 1;
  } finally {
    await _git(['worktree', 'remove', '--force', dir]);
  }
}

/// Runs the tests of each package. Returns whether all passed in time.
Future<bool> _runAll(
  String root,
  Map<String, List<String>> byPackage,
  String flutterBin,
  Duration timeout,
  String platform,
  String name,
) async {
  var allPassed = true;
  for (final MapEntry(key: package, value: tests) in byPackage.entries) {
    final usesFlutter = File('$root/$package/pubspec.yaml')
        .readAsStringSync()
        .contains(RegExp(r'^\s+flutter:\s*\n\s+sdk: flutter', multiLine: true));
    final exe = usesFlutter ? '$flutterBin/flutter' : '$flutterBin/dart';
    final process = await Process.start(exe, [
      'test',
      if (platform != 'vm') ...['-p', platform],
      if (name.isNotEmpty) ...['-n', name],
      ...tests,
    ], workingDirectory: '$root/$package');
    final out = StringBuffer();
    process.stdout.transform(const SystemEncoding().decoder).listen(out.write);
    process.stderr.transform(const SystemEncoding().decoder).listen(out.write);
    final code = await process.exitCode.timeout(
      timeout,
      onTimeout: () {
        process.kill(ProcessSignal.sigkill);
        out.writeln('TIMED OUT after ${timeout.inSeconds} s');
        return -1;
      },
    );
    final last = '$out'
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .lastOrNull;
    stdout.writeln(
      '  $package: exit $code, ${last?.replaceAll(RegExp('^.*: '), '')}',
    );
    if (code != 0) allPassed = false;
  }
  return allPassed;
}

Future<String> _git(List<String> args) async {
  final r = await Process.run('git', args);
  if (r.exitCode != 0) {
    throw ProcessException('git', args, '${r.stderr}', r.exitCode);
  }
  return '${r.stdout}'.trim();
}
