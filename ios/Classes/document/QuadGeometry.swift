import CoreGraphics

/// Pure geometry helpers for comparing detection quads.
/// Points are normalized [0,1], top-left origin, TL/TR/BR/BL order,
/// but the math is origin/scale agnostic — only consistency between the two
/// polygons matters.
enum QuadGeometry {
  /// Absolute polygon area via the shoelace formula.
  static func area(_ points: [CGPoint]) -> CGFloat {
    guard points.count >= 3 else { return 0 }
    var sum: CGFloat = 0
    for i in 0..<points.count {
      let a = points[i]
      let b = points[(i + 1) % points.count]
      sum += a.x * b.y - b.x * a.y
    }
    return abs(sum) / 2
  }

  /// Intersection-over-union of two convex quads. 0 when either is degenerate.
  static func iou(_ a: [CGPoint], _ b: [CGPoint]) -> CGFloat {
    let areaA = area(a)
    let areaB = area(b)
    guard areaA > 1e-9, areaB > 1e-9 else { return 0 }
    let inter = area(clip(subject: a, by: b))
    let union = areaA + areaB - inter
    guard union > 0 else { return 0 }
    return inter / union
  }

  /// Sutherland–Hodgman clip of one convex polygon by another.
  static func clip(subject: [CGPoint], by clipPolygon: [CGPoint]) -> [CGPoint] {
    guard subject.count >= 3, clipPolygon.count >= 3 else { return [] }
    var output = normalizedWinding(subject)
    let clipper = normalizedWinding(clipPolygon)
    for i in 0..<clipper.count {
      guard !output.isEmpty else { return [] }
      let edgeA = clipper[i]
      let edgeB = clipper[(i + 1) % clipper.count]
      let input = output
      output = []
      for j in 0..<input.count {
        let current = input[j]
        let previous = input[(j + input.count - 1) % input.count]
        let currentInside = isInside(current, edgeA: edgeA, edgeB: edgeB)
        let previousInside = isInside(previous, edgeA: edgeA, edgeB: edgeB)
        if currentInside {
          if !previousInside {
            output.append(intersection(previous, current, edgeA, edgeB))
          }
          output.append(current)
        } else if previousInside {
          output.append(intersection(previous, current, edgeA, edgeB))
        }
      }
    }
    return output
  }

  /// Forces the winding that makes `isInside`'s cross-product sign valid.
  private static func normalizedWinding(_ points: [CGPoint]) -> [CGPoint] {
    var sum: CGFloat = 0
    for i in 0..<points.count {
      let a = points[i]
      let b = points[(i + 1) % points.count]
      sum += (b.x - a.x) * (b.y + a.y)
    }
    return sum > 0 ? points.reversed() : points
  }

  private static func isInside(_ p: CGPoint, edgeA: CGPoint, edgeB: CGPoint) -> Bool {
    (edgeB.x - edgeA.x) * (p.y - edgeA.y) - (edgeB.y - edgeA.y) * (p.x - edgeA.x) >= 0
  }

  private static func intersection(
    _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint, _ p4: CGPoint
  ) -> CGPoint {
    let d = (p1.x - p2.x) * (p3.y - p4.y) - (p1.y - p2.y) * (p3.x - p4.x)
    guard abs(d) > 1e-12 else { return p2 }
    let a = p1.x * p2.y - p1.y * p2.x
    let b = p3.x * p4.y - p3.y * p4.x
    return CGPoint(
      x: (a * (p3.x - p4.x) - (p1.x - p2.x) * b) / d,
      y: (a * (p3.y - p4.y) - (p1.y - p2.y) * b) / d
    )
  }
}
