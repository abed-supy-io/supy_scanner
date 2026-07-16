import 'package:supy_scanner_perfgate/baseline_compare.dart';
import 'package:test/test.dart';

BenchSample _sample(String metric, int p95) => BenchSample(
      metric: metric,
      runs: 10,
      min: 0,
      max: p95,
      p50: p95 ~/ 2,
      p95: p95,
    );

void main() {
  group('parseBenchStream', () {
    test('extracts tier + samples from interleaved stdout', () {
      const stdout = '''
[trace] starting
00:00 +0: setUpAll
BENCH_TIER {"tier":"low"}
00:00 +1: preview cold start
BENCH_RESULT {"metric":"preview_cold_start_ms","runs":20,"min":120,"max":900,"p50":300,"p95":700}
BENCH_RESULT {"metric":"qr_cold_detect_ms","runs":50,"min":80,"max":850,"p50":250,"p95":600}
All tests passed!
''';
      final parsed = parseBenchStream(stdout);
      expect(parsed.tier, 'low');
      expect(parsed.samples, hasLength(2));
      expect(parsed.samples.first.metric, 'preview_cold_start_ms');
      expect(parsed.samples.first.p95, 700);
    });

    test('returns unknown tier and empty samples on empty input', () {
      final parsed = parseBenchStream('');
      expect(parsed.tier, 'unknown');
      expect(parsed.samples, isEmpty);
    });

    test('ignores malformed BENCH_RESULT lines', () {
      const stdout = 'BENCH_RESULT not-json-here\nBENCH_TIER also-not-json\n';
      final parsed = parseBenchStream(stdout);
      expect(parsed.tier, 'unknown');
      expect(parsed.samples, isEmpty);
    });
  });

  group('compareAgainstBaselines', () {
    test('within tolerance => ok', () {
      final results = compareAgainstBaselines(
        observed: [_sample('qr_cold_detect_ms', 110)],
        baselines: {'qr_cold_detect_ms': _sample('qr_cold_detect_ms', 100)},
      );
      expect(results, hasLength(1));
      expect(results.single.status, CompareStatus.ok);
      expect(results.single.deltaPct, closeTo(0.10, 1e-9));
    });

    test('exactly at tolerance => ok', () {
      final results = compareAgainstBaselines(
        observed: [_sample('m', 115)],
        baselines: {'m': _sample('m', 100)},
      );
      expect(results.single.status, CompareStatus.ok);
    });

    test('over tolerance => regressed', () {
      final results = compareAgainstBaselines(
        observed: [_sample('m', 130)],
        baselines: {'m': _sample('m', 100)},
      );
      expect(results.single.status, CompareStatus.regressed);
      expect(hasRegression(results), isTrue);
    });

    test('missing baseline => noBaseline (does not fail the gate)', () {
      final results = compareAgainstBaselines(
        observed: [_sample('newly_added_metric', 999)],
        baselines: const {},
      );
      expect(results.single.status, CompareStatus.noBaseline);
      expect(hasRegression(results), isFalse);
    });

    test('mixed: ok + regressed + missing => hasRegression true', () {
      final results = compareAgainstBaselines(
        observed: [
          _sample('ok_metric', 105),
          _sample('bad_metric', 200),
          _sample('new_metric', 50),
        ],
        baselines: {
          'ok_metric': _sample('ok_metric', 100),
          'bad_metric': _sample('bad_metric', 100),
        },
      );
      expect(results.map((r) => r.status), <CompareStatus>[
        CompareStatus.ok,
        CompareStatus.regressed,
        CompareStatus.noBaseline,
      ]);
      expect(hasRegression(results), isTrue);
    });

    test('baseline p95 = 0 treats delta as zero (no false positive)', () {
      final results = compareAgainstBaselines(
        observed: [_sample('m', 0)],
        baselines: {'m': _sample('m', 0)},
      );
      expect(results.single.status, CompareStatus.ok);
      expect(results.single.deltaPct, 0.0);
    });
  });
}
