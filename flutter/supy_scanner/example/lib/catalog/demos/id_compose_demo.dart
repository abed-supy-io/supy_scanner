import 'package:flutter/material.dart';
import 'package:supy_scanner/supy_scanner.dart';

import '../demo_scaffold.dart';

/// Composes a unified `SupyIdDocument` from a parsed MRZ. Demonstrates the
/// normalized cross-source getters (name / number / dates) that
/// `SupyIdParser.compose` exposes. Runs offline on a canned passport zone.
class IdComposeDemo extends StatefulWidget {
  const IdComposeDemo({super.key});

  @override
  State<IdComposeDemo> createState() => _IdComposeDemoState();
}

class _IdComposeDemoState extends State<IdComposeDemo> {
  static const String _mrzText =
      'P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<\n'
      'L898902C36UTO7408122F1204159ZE184226B<<<<<10';

  SupyIdDocument? _doc;
  bool _composedOnce = false;

  void _compose() {
    final mrz = SupyMrzParser.parse(_mrzText);
    setState(() {
      _doc = SupyIdParser.compose(mrz: mrz);
      _composedOnce = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final doc = _doc;
    return DemoScaffold(
      title: 'ID document compose',
      description:
          'Real identity capture blends sources — a passport MRZ, a driver\'s '
          'license PDF417, front-side OCR. SupyIdParser.compose merges whatever '
          'you have into one document and exposes normalized getters that '
          'prefer the check-digit-validated MRZ. This demo composes from a '
          'passport MRZ alone.',
      apiSummary:
          'SupyIdParser.compose(mrz: …, driverLicense: …, frontText: …) '
          '→ SupyIdDocument?',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const SelectableText(
              _mrzText,
              style: TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _compose,
            icon: const Icon(Icons.contact_page),
            label: const Text('Compose ID'),
          ),
          const SizedBox(height: 16),
          if (_composedOnce)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child:
                    doc == null
                        ? const Text('No sources — nothing to compose.')
                        : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _kv('Type', doc.type.name),
                            _kv('First name', doc.firstName ?? '—'),
                            _kv('Last name', doc.lastName ?? '—'),
                            _kv('Doc number', doc.documentNumber ?? '—'),
                            _kv('DOB', doc.dateOfBirth ?? '—'),
                            _kv('Expiry', doc.expiryDate ?? '—'),
                            _kv('Nationality', doc.nationality ?? '—'),
                            _kv('Verified', doc.isVerified.toString()),
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
          width: 120,
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
