import 'package:flutter/material.dart';
import 'package:supy_scanner/supy_scanner.dart';

import '../branding/supy_brand.dart';

class SupyDemoBatchBarcodePage extends StatefulWidget {
  const SupyDemoBatchBarcodePage({super.key});

  @override
  State<SupyDemoBatchBarcodePage> createState() =>
      _SupyDemoBatchBarcodePageState();
}

class _SupyDemoBatchBarcodePageState extends State<SupyDemoBatchBarcodePage> {
  SupyBatchBarcodeResult? _result;
  String? _error;
  bool _running = false;

  Future<void> _scan() async {
    setState(() {
      _running = true;
      _error = null;
    });
    try {
      final r = await SupyScannerChannel.instance.scanBarcodesBatch(
        const SupyBatchBarcodeScanOptions(),
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
    final items = _result?.items ?? const <SupyBarcode>[];
    return Theme(
      data: SupyBrand.theme(),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Batch Count'),
          actions: [
            if (_result != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: SupyBrand.accent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${items.length}',
                      style: const TextStyle(
                        color: SupyBrand.onNavy,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton.icon(
                onPressed: _running ? null : _scan,
                icon: const Icon(Icons.dynamic_feed),
                label: Text(_running ? 'Scanning…' : 'Start batch session'),
              ),
              const SizedBox(height: 16),
              if (_error != null)
                Text(
                  _error!,
                  style: const TextStyle(color: SupyBrand.critical),
                ),
              if (_result != null) ...[
                Text(
                  'Unique: ${items.length}  ·  Duplicates: '
                  '${_result!.duplicateCount}',
                  style: const TextStyle(
                    color: SupyBrand.onSurfaceMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Expanded(
                child:
                    items.isEmpty
                        ? const Center(
                          child: Text(
                            'No items yet. Start a batch session to scan\n'
                            'multiple barcodes in one go.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: SupyBrand.onSurfaceMuted),
                          ),
                        )
                        : Card(
                          child: ListView.separated(
                            itemCount: items.length,
                            separatorBuilder:
                                (_, __) => const Divider(
                                  height: 1,
                                  color: Color(0x140F1E3A),
                                ),
                            itemBuilder: (_, i) {
                              final b = items[i];
                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: SupyBrand.accentSoft,
                                  foregroundColor: SupyBrand.accent,
                                  child: Text('${i + 1}'),
                                ),
                                title: Text(b.rawValue),
                                subtitle: Text(b.format.wireName),
                              );
                            },
                          ),
                        ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
