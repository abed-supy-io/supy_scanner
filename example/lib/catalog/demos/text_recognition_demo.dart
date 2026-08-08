import 'package:flutter/material.dart';
import 'package:supy_scanner/supy_scanner.dart';

import '../demo_scaffold.dart';

/// Standalone OCR: capture a single page, then run `recognizeText` over it and
/// render the block → line tree it returns.
class TextRecognitionDemo extends StatefulWidget {
  const TextRecognitionDemo({super.key});

  @override
  State<TextRecognitionDemo> createState() => _TextRecognitionDemoState();
}

class _TextRecognitionDemoState extends State<TextRecognitionDemo> {
  SupyRecognizedText? _text;
  String? _error;
  bool _busy = false;

  Future<void> _captureAndRecognize() async {
    setState(() {
      _busy = true;
      _error = null;
      _text = null;
    });
    try {
      final doc = await SupyScannerChannel.instance.scanDocument(
        const SupyDocumentScanOptions(maxPages: 1),
      );
      if (doc == null || doc.pages.isEmpty) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      final path = Uri.parse(doc.pages.first.uri).toFilePath();
      final recognized = await SupyScannerChannel.instance.recognizeText(
        SupyRecognizeTextOptions(imagePath: path),
      );
      if (!mounted) return;
      setState(() {
        _text = recognized;
        _busy = false;
      });
    } on SupyScanError catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '${e.code.name}: ${e.message}';
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = _text;
    return DemoScaffold(
      title: 'Text recognition (OCR)',
      description:
          'Run OCR over a captured page and get back a block → line → element '
          'tree with normalized bounding boxes — the raw recognition primitive '
          'the VIN / MRZ / pattern features build on.',
      apiSummary:
          'SupyScannerChannel.instance.recognizeText('
          'SupyRecognizeTextOptions(imagePath: …)) → SupyRecognizedText',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton.icon(
            onPressed: _busy ? null : _captureAndRecognize,
            icon: const Icon(Icons.text_snippet),
            label: Text(_busy ? 'Recognizing…' : 'Capture page & recognize'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
          if (text != null) ...[
            const SizedBox(height: 16),
            Text(
              '${text.blocks.length} block(s) · ${text.fullText.length} chars',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            for (final block in text.blocks)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final line in block.lines)
                        Text(line.text, style: const TextStyle(fontSize: 13)),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
