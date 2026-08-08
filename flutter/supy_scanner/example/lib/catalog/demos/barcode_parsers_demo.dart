import 'package:flutter/material.dart';
import 'package:supy_scanner/supy_scanner.dart';

import '../demo_scaffold.dart';

/// Interprets decoded barcode payloads as strongly-typed documents (Wi-Fi,
/// vCard, URL, GS1, boarding pass, …) via the pure-Dart parser. Runs entirely
/// offline on canned payloads so it needs no camera.
class BarcodeParsersDemo extends StatefulWidget {
  const BarcodeParsersDemo({super.key});

  @override
  State<BarcodeParsersDemo> createState() => _BarcodeParsersDemoState();
}

class _Sample {
  const _Sample(this.label, this.raw, this.format);
  final String label;
  final String raw;
  final SupyBarcodeFormat format;
}

class _BarcodeParsersDemoState extends State<BarcodeParsersDemo> {
  static const List<_Sample> _samples = [
    _Sample('URL', 'https://supy.io/scanner', SupyBarcodeFormat.qr),
    _Sample(
      'Wi-Fi',
      'WIFI:T:WPA;S:SupyGuest;P:s3cr3tpass;H:false;;',
      SupyBarcodeFormat.qr,
    ),
    _Sample('Email', 'mailto:hello@supy.io?subject=Hi', SupyBarcodeFormat.qr),
    _Sample('Phone', 'tel:+97141234567', SupyBarcodeFormat.qr),
    _Sample(
      'vCard',
      'BEGIN:VCARD\nVERSION:3.0\nN:Doe;Jane\nFN:Jane Doe\n'
          'TEL:+97141234567\nEMAIL:jane@supy.io\nEND:VCARD',
      SupyBarcodeFormat.qr,
    ),
    _Sample(
      'GS1',
      '(01)09506000134352(17)261231(10)LOT42',
      SupyBarcodeFormat.dataMatrix,
    ),
  ];

  _Sample _selected = _samples.first;
  SupyBarcodeDocument? _parsed;
  bool _parsedOnce = false;

  void _parse() {
    final barcode = SupyBarcode(
      rawValue: _selected.raw,
      format: _selected.format,
    );
    setState(() {
      _parsed = barcode.parseDocument();
      _parsedOnce = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final parsed = _parsed;
    return DemoScaffold(
      title: 'Barcode parsers',
      description:
          'A decoded barcode is just a string until you interpret it. '
          'parseDocument() turns known payloads into typed documents — '
          'Wi-Fi credentials, contacts, URLs, GS1 application identifiers and '
          'more — or returns null so you can fall back to the raw value.',
      apiSummary:
          'SupyBarcode(rawValue: …, format: …).parseDocument() '
          '→ SupyBarcodeDocument? (SupyWifiBarcode, SupyContactBarcode, …)',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final s in _samples)
                ChoiceChip(
                  label: Text(s.label),
                  selected: _selected == s,
                  onSelected:
                      (_) => setState(() {
                        _selected = s;
                        _parsedOnce = false;
                        _parsed = null;
                      }),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(
              _selected.raw,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _parse,
            icon: const Icon(Icons.account_tree),
            label: const Text('Parse document'),
          ),
          const SizedBox(height: 16),
          if (_parsedOnce)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      parsed == null
                          ? 'Unrecognized — fall back to raw value'
                          : parsed.runtimeType.toString(),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    if (parsed != null) ...[
                      const SizedBox(height: 6),
                      SelectableText(
                        parsed.toString(),
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
