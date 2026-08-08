import 'dart:io';

import 'package:barcode_image/barcode_image.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:supy_scanner/supy_scanner.dart';

import '../demo_scaffold.dart';

/// Decode-from-image: rasterize a barcode to a PNG on disk, then run the
/// still-image detector over it. No camera involved — the deterministic
/// counterpart to the live scanner.
class DecodeImageDemo extends StatefulWidget {
  const DecodeImageDemo({super.key});

  @override
  State<DecodeImageDemo> createState() => _DecodeImageDemoState();
}

class _Sample {
  const _Sample(this.label, this.format, this.barcode, this.value, this.size);
  final String label;
  final SupyBarcodeFormat format;
  final Barcode barcode;
  final String value;
  final Size size;
}

class _DecodeImageDemoState extends State<DecodeImageDemo> {
  static final List<_Sample> _samples = [
    _Sample(
      'QR',
      SupyBarcodeFormat.qr,
      Barcode.qrCode(),
      'SUPY-DECODE-QR',
      const Size(420, 420),
    ),
    _Sample(
      'Code 128',
      SupyBarcodeFormat.code128,
      Barcode.code128(),
      'SUPY128DECODE',
      const Size(560, 200),
    ),
    _Sample(
      'PDF417',
      SupyBarcodeFormat.pdf417,
      Barcode.pdf417(),
      'SUPY-PDF417',
      const Size(620, 240),
    ),
  ];

  _Sample _selected = _samples.first;
  String? _imagePath;
  List<SupyBarcode>? _results;
  String? _error;
  bool _busy = false;

  Future<void> _generateAndDecode() async {
    setState(() {
      _busy = true;
      _error = null;
      _results = null;
    });
    try {
      final s = _selected;
      final w = s.size.width.toInt();
      final h = s.size.height.toInt();
      final image = img.Image(width: w, height: h);
      img.fill(image, color: img.ColorRgb8(255, 255, 255));
      drawBarcode(image, s.barcode, s.value, width: w, height: h);
      final dir = await Directory.systemTemp.createTemp('supy_decode_');
      final file = File('${dir.path}/${s.label.replaceAll(' ', '_')}.png');
      await file.writeAsBytes(img.encodePng(image), flush: true);

      final results = await SupyScannerChannel.instance.decodeImage(
        SupyDecodeImageOptions(imagePath: file.path, formats: [s.format]),
      );
      if (!mounted) return;
      setState(() {
        _imagePath = file.path;
        _results = results;
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
    final results = _results;
    return DemoScaffold(
      title: 'Decode from image',
      description:
          'Generate a barcode PNG on device, then decode that still image — '
          'no camera. This is the deterministic path used by the benchmark '
          'and by any "scan from a saved photo" flow.',
      apiSummary:
          'SupyScannerChannel.instance.decodeImage('
          'SupyDecodeImageOptions(imagePath: …, formats: [SupyBarcodeFormat.qr]))',
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
                      _busy ? null : (_) => setState(() => _selected = s),
                ),
            ],
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : _generateAndDecode,
            icon: const Icon(Icons.image_search),
            label: Text(_busy ? 'Decoding…' : 'Generate & decode'),
          ),
          const SizedBox(height: 16),
          if (_imagePath != null && File(_imagePath!).existsSync())
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(
                  File(_imagePath!),
                  height: 180,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
          if (results != null) ...[
            const SizedBox(height: 12),
            Text(
              'Decoded ${results.length} barcode(s)',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            for (final b in results)
              ListTile(
                dense: true,
                leading: const Icon(Icons.qr_code_2),
                title: Text(b.rawValue),
                subtitle: Text(b.format.wireName),
              ),
          ],
        ],
      ),
    );
  }
}
