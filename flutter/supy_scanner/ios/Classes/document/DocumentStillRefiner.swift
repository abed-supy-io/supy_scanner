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
/// the result only when it plausibly matches the preview-tracked quad — either
/// by symmetric IoU (`minIoU`) or, for a tighter/offset still detection the
/// preview→photo FOV mapping would otherwise get vetoed, by containment (see
/// `evaluate`). Spec: docs/superpowers/specs/
/// 2026-07-03-supy-document-scanner-replaces-scanbot-design.md.
/// Never fails the capture: every path returns a usable quad.
enum DocumentStillRefiner {
  static let defaultMinIoU: CGFloat = 0.8
  /// Overlap (relative to the smaller quad's area) at which a still detection
  /// is treated as the same page as the seed despite an offset/tightness
  /// difference the preview→photo FOV mapping introduced. Lower than
  /// `defaultMinIoU` on purpose — see `evaluate`.
  static let defaultMinContainment: CGFloat = 0.75
  /// Area band (as a fraction of the seed area) a containment-accepted
  /// candidate must fall in. Keeps the still detection comparable in size to
  /// the framed page so it can't snap onto a small inner rectangle, nor onto a
  /// much-larger background rectangle. The containment path exists to rescue a
  /// still detection that is *tighter* than the seed (ratio < 1), so the upper
  /// bound only needs modest headroom above 1 for a seed the FOV mapping made
  /// slightly small. A full-frame background rectangle (~2× a half-frame seed)
  /// otherwise sails through — its containment against the smaller seed is ~1 —
  /// and snaps the crop to the whole image; capping at 1.35 vetoes it so the
  /// seed quad drives the crop instead.
  static let defaultMinAreaRatio: CGFloat = 0.5
  static let defaultMaxAreaRatio: CGFloat = 1.35

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
  ///
  /// A still candidate is accepted when it clearly outlines the same page the
  /// user framed, by *either* rule:
  ///   - symmetric IoU ≥ `minIoU` — the strong-agreement fast path; or
  ///   - containment ≥ `minContainment`, where containment is the overlap
  ///     measured against the *smaller* quad's area, provided the candidate is
  ///     within [`minAreaRatio`, `maxAreaRatio`]× the seed area.
  ///
  /// The containment rule exists because the preview→photo FOV mapping can
  /// place the seed slightly offset or looser than the true page. A full-res
  /// still detection outlines the same page but tighter/shifted, which drags
  /// symmetric IoU below `minIoU` and gets it wrongly vetoed — leaving the bad
  /// seed to drive the crop. Containment (relative to the smaller quad) stays
  /// high in that case, so the correct detection wins; the area band keeps it
  /// from snapping onto a small inner rectangle (a table/box printed on the
  /// page) that would sit fully inside the seed.
  ///
  /// The gate is additive: everything the IoU path accepted before is still
  /// accepted. Accepted candidates are ranked by IoU so the detection whose
  /// overall extent best matches where the user aimed wins.
  static func evaluate(
    candidates: [[CGPoint]],
    seedQuad: [CGPoint],
    minIoU: CGFloat,
    minContainment: CGFloat = defaultMinContainment,
    minAreaRatio: CGFloat = defaultMinAreaRatio,
    maxAreaRatio: CGFloat = defaultMaxAreaRatio
  ) -> DocumentStillRefinement {
    guard seedQuad.count == 4 else {
      return DocumentStillRefinement(quad: seedQuad, refined: false)
    }
    let seedArea = QuadGeometry.area(seedQuad)
    var best: (quad: [CGPoint], iou: CGFloat)?
    for candidate in candidates where candidate.count == 4 {
      let candArea = QuadGeometry.area(candidate)
      guard candArea > 1e-9, seedArea > 1e-9 else { continue }
      let iou = QuadGeometry.iou(candidate, seedQuad)
      let accepted: Bool
      if iou >= minIoU {
        accepted = true
      } else {
        let ratio = candArea / seedArea
        let inter = QuadGeometry.area(
          QuadGeometry.clip(subject: candidate, by: seedQuad))
        let containment = inter / min(candArea, seedArea)
        accepted =
          containment >= minContainment
          && ratio >= minAreaRatio && ratio <= maxAreaRatio
      }
      if accepted, iou > (best?.iou ?? -1) {
        best = (candidate, iou)
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
    // A few extra candidates: a distractor rectangle (table edge, inner box)
    // can outrank the page in Vision's top 3, and the IoU/containment gate in
    // `evaluate` only ever sees what this pass returns. Widening the field lets
    // the true page survive to the matcher; the gate still rejects the rest.
    rectRequest.maximumObservations = 6
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
