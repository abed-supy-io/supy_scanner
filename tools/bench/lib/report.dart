// Aggregation + report rendering + regression gate for the DSQ bench.
// The gate implements the program-wide rule from the DSQ spec: no metric
// regresses by more than ±2% (direction-aware) vs the pinned baseline.

class OutputMetrics {
  OutputMetrics(
      {required this.sharpness, required this.uniformity, this.dpi, this.cer});

  final double sharpness;
  final double uniformity;
  final double? dpi;
  final double? cer;
}

class SceneResult {
  SceneResult({
    required this.id,
    required this.docType,
    required this.lighting,
    required this.labelHasDoc,
    this.detected,
    this.iou,
    this.ours,
    this.scanbot,
  });

  final String id;
  final String docType;
  final String lighting;
  final bool labelHasDoc;
  final bool? detected;
  final double? iou;
  final OutputMetrics? ours;
  final OutputMetrics? scanbot;
}

class BenchSummary {
  BenchSummary(
      {required this.scenes, required this.metrics, required this.perLighting});

  final int scenes;
  final Map<String, double> metrics;
  final Map<String, Map<String, double>> perLighting;

  Map<String, Object?> toJson() => {
        'scenes': scenes,
        'metrics': metrics,
        'perLighting': perLighting,
      };

  static BenchSummary fromJson(Map<String, Object?> json) => BenchSummary(
        scenes: json['scenes'] as int,
        metrics: (json['metrics'] as Map).map(
            (k, v) => MapEntry(k as String, (v as num).toDouble())),
        perLighting: (json['perLighting'] as Map).map((k, v) => MapEntry(
            k as String,
            (v as Map)
                .map((k2, v2) => MapEntry(k2 as String, (v2 as num).toDouble())))),
      );
}

double? _mean(Iterable<double> values) {
  final list = values.toList();
  if (list.isEmpty) return null;
  return list.reduce((a, b) => a + b) / list.length;
}

Map<String, double> _detectionMetrics(List<SceneResult> results) {
  final labeled = results.where((r) => r.labelHasDoc).toList();
  final negatives = results.where((r) => !r.labelHasDoc).toList();
  final m = <String, double>{};
  if (labeled.isNotEmpty) {
    m['detect_rate'] =
        labeled.where((r) => r.detected == true).length / labeled.length;
    m['mean_iou'] = labeled
            .map((r) => (r.detected == true ? (r.iou ?? 0.0) : 0.0))
            .reduce((a, b) => a + b) /
        labeled.length;
  }
  if (negatives.isNotEmpty) {
    m['false_positive_rate'] =
        negatives.where((r) => r.detected == true).length / negatives.length;
  }
  return m;
}

Map<String, double> _outputMetrics(
    List<SceneResult> results, String prefix, OutputMetrics? Function(SceneResult) pick) {
  final m = <String, double>{};
  void put(String key, double? Function(OutputMetrics) f) {
    final mean = _mean(results
        .map(pick)
        .whereType<OutputMetrics>()
        .map(f)
        .whereType<double>());
    if (mean != null) m['${prefix}_$key'] = mean;
  }

  put('sharpness', (o) => o.sharpness);
  put('uniformity', (o) => o.uniformity);
  put('dpi', (o) => o.dpi);
  put('cer', (o) => o.cer);
  return m;
}

BenchSummary aggregate(List<SceneResult> results) {
  final metrics = <String, double>{
    ..._detectionMetrics(results),
    ..._outputMetrics(results, 'ours', (r) => r.ours),
    ..._outputMetrics(results, 'scanbot', (r) => r.scanbot),
  };
  final perLighting = <String, Map<String, double>>{};
  final lightings = results.map((r) => r.lighting).toSet().toList()..sort();
  for (final lighting in lightings) {
    final subset = results.where((r) => r.lighting == lighting).toList();
    perLighting[lighting] = {
      ..._detectionMetrics(subset),
      ..._outputMetrics(subset, 'ours', (r) => r.ours),
    };
  }
  return BenchSummary(
      scenes: results.length, metrics: metrics, perLighting: perLighting);
}

/// Metrics where a smaller number is better.
const kLowerIsBetter = {'ours_cer', 'false_positive_rate'};

/// Metrics eligible for gating (scanbot_* are reference-only).
bool _gated(String metric) => !metric.startsWith('scanbot_');

class GateResult {
  GateResult(
      {required this.metric,
      required this.observed,
      required this.baseline,
      required this.deltaPct,
      required this.regressed});

  final String metric;
  final double observed;
  final double baseline;
  final double deltaPct;
  final bool regressed;
}

List<GateResult> gate(BenchSummary observed, BenchSummary baseline,
    {double tolerancePct = 2.0}) {
  final results = <GateResult>[];
  for (final entry in observed.metrics.entries) {
    if (!_gated(entry.key)) continue;
    final base = baseline.metrics[entry.key];
    if (base == null || base == 0) continue;
    final deltaPct = (entry.value - base) / base * 100.0;
    final worsePct =
        kLowerIsBetter.contains(entry.key) ? deltaPct : -deltaPct;
    results.add(GateResult(
      metric: entry.key,
      observed: entry.value,
      baseline: base,
      deltaPct: deltaPct,
      regressed: worsePct > tolerancePct,
    ));
  }
  return results;
}

String _fmt(double v) => v.toStringAsFixed(4);

String renderMarkdown(
    BenchSummary summary, Map<String, BenchSummary> baselines) {
  final buf = StringBuffer()
    ..writeln('# DSQ bench report')
    ..writeln()
    ..writeln('Scenes: ${summary.scenes}')
    ..writeln()
    ..writeln('## Scoreboard')
    ..writeln();
  final baselineNames = baselines.keys.toList()..sort();
  buf.write('| metric | value |');
  for (final name in baselineNames) {
    buf.write(' Δ vs $name |');
  }
  buf
    ..writeln()
    ..write('|---|---|');
  for (final _ in baselineNames) {
    buf.write('---|');
  }
  buf.writeln();
  final keys = summary.metrics.keys.toList()..sort();
  for (final key in keys) {
    final value = summary.metrics[key]!;
    buf.write('| $key | ${_fmt(value)} |');
    for (final name in baselineNames) {
      final base = baselines[name]!.metrics[key];
      if (base == null || base == 0) {
        buf.write(' n/a |');
      } else {
        final delta = (value - base) / base * 100.0;
        buf.write(' ${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(1)}% |');
      }
    }
    buf.writeln();
  }
  buf
    ..writeln()
    ..writeln('## Per-lighting')
    ..writeln();
  final allKeys = <String>{
    for (final m in summary.perLighting.values) ...m.keys
  }.toList()
    ..sort();
  buf.write('| lighting |');
  for (final k in allKeys) {
    buf.write(' $k |');
  }
  buf
    ..writeln()
    ..write('|---|');
  for (final _ in allKeys) {
    buf.write('---|');
  }
  buf.writeln();
  final lightings = summary.perLighting.keys.toList()..sort();
  for (final lighting in lightings) {
    buf.write('| $lighting |');
    for (final k in allKeys) {
      final v = summary.perLighting[lighting]![k];
      buf.write(v == null ? ' — |' : ' ${_fmt(v)} |');
    }
    buf.writeln();
  }
  return buf.toString();
}
