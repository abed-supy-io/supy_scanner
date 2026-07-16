/// Pure-Dart comparator for perfgate benchmarks. No Flutter imports so this
/// module is unit-testable on the CI host without a device.
library;

import 'dart:convert';

/// Maximum allowed p95 regression vs. baseline before perfgate fails the run.
/// Locked at 15% per `docs/PLAN.md §6` and the V1-S2-07 ticket.
const double kP95RegressionTolerance = 0.15;

/// Single metric sample emitted by `example/integration_test/perf_bench_test.dart`
/// as a `BENCH_RESULT { ... }` line.
class BenchSample {
  const BenchSample({
    required this.metric,
    required this.runs,
    required this.min,
    required this.max,
    required this.p50,
    required this.p95,
  });

  factory BenchSample.fromJson(Map<String, Object?> json) => BenchSample(
        metric: json['metric']! as String,
        runs: (json['runs'] as num).toInt(),
        min: (json['min'] as num?)?.toInt() ?? 0,
        max: (json['max'] as num?)?.toInt() ?? 0,
        p50: (json['p50'] as num).toInt(),
        p95: (json['p95'] as num).toInt(),
      );

  final String metric;
  final int runs;
  final int min;
  final int max;
  final int p50;
  final int p95;

  Map<String, Object?> toJson() => <String, Object?>{
        'metric': metric,
        'runs': runs,
        'min': min,
        'max': max,
        'p50': p50,
        'p95': p95,
      };
}

/// Verdict for a single metric.
enum CompareStatus {
  /// Metric is within tolerance of the baseline p95.
  ok,

  /// Metric exceeds baseline p95 by more than [kP95RegressionTolerance].
  regressed,

  /// No baseline exists for this metric — record-only outcome.
  noBaseline,
}

class CompareResult {
  const CompareResult({
    required this.metric,
    required this.status,
    required this.observedP95,
    required this.baselineP95,
    required this.deltaPct,
  });

  final String metric;
  final CompareStatus status;
  final int observedP95;
  final int? baselineP95;
  final double? deltaPct;

  Map<String, Object?> toJson() => <String, Object?>{
        'metric': metric,
        'status': status.name,
        'observedP95': observedP95,
        'baselineP95': baselineP95,
        'deltaPct': deltaPct,
      };
}

/// Parses the captured stdout of a perf bench run into structured samples
/// plus a detected device tier. Unknown / missing tier returns `'unknown'`.
({String tier, List<BenchSample> samples}) parseBenchStream(String stdout) {
  String tier = 'unknown';
  final samples = <BenchSample>[];
  for (final line in const LineSplitter().convert(stdout)) {
    final tierIdx = line.indexOf('BENCH_TIER ');
    if (tierIdx >= 0) {
      final payload =
          _extractJson(line.substring(tierIdx + 'BENCH_TIER '.length));
      if (payload != null) {
        final t = payload['tier'];
        if (t is String && t.isNotEmpty) tier = t;
      }
      continue;
    }
    final resIdx = line.indexOf('BENCH_RESULT ');
    if (resIdx >= 0) {
      final payload =
          _extractJson(line.substring(resIdx + 'BENCH_RESULT '.length));
      if (payload != null) samples.add(BenchSample.fromJson(payload));
    }
  }
  return (tier: tier, samples: samples);
}

Map<String, Object?>? _extractJson(String tail) {
  final start = tail.indexOf('{');
  if (start < 0) return null;
  final raw = tail.substring(start);
  try {
    return jsonDecode(raw) as Map<String, Object?>;
  } on FormatException {
    return null;
  }
}

/// Compares each [observed] sample against its baseline. A sample whose p95
/// exceeds the baseline p95 by more than [kP95RegressionTolerance] is marked
/// [CompareStatus.regressed]. Missing baselines yield [CompareStatus.noBaseline].
List<CompareResult> compareAgainstBaselines({
  required List<BenchSample> observed,
  required Map<String, BenchSample> baselines,
  double tolerance = kP95RegressionTolerance,
}) {
  final results = <CompareResult>[];
  for (final s in observed) {
    final base = baselines[s.metric];
    if (base == null) {
      results.add(CompareResult(
        metric: s.metric,
        status: CompareStatus.noBaseline,
        observedP95: s.p95,
        baselineP95: null,
        deltaPct: null,
      ));
      continue;
    }
    final baseP95 = base.p95;
    final delta = baseP95 == 0 ? 0.0 : (s.p95 - baseP95) / baseP95;
    results.add(CompareResult(
      metric: s.metric,
      status: delta > tolerance ? CompareStatus.regressed : CompareStatus.ok,
      observedP95: s.p95,
      baselineP95: baseP95,
      deltaPct: delta,
    ));
  }
  return results;
}

/// True if any result is [CompareStatus.regressed]. `noBaseline` does NOT fail
/// the gate — it's surfaced in the report so the operator can decide whether
/// to record a new baseline via `tools/perfgate/regen-baselines.dart`.
bool hasRegression(List<CompareResult> results) =>
    results.any((r) => r.status == CompareStatus.regressed);
