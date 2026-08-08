import CoreImage
import ImageIO

/// Output of a rectify pass over a captured still.
struct DocumentRectifyOutput {
  /// Rectified (perspective-corrected) document image.
  let image: CGImage
  /// Final quad actually warped — normalized [0,1], top-left origin,
  /// TL/TR/BR/BL, in the still's oriented space.
  let quad: [CGPoint]
  /// "refined" when the on-still re-detection was accepted, "preview" when
  /// the mapped preview quad was used. Wire value for the `quadSource` key.
  let quadSource: String
}

/// Still-capture rectification: orients the still, maps the analyzer-space
/// quad into still space, refines it against an on-still re-detection, and
/// warps via CIPerspectiveCorrection. Pure w.r.t. Flutter — callers own
/// threading, encoding, and channel errors.
enum DocumentRectifyPipeline {
  /// Fraction each corner is pushed outward from the quad centroid before the
  /// warp. Edge/segmentation detection lands a hair *inside* the true page
  /// border, so an un-expanded warp slices off the outermost text and corners
  /// ("cuts into the document"). A small outward bleed recovers that sliver;
  /// the expanded quad is clamped to the image so it can never sample outside.
  static let edgeExpansion: CGFloat = 0.02

  static func rectify(
    still: CIImage,
    analyzerQuad: [CGPoint],
    analyzerSize: CGSize,
    context: CIContext,
    refiner: (CIImage, [CGPoint]) -> DocumentStillRefinement = { still, seed in
      DocumentStillRefiner.refine(still: still, seedQuad: seed)
    }
  ) -> DocumentRectifyOutput? {
    guard analyzerQuad.count == 4 else { return nil }

    // Honor EXIF orientation if the decoded still carries one, so the quad
    // (portrait, top-left origin) and the pixels agree. No-op for the
    // portrait-oriented buffers the session emits today (orientation 1).
    let exif =
      (still.properties[kCGImagePropertyOrientation as String] as? NSNumber)?
        .int32Value ?? 1
    let oriented = exif == 1 ? still : still.oriented(forExifOrientation: exif)
    let stillSize = oriented.extent.size
    guard stillSize.width > 0, stillSize.height > 0 else { return nil }

    // 1. Analyzer space → still space (centered-crop FOV model), clamped so
    //    edge-hugging quads never leave the image.
    let mapped = PreviewPhotoQuadMapper.mapNormalizedQuad(
      analyzerQuad, from: analyzerSize, to: stillSize
    ).map { CGPoint(x: min(max($0.x, 0), 1), y: min(max($0.y, 0), 1)) }

    // 2. On-still refinement. Falls back to `mapped` internally — a capture
    //    never fails because refinement failed. Re-assert that here: if a
    //    refiner ever yields a non-4-point quad, use the mapped preview quad
    //    (always 4 points) instead of failing the capture.
    let refinement = refiner(oriented, mapped)
    let refinedAccepted = refinement.quad.count == 4
    let detected = refinedAccepted ? refinement.quad : mapped

    // 3. Bleed the quad outward so the warp keeps the page's outermost edge
    //    instead of clipping into it. Clamped to [0,1] in step 1's space.
    let quad = expandQuad(detected, by: edgeExpansion)

    // 4. Warp. Quad is top-left-origin; CIImage is bottom-left — flip Y once.
    guard let filter = CIFilter(name: "CIPerspectiveCorrection") else {
      return nil
    }
    let w = stillSize.width
    let h = stillSize.height
    let tl = CGPoint(x: quad[0].x * w, y: (1 - quad[0].y) * h)
    let tr = CGPoint(x: quad[1].x * w, y: (1 - quad[1].y) * h)
    let br = CGPoint(x: quad[2].x * w, y: (1 - quad[2].y) * h)
    let bl = CGPoint(x: quad[3].x * w, y: (1 - quad[3].y) * h)
    filter.setValue(oriented, forKey: kCIInputImageKey)
    filter.setValue(CIVector(cgPoint: tl), forKey: "inputTopLeft")
    filter.setValue(CIVector(cgPoint: tr), forKey: "inputTopRight")
    filter.setValue(CIVector(cgPoint: bl), forKey: "inputBottomLeft")
    filter.setValue(CIVector(cgPoint: br), forKey: "inputBottomRight")
    guard let outCI = filter.outputImage,
          let cg = context.createCGImage(outCI, from: outCI.extent)
    else { return nil }

    return DocumentRectifyOutput(
      image: cg,
      quad: quad,
      quadSource: refinedAccepted && refinement.refined ? "refined" : "preview"
    )
  }

  /// Scales `quad` outward from its centroid by `ratio` (0.02 == 2% bleed),
  /// clamping every corner back into the [0,1] normalized image bounds. A
  /// non-4-point quad or a zero ratio is returned unchanged.
  static func expandQuad(_ quad: [CGPoint], by ratio: CGFloat) -> [CGPoint] {
    guard quad.count == 4, ratio != 0 else { return quad }
    let cx = quad.reduce(0) { $0 + $1.x } / CGFloat(quad.count)
    let cy = quad.reduce(0) { $0 + $1.y } / CGFloat(quad.count)
    let scale = 1 + ratio
    return quad.map { p in
      CGPoint(
        x: min(max(cx + (p.x - cx) * scale, 0), 1),
        y: min(max(cy + (p.y - cy) * scale, 0), 1)
      )
    }
  }
}
