import 'package:flutter/material.dart';
import 'package:supy_scanner/supy_scanner.dart';

import '../demo_scaffold.dart';

/// Parses an ICAO 9303 Machine Readable Zone with the pure-Dart
/// `SupyMrzParser`. Ships canned TD1/TD3 samples so it runs with no camera.
class MrzParserDemo extends StatefulWidget {
  const MrzParserDemo({super.key});

  @override
  State<MrzParserDemo> createState() => _MrzParserDemoState();
}

class _Sample {
  const _Sample(this.label, this.text);
  final String label;
  final String text;
}

class _MrzParserDemoState extends State<MrzParserDemo> {
  // Canonical ICAO 9303 specimen zones (public spec examples).
  static const List<_Sample> _samples = [
    _Sample(
      'TD3 passport',
      'P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<\n'
          'L898902C36UTO7408122F1204159ZE184226B<<<<<10',
    ),
    _Sample(
      'TD1 ID card',
      'I<UTOD231458907<<<<<<<<<<<<<<<\n'
          '7408122F1204159UTO<<<<<<<<<<<6\n'
          'ERIKSSON<<ANNA<MARIA<<<<<<<<<<',
    ),
  ];

  _Sample _selected = _samples.first;
  SupyMrzDocument? _mrz;
  bool _parsedOnce = false;

  void _parse() {
    setState(() {
      _mrz = SupyMrzParser.parse(_selected.text);
      _parsedOnce = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final mrz = _mrz;
    return DemoScaffold(
      title: 'MRZ parser',
      description:
          'Decode the machine-readable zone of passports and ID cards (ICAO '
          '9303 TD1/TD2/TD3). Every field is extracted and each check digit is '
          'verified independently, so you can trust a name even when a date '
          'misread — inspect the per-field validity flags.',
      apiSummary:
          'SupyMrzParser.parse(String) → SupyMrzDocument?  ·  also '
          'SupyRecognizedText.parseMrz()',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            children: [
              for (final s in _samples)
                ChoiceChip(
                  label: Text(s.label),
                  selected: _selected == s,
                  onSelected:
                      (_) => setState(() {
                        _selected = s;
                        _parsedOnce = false;
                        _mrz = null;
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
              _selected.text,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _parse,
            icon: const Icon(Icons.badge),
            label: const Text('Parse MRZ'),
          ),
          const SizedBox(height: 16),
          if (_parsedOnce)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child:
                    mrz == null
                        ? const Text('No valid MRZ found in the input.')
                        : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _kv('Format', mrz.format.name.toUpperCase()),
                            _kv('Type', mrz.documentType),
                            _kv('Issuer', mrz.issuingCountry),
                            _kv('Surname', mrz.surname),
                            _kv('Given names', mrz.givenNames),
                            _kv('Doc number', mrz.documentNumber),
                            _kv('Nationality', mrz.nationality),
                            _kv('DOB (YYMMDD)', mrz.dateOfBirth),
                            _kv('Sex', mrz.sex.name),
                            _kv('Expiry (YYMMDD)', mrz.expiryDate),
                            const Divider(),
                            _kv(
                              'Doc # valid',
                              mrz.documentNumberValid.toString(),
                            ),
                            _kv('DOB valid', mrz.dateOfBirthValid.toString()),
                            _kv('Expiry valid', mrz.expiryDateValid.toString()),
                            _kv(
                              'Composite valid',
                              mrz.compositeValid.toString(),
                            ),
                            _kv('Overall valid', mrz.isValid.toString()),
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
          width: 140,
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
