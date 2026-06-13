import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:supy_scanner/supy_scanner.dart';

void main() {
  runApp(const SupyScannerExampleApp());
}

class SupyScannerExampleApp extends StatelessWidget {
  const SupyScannerExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'supy_scanner example',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF6448C3),
      ),
      home: const _Home(),
    );
  }
}

class _Home extends StatelessWidget {
  const _Home();

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('supy_scanner'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Embedded', icon: Icon(Icons.qr_code_scanner)),
              Tab(text: 'Batch', icon: Icon(Icons.dynamic_feed)),
              Tab(text: 'Document', icon: Icon(Icons.document_scanner)),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _EmbeddedBarcodeTab(),
            _BatchBarcodeTab(),
            _DocumentTab(),
          ],
        ),
      ),
    );
  }
}

class _EmbeddedBarcodeTab extends StatefulWidget {
  const _EmbeddedBarcodeTab();

  @override
  State<_EmbeddedBarcodeTab> createState() => _EmbeddedBarcodeTabState();
}

class _EmbeddedBarcodeTabState extends State<_EmbeddedBarcodeTab> {
  final SupyBarcodeScannerController _controller =
      SupyBarcodeScannerController();
  SupyBarcode? _last;
  bool _torchOn = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        SupyBarcodeScannerView(
          controller: _controller,
          onBarcodeDetected: (b) => setState(() => _last = b),
        ),
        Positioned(
          top: 16,
          right: 16,
          child: FloatingActionButton.small(
            heroTag: 'torch',
            onPressed: () async {
              await _controller.setTorch(on: !_torchOn);
              setState(() => _torchOn = !_torchOn);
            },
            child: Icon(_torchOn ? Icons.flash_on : Icons.flash_off),
          ),
        ),
        if (_last != null)
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: Card(
              color: Colors.black.withValues(alpha: 0.78),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  '${_last!.format.wireName}\n${_last!.rawValue}',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _BatchBarcodeTab extends StatefulWidget {
  const _BatchBarcodeTab();

  @override
  State<_BatchBarcodeTab> createState() => _BatchBarcodeTabState();
}

class _BatchBarcodeTabState extends State<_BatchBarcodeTab> {
  SupyBatchBarcodeResult? _result;
  String? _error;
  bool _running = false;

  Future<void> _scan({int maxBatchCount = 0}) async {
    setState(() {
      _running = true;
      _error = null;
    });
    try {
      final result = await SupyScannerChannel.instance.scanBarcodesBatch(
        SupyBatchBarcodeScanOptions(
          maxBatchCount: maxBatchCount,
        ),
      );
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
    return Padding(
      padding: const EdgeInsets.all(16),
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
          Expanded(
            child: items.isEmpty
                ? const Center(
                    child: Text(
                      'Tap a button above to start a batch session.\n'
                      'Same code re-scanned within 800ms is dropped.',
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final b = items[i];
                      return ListTile(
                        leading: CircleAvatar(child: Text('${i + 1}')),
                        title: Text(b.rawValue),
                        subtitle: Text(b.format.wireName),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _DocumentTab extends StatefulWidget {
  const _DocumentTab();

  @override
  State<_DocumentTab> createState() => _DocumentTabState();
}

class _DocumentTabState extends State<_DocumentTab> {
  SupyDocumentData? _result;
  String? _error;
  bool _running = false;

  Future<void> _scan({int maxPages = 0}) async {
    setState(() {
      _running = true;
      _error = null;
    });
    try {
      final result = await SupyScannerChannel.instance.scanDocument(
        SupyDocumentScanOptions(maxPages: maxPages),
      );
      setState(() => _result = result);
    } on SupyScanError catch (e) {
      if (e.code == SupyScanErrorCode.cancelled) {
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
    final pages = _result?.pages ?? const <SupyDocumentPage>[];
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _running ? null : () => _scan(),
                  icon: const Icon(Icons.document_scanner),
                  label: const Text('Scan (no limit)'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: _running ? null : () => _scan(maxPages: 3),
                  icon: const Icon(Icons.filter_3),
                  label: const Text('Max 3 pages'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_result != null)
            Text(
              'Pages: ${pages.length}  ·  OCR chars: ${_result!.ocrText.length}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
          const SizedBox(height: 8),
          Expanded(
            child: pages.isEmpty
                ? const Center(child: Text('No scan yet.'))
                : ListView(
                    children: [
                      SizedBox(
                        height: 180,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: pages.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(width: 8),
                          itemBuilder: (_, i) {
                            final page = pages[i];
                            final file = File(Uri.parse(page.uri).toFilePath());
                            return ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: file.existsSync()
                                  ? Image.file(file, fit: BoxFit.cover)
                                  : Container(
                                      width: 120,
                                      color: Colors.grey.shade300,
                                      alignment: Alignment.center,
                                      child: Text('Page ${i + 1}'),
                                    ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_result!.ocrText.isNotEmpty)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(_result!.ocrText),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
