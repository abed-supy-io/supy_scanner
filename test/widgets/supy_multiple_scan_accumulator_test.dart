import 'package:flutter_test/flutter_test.dart';
import 'package:supy_scanner/supy_scanner.dart';

void main() {
  const ean = SupyBarcode(
    rawValue: '1234567890123',
    format: SupyBarcodeFormat.ean13,
  );
  const qr = SupyBarcode(
    rawValue: 'https://supy.io',
    format: SupyBarcodeFormat.qr,
  );

  group('SupyMultipleScanAccumulator unique mode', () {
    test('records each payload once', () {
      final acc = SupyMultipleScanAccumulator(
        config: const SupyMultipleScanUseCaseConfiguration(),
      );
      final t0 = DateTime.utc(2026, 6, 13);
      acc.offer(ean, now: t0);
      acc.offer(ean, now: t0.add(const Duration(seconds: 5)));
      acc.offer(qr, now: t0.add(const Duration(seconds: 6)));
      expect(acc.items, hasLength(2));
      expect(acc.items[0].count, 1);
      expect(acc.totalCount, 2);
      expect(acc.uniqueCount, 2);
    });

    test('clear empties', () {
      final acc = SupyMultipleScanAccumulator(
        config: const SupyMultipleScanUseCaseConfiguration(),
      );
      acc.offer(ean, now: DateTime.utc(2026));
      acc.clear();
      expect(acc.items, isEmpty);
      expect(acc.totalCount, 0);
    });
  });

  group('SupyMultipleScanAccumulator counting mode', () {
    test('debounce blocks duplicate within window', () {
      final acc = SupyMultipleScanAccumulator(
        config: const SupyMultipleScanUseCaseConfiguration(
          mode: SupyMultipleScanMode.counting,
        ),
      );
      final t0 = DateTime.utc(2026, 6, 13);
      acc.offer(ean, now: t0);
      acc.offer(ean, now: t0.add(const Duration(milliseconds: 500)));
      expect(acc.totalCount, 1);
      expect(acc.items.single.count, 1);
    });

    test('debounce allows duplicate past window', () {
      final acc = SupyMultipleScanAccumulator(
        config: const SupyMultipleScanUseCaseConfiguration(
          mode: SupyMultipleScanMode.counting,
        ),
      );
      final t0 = DateTime.utc(2026, 6, 13);
      acc.offer(ean, now: t0);
      acc.offer(ean, now: t0.add(const Duration(milliseconds: 1200)));
      acc.offer(ean, now: t0.add(const Duration(milliseconds: 2400)));
      expect(acc.totalCount, 3);
      expect(acc.uniqueCount, 1);
      expect(acc.items.single.count, 3);
    });

    test('distinct payloads accumulate independently', () {
      final acc = SupyMultipleScanAccumulator(
        config: const SupyMultipleScanUseCaseConfiguration(
          mode: SupyMultipleScanMode.counting,
        ),
      );
      final t0 = DateTime.utc(2026, 6, 13);
      acc.offer(ean, now: t0);
      acc.offer(qr, now: t0);
      expect(acc.uniqueCount, 2);
      expect(acc.totalCount, 2);
    });

    test('notifies listeners on accept and clear', () {
      final acc = SupyMultipleScanAccumulator(
        config: const SupyMultipleScanUseCaseConfiguration(),
      );
      var ticks = 0;
      acc.addListener(() => ticks++);
      acc.offer(ean, now: DateTime.utc(2026));
      acc.offer(ean, now: DateTime.utc(2026)); // dedup: no tick
      acc.clear();
      expect(ticks, 2);
    });
  });
}
