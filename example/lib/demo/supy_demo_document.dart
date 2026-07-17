import 'package:flutter/material.dart';
import 'package:supy_scanner/supy_scanner.dart';

import '../branding/supy_brand.dart';
import 'widgets/supy_document_review.dart';

class SupyDemoDocumentPage extends StatefulWidget {
  const SupyDemoDocumentPage({super.key});

  @override
  State<SupyDemoDocumentPage> createState() => _SupyDemoDocumentPageState();
}

class _SupyDemoDocumentPageState extends State<SupyDemoDocumentPage> {
  SupyDocumentData? _result;
  String? _error;
  bool _running = false;

  Future<void> _scan() async {
    setState(() {
      _running = true;
      _error = null;
    });
    try {
      final r = await SupyScannerChannel.instance.scanDocument(
        const SupyDocumentScanOptions(),
      );
      if (!mounted) return;
      setState(() => _result = r);
    } on SupyScanError catch (e) {
      if (!mounted) return;
      if (e.code != SupyScanErrorCode.cancelled) {
        setState(() => _error = e.message);
      }
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: SupyBrand.theme(),
      child: Scaffold(
        appBar: AppBar(title: const Text('Capture Document')),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _running ? null : _scan,
                      icon: const Icon(Icons.document_scanner),
                      label: Text(_running ? 'Scanning…' : 'Capture pages'),
                    ),
                  ),
                ],
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  _error!,
                  style: const TextStyle(color: SupyBrand.critical),
                ),
              ),
            Expanded(
              child:
                  _result == null
                      ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(32),
                          child: Text(
                            'No document captured yet.\n'
                            'Tap "Capture pages" to start.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: SupyBrand.onSurfaceMuted),
                          ),
                        ),
                      )
                      : SupyDocumentReview(data: _result!),
            ),
          ],
        ),
      ),
    );
  }
}
