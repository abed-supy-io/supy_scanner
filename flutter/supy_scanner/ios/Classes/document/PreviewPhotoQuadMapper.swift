import CoreGraphics

/// Maps a normalized quad between two capture spaces that share a sensor
/// field of view but differ in aspect ratio (e.g. a 16:9 analyzer stream vs
/// a 4:3 still). Models the narrower-aspect space as a horizontally centered
/// crop of the wider one — both spaces share the full long axis because the
/// scanner session is portrait-locked. Residual FOV error is corrected
/// downstream by on-still re-detection (`DocumentStillRefiner`).
enum PreviewPhotoQuadMapper {
  /// `quad`: normalized [0,1], top-left origin, relative to `source`.
  /// `source` / `dest`: oriented pixel sizes (post-rotation, i.e. portrait
  /// sizes for portrait sessions) of each space.
  /// Returns the quad normalized [0,1] relative to `dest`.
  static func mapNormalizedQuad(
    _ quad: [CGPoint],
    from source: CGSize,
    to dest: CGSize
  ) -> [CGPoint] {
    guard source.width > 0, source.height > 0, dest.width > 0, dest.height > 0
    else { return quad }
    let sourceAspect = source.width / source.height
    let destAspect = dest.width / dest.height
    if abs(sourceAspect - destAspect) < 0.001 { return quad }
    if sourceAspect < destAspect {
      // Source is the narrower space: it shares the full long axis (height —
      // the session is portrait-locked) and occupies a centered horizontal
      // band of dest.
      let f = sourceAspect / destAspect
      let c = (1 - f) / 2
      return quad.map { CGPoint(x: c + $0.x * f, y: $0.y) }
    } else {
      // Source is the wider space: dest is the centered horizontal band of
      // source — the exact inverse of the branch above, so round-trips are
      // identity. Mapped x may leave [0,1]; callers clamp.
      let f = destAspect / sourceAspect
      let c = (1 - f) / 2
      return quad.map { CGPoint(x: ($0.x - c) / f, y: $0.y) }
    }
  }
}
