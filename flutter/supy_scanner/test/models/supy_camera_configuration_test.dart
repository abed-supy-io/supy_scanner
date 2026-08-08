import 'package:flutter_test/flutter_test.dart';
import 'package:supy_scanner/supy_scanner.dart';

void main() {
  group('SupyCameraConfiguration', () {
    test('default toWire shape', () {
      const cfg = SupyCameraConfiguration();
      expect(cfg.toWire(), <String, Object?>{
        'initialZoom': 1.0,
        'minFocusDistanceLock': false,
        'scanRange': 'standard',
      });
    });

    test('scanRange wire names cover all variants', () {
      expect(SupyScanRange.standard.wireName, 'standard');
      expect(SupyScanRange.close.wireName, 'close');
      expect(SupyScanRange.extended.wireName, 'extended');
    });

    test('initialZoom > 0 enforced', () {
      expect(
        () => SupyCameraConfiguration(initialZoom: 0),
        throwsA(isA<AssertionError>()),
      );
    });

    test('value equality', () {
      const a = SupyCameraConfiguration(
        initialZoom: 2.0,
        minFocusDistanceLock: true,
        scanRange: SupyScanRange.close,
      );
      const b = SupyCameraConfiguration(
        initialZoom: 2.0,
        minFocusDistanceLock: true,
        scanRange: SupyScanRange.close,
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });
  });

  group('SupyBarcodeScanOptions.toWire embeds camera', () {
    test('default includes standard camera block', () {
      const opts = SupyBarcodeScanOptions();
      final wire = opts.toWire();
      expect(wire['camera'], <String, Object?>{
        'initialZoom': 1.0,
        'minFocusDistanceLock': false,
        'scanRange': 'standard',
      });
    });

    test('custom camera flows through', () {
      const opts = SupyBarcodeScanOptions(
        camera: SupyCameraConfiguration(
          initialZoom: 2.5,
          minFocusDistanceLock: true,
          scanRange: SupyScanRange.extended,
        ),
      );
      final wire = opts.toWire();
      expect(wire['camera'], <String, Object?>{
        'initialZoom': 2.5,
        'minFocusDistanceLock': true,
        'scanRange': 'extended',
      });
    });
  });
}
