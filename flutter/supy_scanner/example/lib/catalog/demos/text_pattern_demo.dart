import 'package:flutter/material.dart';
import 'package:supy_scanner/supy_scanner.dart';

import '../demo_scaffold.dart';

/// Live "generic data capture": run regex patterns over the OCR stream and
/// collect hits. Scanbot's text-pattern feature, on-device and pure Dart.
class TextPatternDemo extends StatefulWidget {
  const TextPatternDemo({super.key});

  @override
  State<TextPatternDemo> createState() => _TextPatternDemoState();
}

class _TextPatternDemoState extends State<TextPatternDemo> {
  final List<SupyTextPatternMatch> _matches = [];

  static final List<SupyTextPattern> _patterns = [
    SupyTextPattern.email(),
    SupyTextPattern.url(),
    const SupyTextPattern(
      name: 'sku',
      pattern: r'\b[A-Z]{3}-\d{4,6}\b',
      caseSensitive: false,
    ),
  ];

  void _onMatch(SupyTextPatternMatch match) {
    if (!mounted) return;
    setState(() => _matches.insert(0, match));
  }

  @override
  Widget build(BuildContext context) {
    return DemoScaffold(
      title: 'Text pattern capture',
      description:
          'Point the camera at any text. Three patterns run per frame — email, '
          'URL, and a SKU shape (ABC-12345) — and every hit streams back with '
          'its bounding box, debounced per value. Patterns are pure-Dart '
          'regex, evaluated on-device.',
      apiSummary:
          'SupyTextPatternScannerView(patterns: [SupyTextPattern.email(), …], '
          'onMatch: (SupyTextPatternMatch m) {})',
      fullBleed: true,
      child: Stack(
        fit: StackFit.expand,
        children: [
          SupyTextPatternScannerView(
            patterns: _patterns,
            languages: const ['en'],
            onMatch: _onMatch,
            footer:
                _matches.isEmpty
                    ? null
                    : Container(
                      color: Colors.black.withValues(alpha: 0.78),
                      padding: const EdgeInsets.all(12),
                      constraints: const BoxConstraints(maxHeight: 160),
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          for (final m in _matches.take(6))
                            Text(
                              '${m.patternName}: ${m.value}',
                              style: const TextStyle(color: Colors.white),
                            ),
                        ],
                      ),
                    ),
          ),
        ],
      ),
    );
  }
}
