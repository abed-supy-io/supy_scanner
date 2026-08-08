import 'package:flutter/material.dart';
import 'package:supy_scanner/supy_scanner.dart';

import '../demo_scaffold.dart';

/// Launches the full-screen, Supy-branded [SupyDocumentScannerScreen] — the
/// Scanbot-parity document session: solid brand bars, a live quad-tracking
/// overlay with a colour-coded status band, an in-bar auto-capture toggle, and
/// a multi-page review grid. The screen never pops itself; this demo wires
/// [onComplete] / [onCancel] to [Navigator.pop].
class BrandedDocumentDemo extends StatefulWidget {
  const BrandedDocumentDemo({super.key});

  @override
  State<BrandedDocumentDemo> createState() => _BrandedDocumentDemoState();
}

class _BrandedDocumentDemoState extends State<BrandedDocumentDemo> {
  List<SupyDocumentPage> _pages = const [];

  Future<void> _launch(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    await navigator.push<void>(
      MaterialPageRoute(
        builder:
            (_) => SupyDocumentScannerScreen(
              onComplete: (pages) {
                navigator.maybePop();
                setState(() => _pages = pages);
                messenger.showSnackBar(
                  SnackBar(content: Text('Scanned ${pages.length} page(s)')),
                );
              },
              onCancel: navigator.maybePop,
              onError:
                  (e) => messenger.showSnackBar(
                    SnackBar(content: Text('Error: ${e.message}')),
                  ),
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DemoScaffold(
      title: 'Branded document scanner',
      description:
          'The full-screen Scanbot-parity document session: solid brand bars, '
          'a live green/red edge overlay, an auto-capture toggle, gallery '
          'import, and a multi-page review grid.',
      apiSummary: 'SupyDocumentScannerScreen(onComplete:, onCancel:)',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton.icon(
            onPressed: () => _launch(context),
            icon: const Icon(Icons.document_scanner),
            label: const Text('Launch document scanner'),
          ),
          const SizedBox(height: 24),
          if (_pages.isEmpty)
            Text(
              'No pages yet. Launch the scanner and capture a document.',
              style: Theme.of(context).textTheme.bodyMedium,
            )
          else ...[
            Text(
              'Last session: ${_pages.length} page(s)',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            for (var i = 0; i < _pages.length; i++)
              Card(
                child: ListTile(
                  leading: CircleAvatar(child: Text('${i + 1}')),
                  title: Text('Page ${i + 1}'),
                  subtitle: Text('${_pages[i].width} × ${_pages[i].height} px'),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
