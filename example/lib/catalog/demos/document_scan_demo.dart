import 'dart:io';

import 'package:flutter/material.dart';
import 'package:supy_scanner/supy_scanner.dart';

import '../demo_scaffold.dart';

/// Full document capture: `scanDocument` drives edge-detection, perspective
/// correction and a color filter, returning cropped page images plus OCR text.
class DocumentScanDemo extends StatefulWidget {
  const DocumentScanDemo({super.key});

  @override
  State<DocumentScanDemo> createState() => _DocumentScanDemoState();
}

class _DocumentScanDemoState extends State<DocumentScanDemo> {
  SupyDocumentData? _result;
  String? _error;
  bool _running = false;
  SupyDocumentFilter _filter = SupyDocumentFilter.color;

  Future<void> _scan({int maxPages = 0}) async {
    setState(() {
      _running = true;
      _error = null;
    });
    try {
      final result = await SupyScannerChannel.instance.scanDocument(
        SupyDocumentScanOptions(maxPages: maxPages, filter: _filter),
      );
      if (!mounted) return;
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
    return DemoScaffold(
      title: 'Document scan',
      description:
          'The full document pipeline: detect page edges, correct perspective, '
          'apply a color / grayscale / B&W filter, and return each cropped page '
          'as an image plus recognized OCR text — across one or many pages.',
      apiSummary:
          'SupyScannerChannel.instance.scanDocument('
          'SupyDocumentScanOptions(maxPages:, filter: SupyDocumentFilter)) '
          '→ SupyDocumentData(pages, ocrText)',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<SupyDocumentFilter>(
                segments: const [
                  ButtonSegment(
                    value: SupyDocumentFilter.color,
                    label: Text('Color'),
                  ),
                  ButtonSegment(
                    value: SupyDocumentFilter.grayscale,
                    label: Text('Gray'),
                  ),
                  ButtonSegment(
                    value: SupyDocumentFilter.blackAndWhite,
                    label: Text('B&W'),
                  ),
                  ButtonSegment(
                    value: SupyDocumentFilter.original,
                    label: Text('Original'),
                  ),
                ],
                selected: {_filter},
                onSelectionChanged:
                    _running ? null : (s) => setState(() => _filter = s.first),
              ),
            ),
          ),
          const SizedBox(height: 8),
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
          if (pages.isNotEmpty) ...[
            SizedBox(
              height: 180,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: pages.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final page = pages[i];
                  final file = File(Uri.parse(page.uri).toFilePath());
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child:
                        file.existsSync()
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
                  child: SelectableText(_result!.ocrText),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
