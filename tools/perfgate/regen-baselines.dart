// Regenerate perfgate baselines from a bench run. Refuses to overwrite an
// existing baseline file without `--force` AND `--justification "<reason>"`,
// per the policy in tools/perfgate/README.md.
//
// Typical use:
//
//   dart tools/perfgate/regen-baselines.dart --tier low \
//       --log bench.log --force --justification "initial baseline for V1-S2-07"
//
// Reads BENCH_RESULT / BENCH_TIER lines from --log (or stdin if --stdin).
// Writes baselines/<tier>/<metric>.json and a sibling
// <metric>.justification.md.

import 'dart:convert';
import 'dart:io';

import 'lib/baseline_compare.dart';

Future<int> main(List<String> argv) async {
  final args = _parseArgs(argv);
  final tier = args['tier'];
  if (tier == null || !const ['low', 'mid', 'high'].contains(tier)) {
    stderr.writeln('regen-baselines: --tier must be one of low|mid|high');
    return 64;
  }

  final force = args.containsKey('force');
  final justification = args['justification'];

  final source = args.containsKey('stdin')
      ? await _readAllStdin()
      : (args.containsKey('log')
          ? await File(args['log']!).readAsString()
          : null);
  if (source == null) {
    stderr.writeln('regen-baselines: provide --log <path> or --stdin');
    return 64;
  }

  final parsed = parseBenchStream(source);
  if (parsed.samples.isEmpty) {
    stderr.writeln('regen-baselines: no BENCH_RESULT lines in input');
    return 65;
  }

  final repoRoot = _repoRoot();
  final outDir = Directory('${repoRoot.path}/tools/perfgate/baselines/$tier');
  outDir.createSync(recursive: true);

  var wrote = 0;
  for (final s in parsed.samples) {
    final file = File('${outDir.path}/${s.metric}.json');
    if (file.existsSync() && !force) {
      stderr.writeln('refusing to overwrite ${file.path} without --force '
          '(use `--force --justification "<reason>"`)');
      return 66;
    }
    if (file.existsSync() && (justification == null || justification.isEmpty)) {
      stderr.writeln('refusing to overwrite ${file.path}: --force requires '
          '--justification "<reason>"');
      return 66;
    }
    await file.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(s.toJson())}\n',
    );
    if (justification != null && justification.isNotEmpty) {
      final j = File('${outDir.path}/${s.metric}.justification.md');
      await j.writeAsString(
        '# ${s.metric} baseline change\n\n'
        '_Tier: ${tier}_\n\n'
        '$justification\n',
      );
    }
    wrote++;
  }
  stdout.writeln('regen-baselines: wrote $wrote baseline(s) to ${outDir.path}');
  return 0;
}

Directory _repoRoot() {
  var d = Directory.current;
  for (var i = 0; i < 6; i++) {
    final p = File('${d.path}/flutter/supy_scanner/pubspec.yaml');
    if (p.existsSync() &&
        p.readAsStringSync().contains('name: supy_scanner\n')) {
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
