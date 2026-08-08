import 'package:flutter_test/flutter_test.dart';
import 'package:supy_scanner/supy_scanner.dart';

void main() {
  const cola = SupyBarcode(rawValue: '111', format: SupyBarcodeFormat.ean13);
  const chips = SupyBarcode(rawValue: '222', format: SupyBarcodeFormat.ean13);
  const stranger = SupyBarcode(
    rawValue: '999',
    format: SupyBarcodeFormat.ean13,
  );

  SupyFindAndPickAccumulator make({bool allowUnexpected = false}) {
    return SupyFindAndPickAccumulator(
      config: SupyFindAndPickUseCaseConfiguration(
        expected: const [
          SupyExpectedBarcode(rawValue: '111', expectedCount: 2),
          SupyExpectedBarcode(rawValue: '222'),
        ],
        allowUnexpected: allowUnexpected,
      ),
    );
  }

  test('initial state: zeroed rows in order, not complete', () {
    final acc = make();
    expect(acc.rows, hasLength(2));
    expect(acc.rows[0].foundCount, 0);
    expect(acc.rows[0].isComplete, isFalse);
    expect(acc.completedRowCount, 0);
    expect(acc.totalRowCount, 2);
    expect(acc.isComplete, isFalse);
  });

  test('matching detections increment row, cap at expectedCount', () {
    final acc = make();
    expect(acc.offer(cola), isTrue);
    expect(acc.rows[0].foundCount, 1);
    expect(acc.offer(cola), isTrue);
    expect(acc.rows[0].isComplete, isTrue);
    expect(acc.offer(cola), isFalse); // capped
    expect(acc.rows[0].foundCount, 2);
  });

  test('isComplete true only when every row complete', () {
    final acc = make();
    acc.offer(cola);
    acc.offer(cola);
    expect(acc.isComplete, isFalse);
    acc.offer(chips);
    expect(acc.isComplete, isTrue);
    expect(acc.completedRowCount, 2);
  });

  test('unexpected dropped when allowUnexpected=false', () {
    final acc = make();
    expect(acc.offer(stranger), isFalse);
    expect(acc.unexpected, isEmpty);
  });

  test('unexpected recorded once when allowUnexpected=true', () {
    final acc = make(allowUnexpected: true);
    expect(acc.offer(stranger), isTrue);
    expect(acc.offer(stranger), isFalse); // already recorded
    expect(acc.unexpected, hasLength(1));
    expect(acc.unexpected.single.rawValue, '999');
  });

  test('clear resets rows + unexpected, notifies once', () {
    final acc = make(allowUnexpected: true);
    var ticks = 0;
    acc.addListener(() => ticks++);
    acc.offer(cola); // tick 1
    acc.offer(stranger); // tick 2
    ticks = 0;
    acc.clear(); // tick 3 -> 1
    expect(ticks, 1);
    expect(acc.rows.every((r) => r.foundCount == 0), isTrue);
    expect(acc.unexpected, isEmpty);
  });

  test('clear is a no-op when already zero', () {
    final acc = make();
    var ticks = 0;
    acc.addListener(() => ticks++);
    acc.clear();
    expect(ticks, 0);
  });
}
