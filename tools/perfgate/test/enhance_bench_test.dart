// Parser coverage for the DIE6 enhance bench output. The host C++ binary
// (`core/enhance/bench_enhance.cpp --json --tier ...`) emits one
// `BENCH_TIER` line followed by one `BENCH_RESULT` per `SupyDocumentEnhanceMode`.
// This test pins the metric naming and shape so a stray rename on either side
// fails CI before baselines drift.

import 'package:supy_scanner_perfgate/baseline_compare.dart';
import 'package:test/test.dart';

void main() {
  group('enhance bench output', () {
    // Captured from `bench_enhance --json --tier low --iter 50` (sample run).
    const stdout = '''
BENCH_TIER {"tier":"low"}
BENCH_RESULT {"metric":"enhance_off_ms","runs":50,"min":0,"max":1,"p50":0,"p95":1}
BENCH_RESULT {"metric":"enhance_fast_ms","runs":50,"min":18,"max":24,"p50":19,"p95":22}
BENCH_RESULT {"metric":"enhance_balanced_ms","runs":50,"min":42,"max":58,"p50":47,"p95":54}
BENCH_RESULT {"metric":"enhance_max_ms","runs":50,"min":78,"max":102,"p50":85,"p95":97}
''';

    test('parses all four mode samples under the low tier', () {
      final parsed = parseBenchStream(stdout);
      expect(parsed.tier, 'low');
      expect(parsed.samples.map((s) => s.metric).toList(), <String>[
        'enhance_off_ms',
        'enhance_fast_ms',
        'enhance_balanced_ms',
        'enhance_max_ms',
      ]);
      expect(parsed.samples.last.p95, 97);
    });

    test('regression gate fires on a 20% balanced slowdown', () {
      final parsed = parseBenchStream(stdout);
      final baselines = <String, BenchSample>{
        'enhance_balanced_ms': const BenchSample(
          metric: 'enhance_balanced_ms',
          runs: 50,
          min: 40,
          max: 50,
          p50: 44,
          p95: 45, // observed p95 is 54 — Δ = +20%, above the 15% gate
        ),
      };
      final results = compareAgainstBaselines(
        observed: parsed.samples,
        baselines: baselines,
      );
      final balanced = results.firstWhere(
        (r) => r.metric == 'enhance_balanced_ms',
      );
      expect(balanced.status, CompareStatus.regressed);
      expect(hasRegression(results), isTrue);
    });

    test('off mode tolerates zero baseline without divide-by-zero', () {
      // OFF can legitimately be 0–1 ms; baseline of 0 must not blow up the
      // delta math (baseline_compare.dart guards with `baseP95 == 0`).
      final parsed = parseBenchStream(stdout);
      final baselines = <String, BenchSample>{
        'enhance_off_ms': const BenchSample(
          metric: 'enhance_off_ms',
          runs: 50,
          min: 0,
          max: 0,
          p50: 0,
          p95: 0,
        ),
      };
      final results = compareAgainstBaselines(
        observed: parsed.samples.where((s) => s.metric == 'enhance_off_ms').toList(),
        baselines: baselines,
      );
      expect(results.single.status, CompareStatus.ok);
    });
  });
}
