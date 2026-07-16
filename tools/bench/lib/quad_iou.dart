// Convex-quad IoU for the detection bench. Sutherland–Hodgman clipping +
// shoelace area — winding-agnostic, no deps.
import 'dart:math';

double _signedArea(List<Point<double>> poly) {
  var sum = 0.0;
  for (var i = 0; i < poly.length; i++) {
    final p = poly[i];
    final q = poly[(i + 1) % poly.length];
    sum += p.x * q.y - q.x * p.y;
  }
  return sum / 2.0;
}

/// Absolute polygon area (shoelace).
double polygonArea(List<Point<double>> poly) {
  if (poly.length < 3) return 0.0;
  return _signedArea(poly).abs();
}

/// Clips [subject] against convex [clip] (Sutherland–Hodgman). Works for
/// either winding of either polygon.
List<Point<double>> clipPolygon(
    List<Point<double>> subject, List<Point<double>> clip) {
  if (clip.length < 3 || subject.length < 3) return const [];
  final sign = _signedArea(clip) >= 0 ? 1.0 : -1.0;
  var output = List.of(subject);
  for (var i = 0; i < clip.length && output.isNotEmpty; i++) {
    final a = clip[i];
    final b = clip[(i + 1) % clip.length];
    bool inside(Point<double> p) =>
        sign * ((b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x)) >= 0;
    Point<double> intersect(Point<double> p, Point<double> q) {
      final a1 = b.y - a.y, b1 = a.x - b.x;
      final c1 = a1 * a.x + b1 * a.y;
      final a2 = q.y - p.y, b2 = p.x - q.x;
      final c2 = a2 * p.x + b2 * p.y;
      final det = a1 * b2 - a2 * b1;
      return Point((b2 * c1 - b1 * c2) / det, (a1 * c2 - a2 * c1) / det);
    }

    final input = output;
    output = <Point<double>>[];
    for (var j = 0; j < input.length; j++) {
      final p = input[j];
      final q = input[(j + 1) % input.length];
      final pIn = inside(p);
      final qIn = inside(q);
      if (pIn) {
        output.add(p);
        if (!qIn) output.add(intersect(p, q));
      } else if (qIn) {
        output.add(intersect(p, q));
      }
    }
  }
  return output;
}

List<Point<double>> _toPoints(List<double> quad) => [
      for (var i = 0; i < quad.length; i += 2) Point(quad[i], quad[i + 1]),
    ];

/// IoU of two convex quads given as interleaved [x0,y0,..,x3,y3] lists.
double quadIou(List<double> a, List<double> b) {
  final pa = _toPoints(a);
  final pb = _toPoints(b);
  final areaA = polygonArea(pa);
  final areaB = polygonArea(pb);
  if (areaA <= 0 || areaB <= 0) return 0.0;
  final inter = polygonArea(clipPolygon(pa, pb));
  final union = areaA + areaB - inter;
  if (union <= 0) return 0.0;
  return (inter / union).clamp(0.0, 1.0);
}
