import 'dart:typed_data';

import 'package:test/test.dart';

import '../lib/metrics.dart';

void main() {
  test('flat image has zero variance-of-Laplacian', () {
    final flat = Uint8List.fromList(List.filled(64 * 64, 128));
    expect(varianceOfLaplacian(flat, 64, 64), 0.0);
  });

  test('checkerboard is sharper than a smooth gradient', () {
    final checker = Uint8List(64 * 64);
    final gradient = Uint8List(64 * 64);
    for (var y = 0; y < 64; y++) {
      for (var x = 0; x < 64; x++) {
        checker[y * 64 + x] = ((x + y) % 2 == 0) ? 255 : 0;
        gradient[y * 64 + x] = (x * 4).clamp(0, 255);
      }
    }
    expect(varianceOfLaplacian(checker, 64, 64),
        greaterThan(varianceOfLaplacian(gradient, 64, 64)));
  });

  test('uniform image scores uniformity 1.0; half-dark image scores low', () {
    final flat = Uint8List.fromList(List.filled(64 * 64, 200));
    expect(illuminationUniformity(flat, 64, 64), closeTo(1.0, 1e-9));

    final halfDark = Uint8List(64 * 64);
    for (var y = 0; y < 64; y++) {
      for (var x = 0; x < 64; x++) {
        halfDark[y * 64 + x] = x < 32 ? 200 : 50;
      }
    }
    expect(illuminationUniformity(halfDark, 64, 64), closeTo(0.25, 0.02));
  });

  test('effectiveDpi: A4 width at 2480 px is ~300 DPI', () {
    expect(effectiveDpi(2480, 210.0), closeTo(300.0, 1.0));
  });

  test('cer: exact match 0, one sub in 4 chars = 0.25, case/space ignored',
      () {
    expect(cer('ABCD', 'ABCD'), 0.0);
    expect(cer('ABCD', 'ABXD'), 0.25);
    expect(cer('Total  42.00', 'total 42.00'), 0.0);
    expect(cer('', ''), 0.0);
    expect(cer('', 'X'), 1.0);
  });
}
