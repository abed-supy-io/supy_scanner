import 'package:flutter_test/flutter_test.dart';
import 'package:supy_scanner/src/models/supy_barcode_format.dart';
import 'package:supy_scanner/src/models/supy_scan_options.dart';

void main() {
  group('SupyBarcodeScanOptions.toWire', () {
    test('defaults: useNativeCore is false on the wire', () {
      const opts = SupyBarcodeScanOptions();
      final wire = opts.toWire();
      expect(wire['useNativeCore'], isFalse);
    });

    test('useNativeCore propagates to the wire when enabled', () {
      const opts = SupyBarcodeScanOptions(useNativeCore: true);
      final wire = opts.toWire();
      expect(wire['useNativeCore'], isTrue);
    });

    test('wire shape carries the full v1.1 native-core key set', () {
      const opts = SupyBarcodeScanOptions(
        formats: [SupyBarcodeFormat.qr, SupyBarcodeFormat.ean13],
        useScanWindow: true,
        findBarcodeAtCenter: true,
        useNativeCore: true,
      );
      final wire = opts.toWire();
      expect(
        wire.keys,
        containsAll(<String>[
          'formats',
          'useScanWindow',
          'findBarcodeAtCenter',
          'useNativeCore',
          'camera',
        ]),
      );
    });
  });

  group('SupyDocumentScanOptions.toWire', () {
    test('defaults: useNativeCore is false on the wire', () {
      const opts = SupyDocumentScanOptions();
      final wire = opts.toWire();
      expect(wire['useNativeCore'], isFalse);
    });

    test('useNativeCore propagates to the wire when enabled', () {
      const opts = SupyDocumentScanOptions(useNativeCore: true);
      final wire = opts.toWire();
      expect(wire['useNativeCore'], isTrue);
    });

    test('outputFormat defaults to jpg on the wire', () {
      const opts = SupyDocumentScanOptions();
      expect(opts.outputFormat, SupyDocumentOutputFormat.jpg);
      expect(opts.toWire()['outputFormat'], 'jpg');
    });

    test('outputFormat serializes png + pdf as enum name', () {
      const png = SupyDocumentScanOptions(
        outputFormat: SupyDocumentOutputFormat.png,
      );
      const pdf = SupyDocumentScanOptions(
        outputFormat: SupyDocumentOutputFormat.pdf,
      );
      expect(png.toWire()['outputFormat'], 'png');
      expect(pdf.toWire()['outputFormat'], 'pdf');
    });
  });
}
