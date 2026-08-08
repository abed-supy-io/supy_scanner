import 'package:flutter_test/flutter_test.dart';
import 'package:supy_scanner/src/enhance/supy_document_filter.dart';
import 'package:supy_scanner/src/models/supy_barcode_format.dart';
import 'package:supy_scanner/src/models/supy_document_scanner_backend.dart';
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

    test('outputFormat serializes tiff + searchablePdf as enum name (DC8)', () {
      const tiff = SupyDocumentScanOptions(
        outputFormat: SupyDocumentOutputFormat.tiff,
      );
      const searchable = SupyDocumentScanOptions(
        outputFormat: SupyDocumentOutputFormat.searchablePdf,
      );
      expect(tiff.toWire()['outputFormat'], 'tiff');
      expect(searchable.toWire()['outputFormat'], 'searchablePdf');
    });

    test('invoice intent does not override an explicit tiff/searchablePdf', () {
      // The invoice preset only upgrades the *default* jpg → pdf; an explicit
      // DC8 format is a caller choice and must survive the preset.
      const tiff = SupyDocumentScanOptions(
        intent: SupyDocumentScanIntent.invoice,
        outputFormat: SupyDocumentOutputFormat.tiff,
      );
      const searchable = SupyDocumentScanOptions(
        intent: SupyDocumentScanIntent.invoice,
        outputFormat: SupyDocumentOutputFormat.searchablePdf,
      );
      expect(tiff.toWire()['outputFormat'], 'tiff');
      expect(searchable.toWire()['outputFormat'], 'searchablePdf');
    });

    test('preferredBackend is omitted by default', () {
      const opts = SupyDocumentScanOptions();
      expect(opts.preferredBackend, isNull);
      expect(opts.toWire().containsKey('preferredBackend'), isFalse);
    });

    test('preferredBackend serializes to its wireName', () {
      const cameraX = SupyDocumentScanOptions(
        preferredBackend: SupyDocumentScannerBackend.cameraX,
      );
      const gms = SupyDocumentScanOptions(
        preferredBackend: SupyDocumentScannerBackend.gms,
      );
      expect(cameraX.toWire()['preferredBackend'], 'cameraX');
      expect(gms.toWire()['preferredBackend'], 'gms');
    });

    test('filter defaults to color on the wire', () {
      const opts = SupyDocumentScanOptions();
      expect(opts.filter, SupyDocumentFilter.color);
      expect(opts.toWire()['filter'], 'color');
    });

    test('filter serializes grayscale/blackAndWhite/original', () {
      expect(
        const SupyDocumentScanOptions(
          filter: SupyDocumentFilter.grayscale,
        ).toWire()['filter'],
        'grayscale',
      );
      expect(
        const SupyDocumentScanOptions(
          filter: SupyDocumentFilter.blackAndWhite,
        ).toWire()['filter'],
        'blackAndWhite',
      );
      expect(
        const SupyDocumentScanOptions(
          filter: SupyDocumentFilter.original,
        ).toWire()['filter'],
        'original',
      );
    });
  });

  group('SupyDocumentProcessingOptions', () {
    test('processing is omitted from the wire by default (drop-in safe)', () {
      const opts = SupyDocumentScanOptions();
      expect(opts.toWire().containsKey('processing'), isFalse);
    });

    test('processing serializes under the nested "processing" key', () {
      const opts = SupyDocumentScanOptions(
        processing: SupyDocumentProcessingOptions(),
      );
      final wire = opts.toWire();
      expect(wire['processing'], isA<Map<String, Object?>>());
    });

    test('default processing wire carries the color-scan stage set', () {
      final wire = const SupyDocumentProcessingOptions().toWire();
      expect(wire['detectDocument'], isTrue);
      expect(wire['perspectiveCorrection'], isTrue);
      expect(wire['autoCrop'], isTrue);
      expect(wire['cropMargin'], 0.02);
      expect(wire['deskew'], isTrue);
      expect(wire['shadowRemoval'], isTrue);
      expect(wire['backgroundWhitening'], isTrue);
      expect(wire['denoise'], isTrue);
      expect(wire['sharpen'], isTrue);
      expect(wire['maxDimension'], 2200);
    });

    test(
      'enhancement + quality are omitted when null (fall back to outer)',
      () {
        final wire = const SupyDocumentProcessingOptions().toWire();
        expect(wire.containsKey('enhancement'), isFalse);
        expect(wire.containsKey('quality'), isFalse);
      },
    );

    test(
      'enhancement serializes to the filter wireName; quality passes through',
      () {
        final wire =
            const SupyDocumentProcessingOptions(
              enhancement: SupyDocumentFilter.blackAndWhite,
              quality: 80,
            ).toWire();
        expect(wire['enhancement'], 'blackAndWhite');
        expect(wire['quality'], 80);
      },
    );

    test('overridden stages propagate to the wire', () {
      final wire =
          const SupyDocumentProcessingOptions(
            autoCrop: false,
            deskew: false,
            backgroundWhitening: false,
            maxDimension: 0,
            cropMargin: 0.1,
          ).toWire();
      expect(wire['autoCrop'], isFalse);
      expect(wire['deskew'], isFalse);
      expect(wire['backgroundWhitening'], isFalse);
      expect(wire['maxDimension'], 0);
      expect(wire['cropMargin'], 0.1);
    });

    test('value equality holds for identical options', () {
      expect(
        const SupyDocumentProcessingOptions(),
        const SupyDocumentProcessingOptions(),
      );
      expect(
        const SupyDocumentProcessingOptions().hashCode,
        const SupyDocumentProcessingOptions().hashCode,
      );
      expect(
        const SupyDocumentProcessingOptions(autoCrop: false),
        isNot(const SupyDocumentProcessingOptions()),
      );
    });
  });
}
