// Covers the two exit-contract escapes fixed in run_bench.dart:
//  1. malformed/missing tag JSON in harness stdout must raise
//     HarnessException (mapped to exit 2), never a raw FormatException.
//  2. a subprocess that fails to even launch (missing binary) must also
//     surface as exit 2 with a harness message, not a raw stack trace +
//     exit 255. That path is exercised end-to-end via the compiled driver
//     in the second group below, since it depends on Process.start
//     behavior that isn't meaningfully unit-testable in isolation.
import 'dart:io';

import 'package:test/test.dart';

import '../lib/harness_io.dart';

void main() {
  group('parseJsonLine', () {
    test('malformed JSON after the tag throws HarnessException', () {
      const output = 'noise\nDSQ_DETECT {"detected":tru';
      expect(
        () => parseJsonLine(output, 'DSQ_DETECT'),
        throwsA(isA<HarnessException>()),
      );
    });

    test('malformed JSON HarnessException message includes the line', () {
      const output = 'DSQ_DETECT {"detected":tru';
      try {
        parseJsonLine(output, 'DSQ_DETECT');
        fail('expected HarnessException');
      } on HarnessException catch (e) {
        expect(e.message, contains('DSQ_DETECT'));
        expect(e.message, contains(output));
      }
    });

    test('missing tag line throws HarnessException (not silently null)', () {
      const output = 'some other harness output\nno tag here';
      expect(
        () => parseJsonLine(output, 'DSQ_DETECT'),
        throwsA(isA<HarnessException>()),
      );
    });

    test('well-formed tag line still parses (no regression)', () {
      const output = 'chatter\nDSQ_DETECT {"detected":true,"quad":[1,2]}\ntail';
      final json = parseJsonLine(output, 'DSQ_DETECT');
      expect(json['detected'], true);
      expect(json['quad'], [1, 2]);
    });
  });

  group('run_bench.dart end-to-end exit contract', () {
    // Mirrors a real corpus scene into an isolated repo-shaped temp dir
    // (tools/bench/run_bench.dart + lib/ + pubspec + .dart_tool copied over,
    // bench/corpus/<scene> copied over) but WITHOUT a build/dsq-bench
    // directory. --skip-build then makes the driver try to launch
    // build/dsq-bench/bench_detect, which doesn't exist in the mirror, so
    // Process.run throws ProcessException — the exact escape Finding 2
    // describes. The real worktree already has bench_detect built, so this
    // mirror is the cheapest reliable way to force that failure without
    // touching the shared build output.
    late Directory mirrorRoot;

    setUp(() {
      mirrorRoot = Directory.systemTemp.createTempSync('dsq_bench_it_');
    });

    tearDown(() {
      if (mirrorRoot.existsSync()) mirrorRoot.deleteSync(recursive: true);
    });

    void copyDir(Directory from, Directory to) {
      to.createSync(recursive: true);
      for (final entity in from.listSync()) {
        final name = entity.uri.pathSegments.where((p) => p.isNotEmpty).last;
        if (entity is Directory) {
          copyDir(entity, Directory('${to.path}/$name'));
        } else if (entity is File) {
          entity.copySync('${to.path}/$name');
        }
      }
    }

    test('missing build binary → exit 2, harness message, no scratch leak',
        () async {
      final realBenchDir = Directory('${Directory.current.path}/../../bench');
      final realCorpusScene =
          Directory('${realBenchDir.path}/corpus/seed-001');
      expect(realCorpusScene.existsSync(), isTrue,
          reason: 'fixture scene bench/corpus/seed-001 must exist');

      // Mirror tools/bench (script + lib + pubspec + resolved packages, via
      // the already-present .dart_tool/package_config.json) so `dart run`
      // resolves package:image without a network pub get.
      final mirrorBench = Directory('${mirrorRoot.path}/tools/bench');
      copyDir(Directory(Directory.current.path), mirrorBench);
      // Don't carry over any previous report/baselines output from the
      // real tree — irrelevant to this test and just extra copy weight.
      for (final stale in ['report', 'baselines']) {
        final d = Directory('${mirrorBench.path}/$stale');
        if (d.existsSync()) d.deleteSync(recursive: true);
      }

      // Mirror just the one corpus scene the driver needs for --suite
      // detect. Deliberately no build/dsq-bench under mirrorRoot.
      copyDir(realCorpusScene,
          Directory('${mirrorRoot.path}/bench/corpus/seed-001'));

      final tempPrefix =
          '${Directory.systemTemp.path}${Platform.pathSeparator}dsq_bench';
      List<FileSystemEntity> scratchLeaks() => Directory.systemTemp
          .listSync()
          .where((e) => e.path.startsWith(tempPrefix))
          .toList();
      final before = scratchLeaks().length;

      final result = await Process.run(
        Platform.resolvedExecutable,
        [
          'run',
          '${mirrorBench.path}/run_bench.dart',
          '--suite', 'detect',
          '--skip-build',
          '--skip-ocr',
          '--corpus', 'bench/corpus',
        ],
      );

      expect(result.exitCode, 2,
          reason: 'stdout: ${result.stdout}\nstderr: ${result.stderr}');
      expect(result.stderr, contains('[bench]'));
      expect(result.stderr, isNot(contains('Unhandled exception')));
      expect(result.stderr, isNot(contains('#0      ')));

      final after = scratchLeaks();
      expect(after.length, before,
          reason: 'scratch dir(s) leaked: $after');
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}
