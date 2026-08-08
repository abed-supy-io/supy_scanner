import 'package:flutter/material.dart';
import 'package:supy_scanner/supy_scanner.dart';

import '../demo_scaffold.dart';

/// Full-screen batch capture: `SupyBarcodeScanner.startMultiple` pushes the
/// native/branded multi-scan UI and returns a deduplicated
/// `SupyBatchBarcodeResult` once the user finishes.
class BatchScanDemo extends StatefulWidget {
  const BatchScanDemo({super.key});

  @override
  State<BatchScanDemo> createState() => _BatchScanDemoState();
}

class _BatchScanDemoState extends State<BatchScanDemo> {
  SupyBatchBarcodeResult? _result;
  String? _error;
  bool _running = false;

  Future<void> _scan({int maxBatchCount = 0}) async {
    setState(() {
      _running = true;
      _error = null;
    });
    try {
      final result = await SupyBarcodeScanner.startMultiple(
        context,
        options: SupyBatchBarcodeScanOptions(maxBatchCount: maxBatchCount),
      );
      if (!mounted) return;
      setState(() => _result = result);
    } on SupyScanError catch (e) {
      if (e.code == SupyScanErrorCode.cancelled) {
        // Cancelling is a normal path — don't render as an error.
        setState(() {});
      } else {
        setState(() => _error = '${e.code.name}: ${e.message}');
      }
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _result?.items ?? const <SupyBarcode>[];
    return DemoScaffold(
      title: 'Batch scan',
      description:
          'Scan many codes in one uninterrupted session. The scanner suppresses '
          'a code re-seen within a short cooldown, tracks duplicates, and hands '
          'back the unique set when the user is done — optionally capped at a '
          'fixed count.',
      apiSummary:
          'SupyBarcodeScanner.startMultiple(context, '
          'options: SupyBatchBarcodeScanOptions(maxBatchCount:)) '
          '→ SupyBatchBarcodeResult(items, duplicateCount)',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _running ? null : () => _scan(),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Unlimited'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: _running ? null : () => _scan(maxBatchCount: 5),
                  icon: const Icon(Icons.numbers),
                  label: const Text('Cap at 5'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_result != null)
            Text(
              'Unique: ${items.length}  ·  Duplicates suppressed: '
              '${_result!.duplicateCount}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
          const SizedBox(height: 8),
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'Tap a button above to start a batch session.\n'
                'The same code re-scanned within the cooldown is dropped.',
                textAlign: TextAlign.center,
              ),
            )
          else
            for (final (i, b) in items.indexed)
              ListTile(
                dense: true,
                leading: CircleAvatar(child: Text('${i + 1}')),
                title: Text(b.rawValue),
                subtitle: Text(b.format.wireName),
              ),
        ],
      ),
    );
  }
}
