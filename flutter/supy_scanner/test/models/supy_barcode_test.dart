import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:supy_scanner/supy_scanner.dart';

void main() {
  group('SupyBarcode', () {
    test('equality and hashCode', () {
      const a = SupyBarcode(rawValue: '123', format: SupyBarcodeFormat.ean13);
      const b = SupyBarcode(rawValue: '123', format: SupyBarcodeFormat.ean13);
      const c = SupyBarcode(rawValue: '124', format: SupyBarcodeFormat.ean13);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });

    test('fromMap round-trip with bounding box', () {
      final map = <Object?, Object?>{
        'rawValue': '9780201379624',
        'format': 'ean13',
        'boundingBox': <Object?, Object?>{
          'left': 0.1,
          'top': 0.2,
          'width': 0.3,
          'height': 0.4,
        },
      };
      final decoded = SupyBarcode.fromMap(map);
      expect(decoded.rawValue, '9780201379624');
      expect(decoded.format, SupyBarcodeFormat.ean13);
      expect(decoded.boundingBox, const Rect.fromLTWH(0.1, 0.2, 0.3, 0.4));
    });

    test('fromMap without bounding box', () {
      final decoded = SupyBarcode.fromMap(const <Object?, Object?>{
        'rawValue': 'QR-PAYLOAD',
        'format': 'qr',
      });
      expect(decoded.boundingBox, isNull);
    });
  });

  group('SupyBarcodeFormat', () {
    test('wireName mirrors enum name', () {
      expect(SupyBarcodeFormat.qr.wireName, 'qr');
      expect(SupyBarcodeFormat.code128.wireName, 'code128');
    });

    test('fromWireName parses every value', () {
      for (final f in SupyBarcodeFormat.values) {
        expect(SupyBarcodeFormat.fromWireName(f.wireName), f);
      }
    });

    test('exposes the native-core-only symbologies', () {
      // These decode only via the zxing-cpp core (useNativeCore); their wire
      // names must round-trip so FormatMapper.kt can build the SUPY_FORMAT
      // mask. See docs/SYMBOLOGIES.md.
      expect(SupyBarcodeFormat.dataBar.wireName, 'dataBar');
      expect(SupyBarcodeFormat.dataBarExpanded.wireName, 'dataBarExpanded');
      expect(SupyBarcodeFormat.microQr.wireName, 'microQr');
      expect(SupyBarcodeFormat.rMQR.wireName, 'rMQR');
      expect(SupyBarcodeFormat.maxiCode.wireName, 'maxiCode');
    });

    test('fromWireName throws on unknown', () {
      expect(
        () => SupyBarcodeFormat.fromWireName('not_a_format'),
        throwsArgumentError,
      );
    });
  });
}
