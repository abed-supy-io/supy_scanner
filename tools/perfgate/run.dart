// Perfgate runner — spawns the integration bench, parses BENCH_RESULT lines,
// compares against checked-in baselines, writes report.json, exits 1 on any
// p95 regression > 15%.
//
// Usage:
//   dart tools/perfgate/run.dart [--tier <auto|low|mid|high>] [--report <path>]
//                                 [--baselines-dir <path>] [--skip-run]
//                                 [--stdin]
//
// --skip-run reads a pre-captured log from --report-stdout=<path>; useful when
// a CI step has already run the bench and saved its log.
// --stdin reads the bench stdout from STDIN instead of spawning flutter.

import 'dart:convert';
import 'dart:io';

import 'lib/baseline_compare.dart';

const _scriptRel = 'tools/perfgate';

Future<void> main(List<String> argv) async {
  exitCode = await _run(argv);
}

Future<int> _run(List<String> argv) async {
  final args = _parseArgs(argv);

  final repoRoot = _repoRoot();
  final baselinesDir =
      args['baselines-dir'] ?? '${repoRoot.path}/$_scriptRel/baselines';
  final reportPath =
      args['report'] ?? '${repoRoot.path}/$_scriptRel/report.json';

  final String benchStdout;
  if (args.containsKey('stdin')) {
    benchStdout = await _readAllStdin();
  } else if (args.containsKey('log')) {
    benchStdout = await File(args['log']!).readAsString();
  } else {
    final exampleDir = Directory('${repoRoot.path}/example');
    stdout.writeln('[perfgate] running flutter integration bench '
        'in ${exampleDir.path}');
    final proc = await Process.start(
      'flutter',
      const [
        'test',
        'integration_test/perf_bench_test.dart',
        '--machine',
      ],
      workingDirectory: exampleDir.path,
      runInShell: true,
    );
    final outBuf = StringBuffer();
    proc.stdout.transform(utf8.decoder).listen((s) {
      outBuf.write(s);
      stdout.write(s);
    });
    proc.stderr.transform(utf8.decoder).listen(stderr.write);
    final exit = await proc.exitCode;
    benchStdout = outBuf.toString();
    if (exit != 0) {
      stderr.writeln('[perfgate] integration bench exited with code $exit');
      return exit;
    }
  }

  final parsed = parseBenchStream(benchStdout);
  final overrideTier = args['tier'];
  final tier = (overrideTier == null || overrideTier == 'auto')
      ? parsed.tier
      : overrideTier;
  stdout.writeln('[perfgate] tier=$tier samples=${parsed.samples.length}');

  if (parsed.samples.isEmpty) {
    stderr.writeln('[perfgate] no BENCH_RESULT lines found — refusing to '
        'emit a green report.');
    return 2;
  }

  final baselines = await _loadBaselines(Directory('$baselinesDir/$tier'));
  final results = compareAgainstBaselines(
    observed: parsed.samples,
    baselines: baselines,
  );

  final report = <String, Object?>{
    'tier': tier,
    'baselinesDir': baselinesDir,
    'observed': parsed.samples.map((s) => s.toJson()).toList(),
    'results': results.map((r) => r.toJson()).toList(),
    'regressed': hasRegression(results),
  };
  await File(reportPath).writeAsString(
    const JsonEncoder.withIndent('  ').convert(report),
  );
  stdout.writeln('[perfgate] wrote $reportPath');

  for (final r in results) {
    final pct = r.deltaPct == null
        ? 'n/a'
        : '${(r.deltaPct! * 100).toStringAsFixed(1)}%';
    stdout.writeln('  ${r.metric}: ${r.status.name} '
        '(observed=${r.observedP95} baseline=${r.baselineP95 ?? '-'} Δ=$pct)');
  }

  return hasRegression(results) ? 1 : 0;
}

Future<Map<String, BenchSample>> _loadBaselines(Directory dir) async {
  final out = <String, BenchSample>{};
  if (!dir.existsSync()) {
    stderr.writeln('[perfgate] baseline dir does not exist: ${dir.path} — '
        'all metrics will report noBaseline.');
    return out;
  }
  for (final entity in dir.listSync()) {
    if (entity is! File) continue;
    if (!entity.path.endsWith('.json')) continue;
    final json = jsonDecode(await entity.readAsString());
    if (json is! Map<String, Object?>) continue;
    final sample = BenchSample.fromJson(json);
    out[sample.metric] = sample;
  }
  return out;
}

Directory _repoRoot() {
  var d = Directory.current;
  for (var i = 0; i < 6; i++) {
    if (File('${d.path}/pubspec.yaml').existsSync() &&
        File('${d.path}/pubspec.yaml').readAsStringSync().contains(
              'name: supy_scanner\n',
            )) {
      return d;
    }
    final parent = d.parent;
    if (parent.path == d.path) break;
    d = parent;
  }
  return Directory.current;
}

Future<String> _readAllStdin() async {
  final buf = StringBuffer();
  await for (final chunk in stdin.transform(utf8.decoder)) {
    buf.write(chunk);
  }
  return buf.toString();
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
