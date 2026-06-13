// Perf bench harness for supy_scanner.
//
// Targets (see docs/QA.md §Performance targets):
//   - QR cold-detect p50 < 300 ms, p95 < 800 ms (Moto G Power)
//   - Preview cold start < 400 ms (Pixel 8)
//   - Batch 20-barcode session < 30 s
//   - 10-page OCR end-to-end < 12 s (iPhone SE 3)
//
// What runs unattended:
//   - Preview cold-start timing — fully automatable.
//   - QR cold-detect timing — automatable IF a QR is held in front of the
//     device; otherwise the operator presents the code and the harness records.
//   - Batch 20 — operator-driven (sweep across the torture sheet).
//   - 10-page OCR — operator-driven through the document UI; harness times
//     only the `scanDocument` future round-trip.
//
// All scenarios print BENCH_RESULT JSON lines so the QA.md table can be
// filled in by grepping the test output.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:supy_scanner/supy_scanner.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Preview cold start latency', (tester) async {
    const runs = 20;
    final samples = <int>[];

    for (var i = 0; i < runs; i++) {
      final completer = Completer<Duration>();
      final stopwatch = Stopwatch()..start();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SupyBarcodeScannerView(
              onPreviewStarted: (_) {
                if (!completer.isCompleted) {
                  completer.complete(stopwatch.elapsed);
                }
              },
            ),
          ),
        ),
      );

      final elapsed = await completer.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => const Duration(seconds: 5),
      );
      samples.add(elapsed.inMilliseconds);

      // Tear down before next iteration.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }

    _report('preview_cold_start_ms', samples);
  }, timeout: const Timeout(Duration(minutes: 3)),);

  testWidgets('QR cold-detect latency (operator presents code)',
      (tester) async {
    const runs = 50;
    final samples = <int>[];

    for (var i = 0; i < runs; i++) {
      final detected = Completer<Duration>();
      final stopwatch = Stopwatch();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SupyBarcodeScannerView(
              onPreviewStarted: (_) => stopwatch.start(),
              onBarcodeDetected: (_) {
                if (!detected.isCompleted) {
                  detected.complete(stopwatch.elapsed);
                }
              },
            ),
          ),
        ),
      );

      final elapsed = await detected.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () => const Duration(seconds: 10),
      );
      samples.add(elapsed.inMilliseconds);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }

    _report('qr_cold_detect_ms', samples);
  }, timeout: const Timeout(Duration(minutes: 15)),);

  testWidgets('Batch 20-barcode session wall clock', (tester) async {
    final stopwatch = Stopwatch()..start();
    final result = await SupyScannerChannel.instance.scanBarcodesBatch(
      const SupyBatchBarcodeScanOptions(maxBatchCount: 20),
    );
    stopwatch.stop();

    _report('batch20_ms', [stopwatch.elapsedMilliseconds]);
    expect(result, isNotNull);
  }, timeout: const Timeout(Duration(minutes: 5)),);

  testWidgets('10-page document scan end-to-end', (tester) async {
    final stopwatch = Stopwatch()..start();
    final result = await SupyScannerChannel.instance.scanDocument(
      const SupyDocumentScanOptions(maxPages: 10),
    );
    stopwatch.stop();

    _report('doc10_ms', [stopwatch.elapsedMilliseconds]);
    expect(result, isNotNull);
  }, timeout: const Timeout(Duration(minutes: 5)),);
}

void _report(String metric, List<int> samples) {
  samples.sort();
  int pct(double p) {
    if (samples.isEmpty) return 0;
    final idx = ((samples.length - 1) * p).round();
    return samples[idx];
  }

  final payload = <String, Object?>{
    'metric': metric,
    'runs': samples.length,
    'min': samples.isEmpty ? null : samples.first,
    'max': samples.isEmpty ? null : samples.last,
    'p50': pct(0.50),
    'p95': pct(0.95),
  };
  // The 'BENCH_RESULT ' prefix is what the operator greps for.
  // ignore: avoid_print
  print('BENCH_RESULT ${jsonEncode(payload)}');
}
