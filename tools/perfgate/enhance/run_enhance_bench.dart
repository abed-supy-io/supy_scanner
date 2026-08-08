// Perfgate enhance bench driver (DIE6).
//
// Builds `native/enhance/bench_enhance.cpp` via CMake with -DSUPY_BUILD_TOOLS=ON
// and runs it with `--json --tier <tier>`. The binary's stdout already matches
// the `BENCH_TIER {...}` / `BENCH_RESULT {...}` line protocol consumed by
// `tools/perfgate/lib/baseline_compare.dart` — this driver just forwards it.
//
// The plan originally specified an FFI driver against
// `lib/src/native/supy_native_core_ffi.dart`, but no Dart FFI binding for
// `supy_core_enhance` exists today (the only Dart-side bridge is the
// MethodChannel, which routes through Android/iOS native code). The host
// C++ harness already shipped with the Phase DIE design (see
// `docs/ENHANCEMENT.md` §Performance Bench), so this driver wraps it instead.
//
// Usage:
//   dart tools/perfgate/enhance/run_enhance_bench.dart --tier low
//   dart tools/perfgate/enhance/run_enhance_bench.dart --tier mid --iter 50
//
// Pipe the captured log into `tools/perfgate/run.dart --log <path>` to apply
// the regression gate against `tools/perfgate/baselines/<tier>/enhance_*.json`.

import 'dart:convert';
import 'dart:io';

const _defaultIterations = 50;
const _allowedTiers = {'low', 'mid', 'high'};

Future<void> main(List<String> argv) async {
  exitCode = await _run(argv);
}

Future<int> _run(List<String> argv) async {
  final args = _parseArgs(argv);
  final tier = args['tier'];
  if (tier == null || !_allowedTiers.contains(tier)) {
    stderr.writeln('usage: run_enhance_bench.dart --tier <low|mid|high> '
        '[--iter N] [--log <path>] [--skip-build]');
    return 2;
  }
  final iterations = int.tryParse(args['iter'] ?? '') ?? _defaultIterations;
  final logPath = args['log'];
  final skipBuild = args.containsKey('skip-build');

  final repoRoot = _repoRoot();
  final buildDir = Directory('${repoRoot.path}/build/perfgate-enhance');
  final binPath = '${buildDir.path}/bench_enhance';

  if (!skipBuild) {
    final cmakeRc = await _runCmd('cmake', [
      '-S', '${repoRoot.path}/core',
      '-B', buildDir.path,
      '-DSUPY_BUILD_TOOLS=ON',
      '-DCMAKE_BUILD_TYPE=Release',
    ]);
    if (cmakeRc != 0) return cmakeRc;

    final buildRc = await _runCmd('cmake', [
      '--build', buildDir.path,
      '--target', 'bench_enhance',
      '--config', 'Release',
    ]);
    if (buildRc != 0) return buildRc;
  }

  if (!File(binPath).existsSync()) {
    stderr.writeln('[enhance-bench] bench_enhance binary missing at $binPath');
    return 3;
  }

  stdout.writeln('[enhance-bench] running tier=$tier iter=$iterations');
  final proc = await Process.start(
    binPath,
    ['--json', '--tier', tier, '--iter', '$iterations'],
  );
  final outBuf = StringBuffer();
  proc.stdout.transform(utf8.decoder).listen((s) {
    outBuf.write(s);
    stdout.write(s);
  });
  proc.stderr.transform(utf8.decoder).listen(stderr.write);
  final rc = await proc.exitCode;
  if (rc != 0) return rc;

  if (logPath != null) {
    await File(logPath).writeAsString(outBuf.toString());
    stdout.writeln('[enhance-bench] wrote log to $logPath');
  }
  return 0;
}

Future<int> _runCmd(String exe, List<String> args) async {
  stdout.writeln('[enhance-bench] \$ $exe ${args.join(' ')}');
  final proc = await Process.start(exe, args, runInShell: true);
  proc.stdout.transform(utf8.decoder).listen(stdout.write);
  proc.stderr.transform(utf8.decoder).listen(stderr.write);
  return proc.exitCode;
}

Map<String, String> _parseArgs(List<String> argv) {
  final out = <String, String>{};
  for (var i = 0; i < argv.length; i++) {
    final a = argv[i];
    if (!a.startsWith('--')) continue;
    final name = a.substring(2);
    if (i + 1 < argv.length && !argv[i + 1].startsWith('--')) {
      out[name] = argv[++i];
    } else {
      out[name] = '';
    }
  }
  return out;
}

Directory _repoRoot() {
  var d = Directory.current;
  for (var i = 0; i < 6; i++) {
    final pubspec = File('${d.path}/pubspec.yaml');
    if (pubspec.existsSync() &&
        pubspec.readAsStringSync().contains('name: supy_scanner\n')) {
      return d;
    }
    final parent = d.parent;
    if (parent.path == d.path) break;
    d = parent;
  }
  return Directory.current;
}
