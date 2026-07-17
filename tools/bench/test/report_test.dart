import 'package:test/test.dart';

import '../lib/report.dart';

SceneResult scene(String id, String lighting,
        {bool labelHasDoc = true,
        bool? detected,
        double? iou,
        OutputMetrics? ours,
        OutputMetrics? scanbot}) =>
    SceneResult(
        id: id,
        docType: 'receipt',
        lighting: lighting,
        labelHasDoc: labelHasDoc,
        detected: detected,
        iou: iou,
        ours: ours,
        scanbot: scanbot);

void main() {
  test('aggregate computes rates, means, and per-lighting breakdown', () {
    final results = [
      scene('a', 'good',
          detected: true,
          iou: 0.9,
          ours: OutputMetrics(
              sharpness: 100, uniformity: 0.9, dpi: 300, cer: 0.1),
          scanbot: OutputMetrics(
              sharpness: 80, uniformity: 0.8, dpi: null, cer: 0.2)),
      scene('b', 'dim', detected: false, iou: null),
      scene('c', 'good', labelHasDoc: false, detected: true),
    ];
    final s = aggregate(results);
    expect(s.scenes, 3);
    expect(s.metrics['detect_rate'], closeTo(0.5, 1e-9)); // 1 of 2 labeled
    expect(s.metrics['mean_iou'], closeTo(0.45, 1e-9)); // (0.9 + 0) / 2
    expect(s.metrics['false_positive_rate'], closeTo(1.0, 1e-9)); // 1 of 1
    expect(s.metrics['ours_sharpness'], closeTo(100, 1e-9));
    expect(s.metrics['ours_cer'], closeTo(0.1, 1e-9));
    expect(s.metrics['scanbot_sharpness'], closeTo(80, 1e-9));
    expect(s.metrics.containsKey('scanbot_dpi'), isFalse);
    expect(s.perLighting['good']!['detect_rate'], closeTo(1.0, 1e-9));
    expect(s.perLighting['dim']!['detect_rate'], closeTo(0.0, 1e-9));
  });

  test('summary JSON round-trips', () {
    final s = aggregate([scene('a', 'good', detected: true, iou: 0.8)]);
    final back = BenchSummary.fromJson(s.toJson());
    expect(back.scenes, s.scenes);
    expect(back.metrics, s.metrics);
    expect(back.perLighting, s.perLighting);
  });

  test('gate flags direction-aware regressions beyond 2%', () {
    final base = BenchSummary(scenes: 1, metrics: {
      'mean_iou': 0.80,
      'ours_cer': 0.10,
      'scanbot_sharpness': 500.0,
    }, perLighting: {});
    final observed = BenchSummary(scenes: 1, metrics: {
      'mean_iou': 0.76, // -5% on higher-is-better → regressed
      'ours_cer': 0.11, // +10% on lower-is-better → regressed
      'scanbot_sharpness': 100.0, // reference metric → never gated
    }, perLighting: {});
    final results = gate(observed, base);
    expect(results.where((r) => r.regressed).map((r) => r.metric).toSet(),
        {'mean_iou', 'ours_cer'});
    expect(results.any((r) => r.metric == 'scanbot_sharpness'), isFalse);
  });

  test('gate passes small movements within tolerance', () {
    final base = BenchSummary(
        scenes: 1, metrics: {'mean_iou': 0.80}, perLighting: {});
    final observed = BenchSummary(
        scenes: 1, metrics: {'mean_iou': 0.79}, perLighting: {}); // -1.25%
    expect(gate(observed, base).single.regressed, isFalse);
  });

  test('renderMarkdown includes scoreboard and deltas', () {
    final s = aggregate([
      scene('a', 'good',
          detected: true,
          iou: 0.9,
          ours: OutputMetrics(
              sharpness: 100, uniformity: 0.9, dpi: 300, cer: 0.1))
    ]);
    final md = renderMarkdown(s, {'scanbot': s});
    expect(md, contains('# DSQ bench report'));
    expect(md, contains('mean_iou'));
    expect(md, contains('Δ vs scanbot'));
    expect(md, contains('## Per-lighting'));
  });
}
