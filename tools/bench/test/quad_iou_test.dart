import 'dart:math';

import 'package:test/test.dart';

import '../lib/quad_iou.dart';

// Unit square as a TL,TR,BR,BL interleaved quad (y-down convention).
const unit = [0.0, 0.0, 1.0, 0.0, 1.0, 1.0, 0.0, 1.0];

void main() {
  test('polygonArea of unit square is 1', () {
    final poly = [
      const Point(0.0, 0.0),
      const Point(1.0, 0.0),
      const Point(1.0, 1.0),
      const Point(0.0, 1.0),
    ];
    expect(polygonArea(poly), closeTo(1.0, 1e-9));
    // Winding must not matter.
    expect(polygonArea(poly.reversed.toList()), closeTo(1.0, 1e-9));
  });

  test('identical quads → IoU 1', () {
    expect(quadIou(unit, unit), closeTo(1.0, 1e-9));
  });

  test('disjoint quads → IoU 0', () {
    const other = [2.0, 2.0, 3.0, 2.0, 3.0, 3.0, 2.0, 3.0];
    expect(quadIou(unit, other), closeTo(0.0, 1e-9));
  });

  test('half-overlap → IoU 1/3', () {
    // Unit square shifted right by 0.5: intersection 0.5, union 1.5.
    const shifted = [0.5, 0.0, 1.5, 0.0, 1.5, 1.0, 0.5, 1.0];
    expect(quadIou(unit, shifted), closeTo(1.0 / 3.0, 1e-9));
  });

  test('contained quad → IoU = area ratio', () {
    // Centered half-size square: intersection 0.25, union 1.0.
    const inner = [0.25, 0.25, 0.75, 0.25, 0.75, 0.75, 0.25, 0.75];
    expect(quadIou(unit, inner), closeTo(0.25, 1e-9));
    expect(quadIou(inner, unit), closeTo(0.25, 1e-9));
  });

  test('degenerate quad → IoU 0, no crash', () {
    const degenerate = [0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5];
    expect(quadIou(unit, degenerate), 0.0);
  });
}
