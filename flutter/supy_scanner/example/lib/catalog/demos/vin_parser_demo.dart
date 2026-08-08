import 'package:flutter/material.dart';
import 'package:supy_scanner/supy_scanner.dart';

import '../demo_scaffold.dart';

/// Parses a Vehicle Identification Number out of raw OCR/barcode text using the
/// pure-Dart `SupyVinParser`. Runs offline on an editable sample string.
class VinParserDemo extends StatefulWidget {
  const VinParserDemo({super.key});

  @override
  State<VinParserDemo> createState() => _VinParserDemoState();
}

class _VinParserDemoState extends State<VinParserDemo> {
  final TextEditingController _controller = TextEditingController(
    text: '1HGCM82633A004352',
  );
  SupyVin? _vin;
  bool _parsedOnce = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _parse() {
    setState(() {
      _vin = SupyVinParser.parse(_controller.text);
      _parsedOnce = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final vin = _vin;
    return DemoScaffold(
      title: 'VIN parser',
      description:
          'Extract and validate a 17-character Vehicle Identification Number '
          'from noisy OCR or barcode text. The parser strips separators, '
          'checks the length and check-digit, and returns a typed result — or '
          'null when the text is not a valid VIN.',
      apiSummary: 'SupyVinParser.parse(String) → SupyVin?',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _controller,
            decoration: const InputDecoration(
              labelText: 'Raw text',
              border: OutlineInputBorder(),
            ),
            textCapitalization: TextCapitalization.characters,
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _parse,
            icon: const Icon(Icons.directions_car),
            label: const Text('Parse VIN'),
          ),
          const SizedBox(height: 16),
          if (_parsedOnce)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child:
                    vin == null
                        ? const Text('No valid VIN found in the input.')
                        : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _kv('VIN', vin.rawValue),
                            _kv('Well-formed', vin.isWellFormed.toString()),
                            _kv(
                              'Check digit valid',
                              vin.checkDigitValid.toString(),
                            ),
                            _kv('WMI', vin.worldManufacturerIdentifier),
                            _kv('Model-year code', vin.modelYearCode),
                            _kv('Plant code', vin.plantCode),
                            _kv('Serial', vin.serialNumber),
                            _kv('Source', vin.source.name),
                          ],
                        ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 130,
          child: Text(k, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
        Expanded(
          child: SelectableText(
            v,
            style: const TextStyle(fontFamily: 'monospace'),
          ),
        ),
      ],
    ),
  );
}
