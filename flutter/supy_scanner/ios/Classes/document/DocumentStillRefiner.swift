import CoreImage
import Vision

/// Result of on-still quad refinement.
struct DocumentStillRefinement: Equatable {
  /// Normalized [0,1], top-left origin, TL/TR/BR/BL — in the still's space.
  let quad: [CGPoint]
  /// `true` when the on-still re-detection was accepted; `false` when the
  /// seed (mapped preview quad) was kept.
  let refined: Bool
}

/// Re-runs document detection on the captured full-resolution still and keeps
/// the result only when it plausibly matches the preview-tracked quad
/// (IoU ≥ `minIoU`, spec: docs/superpowers/specs/
/// 2026-07-03-supy-document-scanner-replaces-scanbot-design.md).
/// Never fails the capture: every path returns a usable quad.
enum DocumentStillRefiner {
  static let defaultMinIoU: CGFloat = 0.8

  /// Synchronous Vision pass — call on a background queue only.
  /// `seedQuad`: the preview quad already mapped into the still's space.
  static func refine(
    still: CIImage,
    seedQuad: [CGPoint],
    minIoU: CGFloat = defaultMinIoU
  ) -> DocumentStillRefinement {
    evaluate(
      candidates: detectCandidates(still: still),
      seedQuad: seedQuad,
      minIoU: minIoU
    )
  }

  /// Largest-area document quad detected on the still, or `nil` when Vision
  /// finds nothing rectangular. Used by the gallery-import path, which has no
  /// preview-tracked seed to refine against — it takes the biggest plausible
  /// document region outright. Normalized [0,1], top-left origin, TL/TR/BR/BL.
  /// Synchronous Vision pass — call on a background queue only.
  static func detectBestQuad(still: CIImage) -> [CGPoint]? {
    bestByArea(detectCandidates(still: still))
  }

  /// Picks the largest-area 4-point candidate. Separated from Vision so the
  /// selection rule is unit-testable against synthetic candidate sets.
  static func bestByArea(_ candidates: [[CGPoint]]) -> [CGPoint]? {
    var best: (quad: [CGPoint], area: CGFloat)?
    for candidate in candidates where candidate.count == 4 {
      let a = QuadGeometry.area(candidate)
      if a > (best?.area ?? 0) {
        best = (candidate, a)
      }
    }
    return best?.quad
  }

  /// Pure accept/reject gate, separated from Vision for testability.
  static func evaluate(
    candidates: [[CGPoint]],
    seedQuad: [CGPoint],
    minIoU: CGFloat
  ) -> DocumentStillRefinement {
    guard seedQuad.count == 4 else {
      return DocumentStillRefinement(quad: seedQuad, refined: false)
    }
    var best: (quad: [CGPoint], iou: CGFloat)?
    for candidate in candidates where candidate.count == 4 {
      let overlap = QuadGeometry.iou(candidate, seedQuad)
      if overlap >= minIoU, overlap > (best?.iou ?? 0) {
        best = (candidate, overlap)
      }
    }
    if let best {
      return DocumentStillRefinement(quad: best.quad, refined: true)
    }
    return DocumentStillRefinement(quad: seedQuad, refined: false)
  }

  /// Top-left-origin normalized quads for every Vision observation.
  ///
  /// Strategy: run `VNDetectRectanglesRequest` (geometric, always reliable) to
  /// seed the candidate list. On iOS 17+ also run
  /// `VNDetectDocumentSegmentationRequest` (ML-backed) and merge its results;
  /// on still captures the geometric pass is the dependable primary. This
  /// two-pass approach matches the spirit of `DocumentDetector`'s split while
  /// remaining testable against synthetic fixtures where the ML model fires
  /// inconsistently in the simulator.
  private static func detectCandidates(still: CIImage) -> [[CGPoint]] {
    let handler = VNImageRequestHandler(ciImage: still, options: [:])

    // Geometric rectangle pass — always runs, reliably detects high-contrast
    // rectangular shapes including synthetic test fixtures.
    let rectRequest = VNDetectRectanglesRequest()
    rectRequest.maximumObservations = 3
    rectRequest.minimumConfidence = 0.5
    rectRequest.minimumAspectRatio = 0.35

    var requests: [VNRequest] = [rectRequest]

    // ML document segmentation pass — iOS 17+, best on real photographs.
    let segRequest: VNDetectDocumentSegmentationRequest?
    if #available(iOS 17.0, *) {
      let req = VNDetectDocumentSegmentationRequest()
      segRequest = req
      requests.append(req)
    } else {
      segRequest = nil
    }

    do {
      try handler.perform(requests)
    } catch {
      return []
    }

    func toQuads(_ obs: [VNRectangleObservation]) -> [[CGPoint]] {
      obs.map { obs in
        // Vision is bottom-left origin; flip to top-left once.
        [obs.topLeft, obs.topRight, obs.bottomRight, obs.bottomLeft]
          .map { CGPoint(x: $0.x, y: 1 - $0.y) }
      }
    }

    let rectObs = (rectRequest.results as? [VNRectangleObservation]) ?? []
    let segObs = (segRequest?.results as? [VNRectangleObservation]) ?? []
    return toQuads(rectObs) + toQuads(segObs)
  }
}
