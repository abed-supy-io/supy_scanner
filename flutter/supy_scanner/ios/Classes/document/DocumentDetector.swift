import AVFoundation
import CoreImage
import CoreMedia
import CoreVideo
import Foundation
import Vision

// SPM builds the Obj-C bridge as a separate module; CocoaPods folds it into
// this umbrella module.
#if SWIFT_PACKAGE
import supy_scanner_objc
#endif

/// One frame's worth of raw measurements emitted to the Dart state machine.
///
/// All quad points are normalized to preview coordinates with the **top-left
/// origin** convention the Flutter side expects (Vision uses bottom-left, so
/// we flip Y before emitting).
struct DocumentFrameMetrics {
  let quad: [CGPoint]
  let coverageRatio: Double
  let tiltDegrees: Double
  let meanLuma: Double
  let blurScore: Double
  let clipsEdge: Bool
  /// Variance-of-Laplacian computed over the *quad interior*. Distinct from
  /// `blurScore`, which is the variance over a fixed center crop. Used by the
  /// Dart FSM to reject uniform patches that Vision incidentally rectangulated.
  let interiorVariance: Double
  /// 0..1 measure of corner stability across a small rolling window. 1.0 is
  /// rock-still; 0.0 is wildly jittery. Used by the FSM as a hard
  /// `holdSteady → ready` gate.
  let quadStability: Double
  /// Fraction of in-quad luma samples above the glare threshold (Y > 245).
  /// CQG: feeds the `kGlare` state.
  let glareRatio: Double
  /// Mean per-corner displacement vs. the previous accepted quad,
  /// normalized to the preview diagonal. CQG: feeds the `kHandShake` state.
  let cornerVelocity: Double
  /// Per-corner stability in [0, 1] (same scale as `quadStability` but
  /// computed independently per corner). Empty when no quad / not enough
  /// history. CQG: feeds the `kHandShake` exit gate.
  let perCornerStability: [Double]
  /// Aspect ratio (width / height) of the analyzer frame the quad was
  /// normalized against, in the *oriented* (portrait) space Vision processed —
  /// i.e. matching what the preview layer renders. `0` when unknown. The Dart
  /// overlay uses this to reproduce the preview's aspect-fill crop so the drawn
  /// quad stays glued to the real document edges.
  let sourceAspectRatio: Double

  static let empty = DocumentFrameMetrics(
    quad: [],
    coverageRatio: 0,
    tiltDegrees: 0,
    meanLuma: 0,
    blurScore: 0,
    clipsEdge: false,
    interiorVariance: 0,
    quadStability: 0,
    glareRatio: 0,
    cornerVelocity: 0,
    perCornerStability: [],
    sourceAspectRatio: 0
  )

  /// Signed quad-centroid offset from preview center, per axis, in half-extent
  /// fractions: `(centroid - 0.5) * 2`. Positive X = right of center; positive
  /// Y = below center. `(0, 0)` when there's no complete 4-corner quad.
  var centerOffset: (x: Double, y: Double) {
    guard quad.count == 4 else { return (0, 0) }
    let cx = quad.reduce(0.0) { $0 + $1.x } / 4.0
    let cy = quad.reduce(0.0) { $0 + $1.y } / 4.0
    return (Double((cx - 0.5) * 2.0), Double((cy - 0.5) * 2.0))
  }

  func toMap() -> [String: Any] {
    let offset = centerOffset
    return [
      "quad": quad.map { ["x": Double($0.x), "y": Double($0.y)] },
      "coverageRatio": coverageRatio,
      "tiltDegrees": tiltDegrees,
      "meanLuma": meanLuma,
      "blurScore": blurScore,
      "clipsEdge": clipsEdge,
      "interiorVariance": interiorVariance,
      "quadStability": quadStability,
      "glareRatio": glareRatio,
      "cornerVelocity": cornerVelocity,
      "perCornerStability": perCornerStability,
      "centerOffsetX": offset.x,
      "centerOffsetY": offset.y,
      "sourceAspectRatio": sourceAspectRatio,
    ]
  }
}

/// Document edge detector + frame-quality probe.
///
/// Uses `VNDetectDocumentSegmentationRequest` on iOS 17+, falling back to
/// `VNDetectRectanglesRequest` on iOS 16. Both yield a quad in
/// bottom-left-origin normalized image coords; we flip Y once before emitting.
///
/// Mean luma + variance-of-Laplacian are computed on a downsampled Y plane to
/// keep the analyzer thread cheap.
final class DocumentDetector: NSObject,
  AVCaptureVideoDataOutputSampleBufferDelegate
{

  /// Queue Vision requests are dispatched on. The sample-buffer delegate
  /// itself also runs here.
  let sampleBufferQueue: DispatchQueue = DispatchQueue(
    label: "io.supy.scanner.document.detector",
    qos: .userInitiated
  )

  /// Fires on `sampleBufferQueue`. Marshal to main at the FlutterResult boundary.
  var onMetrics: ((DocumentFrameMetrics) -> Void)?

  /// Fires on `sampleBufferQueue`.
  var onError: ((String) -> Void)?

  /// Lock guarding `_latestQuad`/`_latestAnalyzerSize`. The detector itself
  /// only writes from `sampleBufferQueue`, but `captureAndRectify` reads from
  /// the session queue, so we need a tiny mutex.
  private let latestQuadLock = NSLock()
  private var _latestQuad: [CGPoint] = []
  private var _latestAnalyzerSize: CGSize = .zero

  /// A quad snapshot paired with the oriented (portrait) pixel size of the
  /// analyzer buffer it was detected in — required to map the quad into the
  /// differently-aspected still-photo space.
  struct Detection {
    let quad: [CGPoint]
    let analyzerSize: CGSize
  }

  /// Returns the most recent top-left-origin normalized quad accepted by the
  /// detector, or an empty array if there's no current detection. Thread-safe.
  func snapshotLatestQuad() -> [CGPoint] {
    snapshotLatestDetection()?.quad ?? []
  }

  /// Like `snapshotLatestQuad()` but paired with the analyzer's oriented
  /// buffer size. `nil` when there's no current detection. Thread-safe.
  func snapshotLatestDetection() -> Detection? {
    latestQuadLock.lock()
    defer { latestQuadLock.unlock() }
    guard _latestQuad.count == 4 else { return nil }
    return Detection(quad: _latestQuad, analyzerSize: _latestAnalyzerSize)
  }

  private func setLatestQuad(_ quad: [CGPoint], analyzerSize: CGSize) {
    latestQuadLock.lock()
    _latestQuad = quad
    _latestAnalyzerSize = analyzerSize
    latestQuadLock.unlock()
  }

  /// Edge clip threshold in normalized units. A quad point within this
  /// distance of any preview edge counts as `clipsEdge`.
  private let edgeClipMargin: CGFloat = 0.02

  // Lightweight throttle: skip every other frame when the previous request
  // is still in flight. Prevents Vision backpressure on slow devices.
  private var inFlight: Bool = false

  /// Minimum spacing between *analyzed* frames. The camera (and preview layer)
  /// keep running at their native cadence; we just skip running the heavy
  /// Vision segmentation + emitting `frame_metrics` for frames that arrive
  /// sooner than this. Tier-driven — set once from
  /// `SupyDocumentScannerView.configureSession`. Defaults to a 20 FPS spacing
  /// so an un-configured detector still behaves sanely.
  ///
  /// Read/written only from `sampleBufferQueue` (same as `inFlight`), so no
  /// lock is needed.
  var minFrameInterval: CMTime = CMTime(value: 1, timescale: 20)

  /// Presentation timestamp of the last frame we actually analyzed. `.invalid`
  /// until the first frame is processed.
  private var lastProcessedPTS: CMTime = .invalid

  /// Quad-aspect / area / confidence gates applied uniformly to both the
  /// iOS-16 rectangles request and the iOS-17 segmentation post-processing.
  /// Kept tighter than Vision's defaults so we don't promote laptop screens
  /// or table edges to "candidate document".
  // Tuned for a hand-held page (often with fingers pinning a corner) — the
  // real-world case where the live overlay was refusing to lock at all. Looser
  // than the previous pass (0.35 / 1.0 / 0.12 / 0.5):
  //  - aspect 0.30: fingers over a corner and steep perspective foreshortening
  //    both drag the short/long ratio down; 0.30 tolerates that. Table edges /
  //    monitor bezels still fall out on the area gate below.
  //  - area 0.08: the page no longer has to fill an eighth of the frame, so a
  //    document held a full arm's length back still registers.
  //  - confidence 0.3: the iOS-17 segmentation model reports noticeably lower
  //    confidence when part of the page is occluded (a hand) or lit unevenly;
  //    0.5 was silently rejecting those otherwise-good masks — the "edges never
  //    highlight" symptom. The interior-variance floor + area gate keep genuine
  //    junk (blank table, monitor) out even at this lower confidence.
  private static let minAspectRatio: CGFloat = 0.30
  private static let maxAspectRatio: CGFloat = 1.0
  private static let minBoundingArea: CGFloat = 0.08
  private static let minConfidence: VNConfidence = 0.3

  /// Quads whose interior variance falls below this floor are treated as
  /// uniform patches (blank table, monitor, sky) and discarded. Empirically
  /// well below textured paper but above sensor noise on a uniform surface.
  ///
  /// Kept in lockstep with the shared Dart default
  /// `SupyDocumentGuidanceConfiguration.interiorVarianceFloor`: a sparse,
  /// mostly-white invoice (little ink, wide margins) reports interior variance
  /// only a little above a blank surface, and the old 5.0 floor discarded those
  /// quads outright — the page outline never highlighted. 3.0 still rejects a
  /// genuinely uniform patch but lets a low-ink invoice through to the classifier.
  private static let interiorVarianceFloor: Double = 3.0

  /// Owns the rolling per-corner drift buffer used to compute `quadStability`.
  /// Cleared on every no-quad frame so the buffer never bleeds across
  /// re-acquisitions of the document.
  // Mutated only from `sampleBufferQueue` via the synchronous `handler.perform`
  // completion. Do not touch from any other queue.
  private let stabilityTracker = QuadStabilityTracker(windowSize: 6)

  /// Last accepted (top-left-origin) quad — used to compute `cornerVelocity`.
  /// Cleared on every no-quad frame so a re-acquired document doesn't inherit
  /// a stale velocity reading.
  // Mutated only from `sampleBufferQueue` via the synchronous `handler.perform`
  // completion. Do not touch from any other queue.
  private var previousQuadForVelocity: [CGPoint] = []

  /// Glare detection threshold on the Y plane (8-bit luma). Pixels at or
  /// above this value count as specular highlights. Empirically distinguishes
  /// fluorescent / glossy-paper hotspots from naturally bright paper.
  private static let glareLumaThreshold: UInt8 = 245

  func captureOutput(
    _ output: AVCaptureOutput,
    didOutput sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection
  ) {
    guard !inFlight else { return }

    // Tier-aware rate limit. Drop frames that arrive sooner than
    // `minFrameInterval` since the last analyzed one — the preview layer is
    // unaffected (it renders straight from the session), so video stays smooth
    // while Vision + overlay repaints run at a calmer cadence. Uses the
    // buffer's own presentation timestamp (monotonic from the capture pipeline)
    // rather than wall-clock.
    let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
    if lastProcessedPTS.isValid {
      let elapsed = CMTimeSubtract(pts, lastProcessedPTS)
      if CMTimeCompare(elapsed, minFrameInterval) < 0 { return }
    }

    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
      return
    }
    lastProcessedPTS = pts
    inFlight = true

    let lumaMetrics = Self.computeLumaMetrics(pixelBuffer: pixelBuffer)

    let handler = VNImageRequestHandler(
      cvPixelBuffer: pixelBuffer,
      orientation: .right, // matches AVCaptureConnection.videoOrientation == .portrait
      options: [:]
    )

    let request = Self.makeRequest { [weak self] quad in
      guard let self = self else { return }
      defer { self.inFlight = false }

      // Variance gate: kill quads whose interior is too uniform to be a real
      // document. The Vision-space quad is fine here — `computeInteriorVariance`
      // only cares about the axis-aligned bounding box of the points.
      let interiorVariance: Double
      if quad.count == 4 {
        interiorVariance = self.computeInteriorVariance(
          pixelBuffer: pixelBuffer,
          normalizedQuad: quad
        )
      } else {
        interiorVariance = 0
      }

      let acceptedQuad: [CGPoint]
      let stability: Double
      let perCorner: [Double]
      let cornerVelocity: Double
      let glareRatio: Double
      if quad.count == 4 && interiorVariance >= Self.interiorVarianceFloor {
        acceptedQuad = quad
        // Push the *flipped* (top-left-origin) quad into the tracker so
        // stability units match what downstream consumers see.
        let flipped = quad.map { CGPoint(x: $0.x, y: 1 - $0.y) }
        stability = self.stabilityTracker.push(flipped)
        perCorner = self.stabilityTracker.perCornerStability()
        cornerVelocity = self.computeCornerVelocity(currentTopLeft: flipped)
        self.previousQuadForVelocity = flipped
        glareRatio = self.computeGlareRatio(
          pixelBuffer: pixelBuffer,
          normalizedQuad: quad
        )
      } else {
        if quad.count == 4 {
          #if DEBUG
          // Passed Vision's conf/aspect/area gates but the interior is too flat
          // to be a printed page (blank surface, monitor, sky).
          NSLog(
            "SupyDoc ✋ var-reject variance=%.2f < floor=%.2f",
            interiorVariance, Self.interiorVarianceFloor)
          #endif
        }
        acceptedQuad = []
        self.stabilityTracker.reset()
        self.previousQuadForVelocity = []
        stability = 0
        perCorner = []
        cornerVelocity = 0
        glareRatio = 0
      }

      // Oriented (portrait) analyzer size: Vision ran with `.right`
      // orientation, so its normalized space swaps the pixel buffer's
      // width/height. This is the space both the quad and the preview live in.
      let orientedSize = CGSize(
        width: CGFloat(CVPixelBufferGetHeight(pixelBuffer)),
        height: CGFloat(CVPixelBufferGetWidth(pixelBuffer))
      )
      let sourceAspectRatio =
        orientedSize.height > 0
        ? Double(orientedSize.width / orientedSize.height) : 0

      let metrics = Self.buildMetrics(
        rawQuad: acceptedQuad,
        meanLuma: lumaMetrics.meanLuma,
        blurScore: lumaMetrics.blurScore,
        edgeClipMargin: self.edgeClipMargin,
        interiorVariance: interiorVariance,
        quadStability: stability,
        glareRatio: glareRatio,
        cornerVelocity: cornerVelocity,
        perCornerStability: perCorner,
        sourceAspectRatio: sourceAspectRatio
      )
      // Cache the emitted (top-left-origin) quad so capture-and-rectify can
      // pick it up without re-running detection. Cleared whenever the quad
      // is rejected — `metrics.quad` is `[]` in that case.
      self.setLatestQuad(metrics.quad, analyzerSize: orientedSize)
      self.onMetrics?(metrics)
    }

    do {
      dispatchPrecondition(condition: .notOnQueue(.main))
      try handler.perform([request])
    } catch {
      inFlight = false
      onError?("Vision request failed: \(error.localizedDescription)")
      stabilityTracker.reset()
      previousQuadForVelocity = []
      setLatestQuad([], analyzerSize: .zero)
      onMetrics?(
        DocumentFrameMetrics(
          quad: [],
          coverageRatio: 0,
          tiltDegrees: 0,
          meanLuma: lumaMetrics.meanLuma,
          blurScore: lumaMetrics.blurScore,
          clipsEdge: false,
          interiorVariance: 0,
          quadStability: 0,
          glareRatio: 0,
          cornerVelocity: 0,
          perCornerStability: [],
          sourceAspectRatio: CVPixelBufferGetWidth(pixelBuffer) > 0
            ? Double(CVPixelBufferGetHeight(pixelBuffer))
              / Double(CVPixelBufferGetWidth(pixelBuffer)) : 0
        )
      )
    }
  }

  // MARK: - Vision request

  /// Builds a `VNRequest` that resolves into the quad's four corners in
  /// Vision's bottom-left-origin normalized space, or `[]` when nothing is
  /// detected. Picks segmentation on iOS 17+, rectangles on iOS 16.
  private static func makeRequest(
    completion: @escaping ([CGPoint]) -> Void
  ) -> VNRequest {
    if #available(iOS 17.0, *) {
      let req = VNDetectDocumentSegmentationRequest { request, _ in
        let results = request.results as? [VNRectangleObservation] ?? []
        // Mirror the iOS-16 gates on the segmentation observation. The
        // segmentation model doesn't expose tunable knobs the way
        // `VNDetectRectanglesRequest` does, so we filter post-hoc.
        let filtered = results.filter { obs in
          guard obs.confidence >= minConfidence else { return false }
          let a = aspect(of: obs)
          guard a >= minAspectRatio && a <= maxAspectRatio else { return false }
          return boundingArea(of: obs) >= minBoundingArea
        }
        let best = filtered.max(by: { lhs, rhs in
          area(of: lhs) < area(of: rhs)
        })
        debugLogVisionGate(results: results, accepted: best)
        guard let best = best else {
          completion([])
          return
        }
        completion([
          best.topLeft,
          best.topRight,
          best.bottomRight,
          best.bottomLeft,
        ])
      }
      return req
    }
    let req = VNDetectRectanglesRequest { request, _ in
      let results = request.results as? [VNRectangleObservation] ?? []
      let best = results.max(by: { lhs, rhs in
        area(of: lhs) < area(of: rhs)
      })
      debugLogVisionGate(results: results, accepted: best)
      guard let best = best else {
        completion([])
        return
      }
      completion([
        best.topLeft,
        best.topRight,
        best.bottomRight,
        best.bottomLeft,
      ])
    }
    req.minimumConfidence = minConfidence
    req.minimumAspectRatio = Float(minAspectRatio)
    req.maximumAspectRatio = Float(maxAspectRatio)
    req.minimumSize = Float(minBoundingArea)
    // Let Vision return several already-gated rectangles instead of only its
    // single top-ranked one, then pick the largest by area (above). With a cap
    // of 1, a distractor that outranks the page (a table edge, a sub-panel)
    // wins and the real document is never even a candidate — the classic
    // "edge won't lock onto the page" failure. The confidence / aspect / size
    // gates already prune junk, so widening the field only adds valid choices.
    req.maximumObservations = 8
    req.quadratureTolerance = 30
    return req
  }

  /// Frame counter backing the 1-in-N throttle for `debugLogVisionGate`, so a
  /// 20 FPS detector logs ~4 lines/sec instead of flooding the console.
  private static var debugGateFrameCounter = 0

  /// DEBUG-only telemetry: prints, for the largest candidate Vision returned,
  /// whether the page locked and — when it didn't — exactly which gate rejected
  /// it (confidence / aspect / area). Watch live in the Xcode or `flutter run`
  /// console, filtered on "SupyDoc", while aiming at an invoice. Compiled out of
  /// release builds entirely. Note the interior-variance gate runs later (in the
  /// capture closure) and is logged separately as "var-reject".
  private static func debugLogVisionGate(
    results: [VNRectangleObservation],
    accepted: VNRectangleObservation?
  ) {
    #if DEBUG
    debugGateFrameCounter &+= 1
    guard debugGateFrameCounter % 5 == 0 else { return }
    if let a = accepted {
      NSLog(
        "SupyDoc ✅ lock conf=%.2f aspect=%.2f area=%.2f",
        a.confidence, Double(aspect(of: a)), Double(boundingArea(of: a)))
    } else if let raw = results.max(by: { area(of: $0) < area(of: $1) }) {
      let conf = raw.confidence
      let asp = aspect(of: raw)
      let ar = boundingArea(of: raw)
      var reasons: [String] = []
      if conf < minConfidence { reasons.append("conf<\(minConfidence)") }
      if asp < minAspectRatio || asp > maxAspectRatio {
        reasons.append("aspect∉[\(minAspectRatio),\(maxAspectRatio)]")
      }
      if ar < minBoundingArea { reasons.append("area<\(minBoundingArea)") }
      NSLog(
        "SupyDoc ✋ reject conf=%.2f aspect=%.2f area=%.2f → %@",
        Double(conf), Double(asp), Double(ar),
        reasons.isEmpty ? "below-best" : reasons.joined(separator: ","))
    } else {
      NSLog("SupyDoc — no page candidate in frame")
    }
    #endif
  }

  private static func area(of obs: VNRectangleObservation) -> CGFloat {
    let w = hypot(obs.topRight.x - obs.topLeft.x, obs.topRight.y - obs.topLeft.y)
    let h = hypot(obs.bottomLeft.x - obs.topLeft.x, obs.bottomLeft.y - obs.topLeft.y)
    return w * h
  }

  /// Shorter-edge / longer-edge ratio of the quad. Always in (0, 1].
  /// Used to discard obvious non-document candidates (very narrow strips,
  /// table edges, etc.).
  private static func aspect(of obs: VNRectangleObservation) -> CGFloat {
    let w = hypot(obs.topRight.x - obs.topLeft.x, obs.topRight.y - obs.topLeft.y)
    let h = hypot(obs.bottomLeft.x - obs.topLeft.x, obs.bottomLeft.y - obs.topLeft.y)
    guard w > 0 && h > 0 else { return 0 }
    return min(w, h) / max(w, h)
  }

  /// Area of the quad's axis-aligned bounding box in normalized units.
  /// Mirrors `VNDetectRectanglesRequest.minimumSize` semantics for the
  /// segmentation path (which has no equivalent knob).
  private static func boundingArea(of obs: VNRectangleObservation) -> CGFloat {
    let xs = [obs.topLeft.x, obs.topRight.x, obs.bottomLeft.x, obs.bottomRight.x]
    let ys = [obs.topLeft.y, obs.topRight.y, obs.bottomLeft.y, obs.bottomRight.y]
    guard let xMin = xs.min(), let xMax = xs.max(),
          let yMin = ys.min(), let yMax = ys.max() else { return 0 }
    return (xMax - xMin) * (yMax - yMin)
  }

  // MARK: - Metrics

  /// Flip Y so the Flutter side gets top-left-origin coordinates, then derive
  /// coverage, tilt, and edge-clip flags.
  private static func buildMetrics(
    rawQuad: [CGPoint],
    meanLuma: Double,
    blurScore: Double,
    edgeClipMargin: CGFloat,
    interiorVariance: Double,
    quadStability: Double,
    glareRatio: Double,
    cornerVelocity: Double,
    perCornerStability: [Double],
    sourceAspectRatio: Double
  ) -> DocumentFrameMetrics {
    guard rawQuad.count == 4 else {
      return DocumentFrameMetrics(
        quad: [],
        coverageRatio: 0,
        tiltDegrees: 0,
        meanLuma: meanLuma,
        blurScore: blurScore,
        clipsEdge: false,
        interiorVariance: interiorVariance,
        quadStability: 0,
        glareRatio: 0,
        cornerVelocity: 0,
        perCornerStability: [],
        sourceAspectRatio: sourceAspectRatio
      )
    }

    let flipped = rawQuad.map { CGPoint(x: $0.x, y: 1 - $0.y) }
    let coverage = polygonArea(flipped)
    let tilt = tiltDegrees(quad: flipped)
    let clips = flipped.contains { p in
      p.x < edgeClipMargin || p.x > 1 - edgeClipMargin
        || p.y < edgeClipMargin || p.y > 1 - edgeClipMargin
    }

    return DocumentFrameMetrics(
      quad: flipped,
      coverageRatio: Double(coverage),
      tiltDegrees: Double(tilt),
      meanLuma: meanLuma,
      blurScore: blurScore,
      clipsEdge: clips,
      interiorVariance: interiorVariance,
      quadStability: quadStability,
      glareRatio: glareRatio,
      cornerVelocity: cornerVelocity,
      perCornerStability: perCornerStability,
      sourceAspectRatio: sourceAspectRatio
    )
  }

  /// Shoelace formula on a closed quad. Returns the absolute area in
  /// normalized units (0..1).
  private static func polygonArea(_ points: [CGPoint]) -> CGFloat {
    guard points.count >= 3 else { return 0 }
    var sum: CGFloat = 0
    for i in 0..<points.count {
      let a = points[i]
      let b = points[(i + 1) % points.count]
      sum += (a.x * b.y) - (b.x * a.y)
    }
    return abs(sum) * 0.5
  }

  /// Average of the two top/bottom edge angles, measured from horizontal.
  /// Returns the absolute value in degrees so the state machine just compares
  /// against a single positive threshold.
  private static func tiltDegrees(quad: [CGPoint]) -> CGFloat {
    let topLeft = quad[0]
    let topRight = quad[1]
    let bottomRight = quad[2]
    let bottomLeft = quad[3]
    let topAngle = atan2(topRight.y - topLeft.y, topRight.x - topLeft.x)
    let bottomAngle = atan2(bottomRight.y - bottomLeft.y,
                            bottomRight.x - bottomLeft.x)
    let avg = (topAngle + bottomAngle) * 0.5
    return abs(avg * 180.0 / .pi)
  }

  // MARK: - Luma + blur

  private struct LumaMetrics {
    let meanLuma: Double
    let blurScore: Double
  }

  /// Computes mean luma + variance-of-Laplacian over a downsampled center
  /// crop of the Y plane. Center crop avoids letterbox artifacts when the
  /// preview pillarboxes the buffer.
  ///
  /// Algorithm lives in the shared C++ core (`native/quality/frame_scorer.cpp`)
  /// so iOS and Android (via JNI) feed identical numbers into the C++ guidance
  /// classifier. Phase FQS.
  private static func computeLumaMetrics(pixelBuffer: CVPixelBuffer) -> LumaMetrics {
    CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

    let planeIndex = 0
    guard
      let base = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, planeIndex)
    else {
      return LumaMetrics(meanLuma: 0, blurScore: 0)
    }
    let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, planeIndex)
    let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, planeIndex)
    let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, planeIndex)
    let ptr = base.assumingMemoryBound(to: UInt8.self)

    let result = SupyNativeCoreBridge.scoreLumaPlane(
      ptr,
      width: Int32(width),
      height: Int32(height),
      rowStride: Int32(bytesPerRow))

    let meanLuma = result["meanLuma"]?.doubleValue ?? 0
    let blurScore = result["blurScore"]?.doubleValue ?? 0
    return LumaMetrics(meanLuma: meanLuma, blurScore: blurScore)
  }

  // MARK: - Interior variance (quad-gated)

  /// Variance-of-Laplacian computed *inside* the candidate quad's
  /// axis-aligned bounding box. This is a stricter test than the
  /// center-crop `blurScore` because Vision can rectangulate uniform regions
  /// (sky, monitor, blank table) — those will pass the blur check (their
  /// crop has texture elsewhere) but fail this one.
  ///
  /// Pure-function-ish: doesn't mutate detector state. Exposed at internal
  /// visibility so `DocumentDetectorTests` can fixture pixel buffers.
  func computeInteriorVariance(
    pixelBuffer: CVPixelBuffer,
    normalizedQuad: [CGPoint]
  ) -> Double {
    guard normalizedQuad.count == 4 else { return 0 }
    CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
    let w = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
    let h = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
    let stride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
    guard let base = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) else {
      return 0
    }
    let y = base.assumingMemoryBound(to: UInt8.self)

    let xs = normalizedQuad.map { Int($0.x * CGFloat(w)) }
    let ys = normalizedQuad.map { Int($0.y * CGFloat(h)) }
    let xMin = max(0, xs.min()!)
    let yMin = max(0, ys.min()!)
    let xMax = min(w - 1, xs.max()!)
    let yMax = min(h - 1, ys.max()!)

    // ~96 samples on the long edge keeps the cost flat across camera
    // resolutions — same trick as `computeLumaMetrics`.
    let target = 96
    let longEdge = max(xMax - xMin, yMax - yMin)
    let step = max(1, longEdge / target)
    // Reject bboxes too small to host the 3x3 Laplacian kernel at this
    // step. Subsumes the old fixed `< 8` guard, which silently produced
    // `n == 0` on large frames where `step > 1`.
    if (xMax - xMin) < 2 * step + 1 || (yMax - yMin) < 2 * step + 1 { return 0 }

    var sumLap: Double = 0
    var sumLap2: Double = 0
    var n: Int = 0
    var yy = yMin + step
    while yy < yMax - step {
      var xx = xMin + step
      while xx < xMax - step {
        let c = Int(y[yy * stride + xx])
        let l = Int(y[yy * stride + xx - step])
        let r = Int(y[yy * stride + xx + step])
        let u = Int(y[(yy - step) * stride + xx])
        let d = Int(y[(yy + step) * stride + xx])
        let lap = Double(4 * c - l - r - u - d)
        sumLap += lap
        sumLap2 += lap * lap
        n += 1
        xx += step
      }
      yy += step
    }
    guard n > 0 else { return 0 }
    let mean = sumLap / Double(n)
    return sumLap2 / Double(n) - mean * mean
  }

  // MARK: - Glare (quad-gated luma threshold)

  /// Fraction of sampled luma pixels inside the quad's axis-aligned bbox that
  /// sit at or above `glareLumaThreshold`. CQG: feeds the `kGlare` state.
  /// Uses the same step-down sampling pattern as `computeInteriorVariance`.
  func computeGlareRatio(
    pixelBuffer: CVPixelBuffer,
    normalizedQuad: [CGPoint]
  ) -> Double {
    guard normalizedQuad.count == 4 else { return 0 }
    CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
    let w = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
    let h = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
    let stride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
    guard let base = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) else {
      return 0
    }
    let y = base.assumingMemoryBound(to: UInt8.self)

    let xs = normalizedQuad.map { Int($0.x * CGFloat(w)) }
    let ys = normalizedQuad.map { Int($0.y * CGFloat(h)) }
    let xMin = max(0, xs.min()!)
    let yMin = max(0, ys.min()!)
    let xMax = min(w - 1, xs.max()!)
    let yMax = min(h - 1, ys.max()!)
    if xMax <= xMin || yMax <= yMin { return 0 }

    let target = 96
    let longEdge = max(xMax - xMin, yMax - yMin)
    let step = max(1, longEdge / target)

    var hot: Int = 0
    var n: Int = 0
    var yy = yMin
    let threshold = Self.glareLumaThreshold
    while yy <= yMax {
      var xx = xMin
      while xx <= xMax {
        if y[yy * stride + xx] >= threshold { hot += 1 }
        n += 1
        xx += step
      }
      yy += step
    }
    guard n > 0 else { return 0 }
    return Double(hot) / Double(n)
  }

  // MARK: - Corner velocity

  /// L2-mean of corner displacement vs. `previousQuadForVelocity`, normalized
  /// to the preview diagonal (unit-normalized space → sqrt(2)). Returns 0
  /// when there is no previous frame.
  private func computeCornerVelocity(currentTopLeft: [CGPoint]) -> Double {
    guard previousQuadForVelocity.count == 4 && currentTopLeft.count == 4 else {
      return 0
    }
    var sumSq: Double = 0
    for i in 0..<4 {
      let dx = Double(currentTopLeft[i].x - previousQuadForVelocity[i].x)
      let dy = Double(currentTopLeft[i].y - previousQuadForVelocity[i].y)
      sumSq += dx * dx + dy * dy
    }
    let meanSq = sumSq / 4.0
    return sqrt(meanSq) / sqrt(2.0)
  }
}

// MARK: - QuadStabilityTracker

/// Rolling-window quad stability gauge.
///
/// Holds the last `windowSize` quads and reports stability as
/// `1 - maxCornerDrift / 0.1`, clamped to [0, 1]. A fully-static quad over the
/// window returns 1.0; a quad whose worst corner travels 0.1 (normalized) or
/// more returns 0.0.
///
/// Reset on every no-quad frame so a re-acquired document doesn't inherit
/// stability from a stale buffer.
final class QuadStabilityTracker {
  private let windowSize: Int
  private var history: [[CGPoint]] = []

  init(windowSize: Int = 6) { self.windowSize = windowSize }

  @discardableResult
  func push(_ quad: [CGPoint]) -> Double {
    guard quad.count == 4 else {
      history.removeAll()
      return 0.0
    }
    history.append(quad)
    if history.count > windowSize { history.removeFirst() }
    return stability()
  }

  func stability() -> Double {
    guard history.count >= 2 else { return 0.0 }
    var maxDrift: Double = 0
    for corner in 0..<4 {
      var minX = Double.infinity
      var maxX = -Double.infinity
      var minY = Double.infinity
      var maxY = -Double.infinity
      for frame in history {
        let p = frame[corner]
        minX = min(minX, Double(p.x))
        maxX = max(maxX, Double(p.x))
        minY = min(minY, Double(p.y))
        maxY = max(maxY, Double(p.y))
      }
      let drift = max(maxX - minX, maxY - minY)
      if drift > maxDrift { maxDrift = drift }
    }
    return max(0.0, min(1.0, 1.0 - maxDrift / 0.1))
  }

  /// Per-corner stability in [0, 1], using the same 1 - drift / 0.1 mapping
  /// as `stability()`. Returns an empty array when the buffer has fewer than
  /// two frames. CQG: feeds `kHandShake` exit gate.
  func perCornerStability() -> [Double] {
    guard history.count >= 2 else { return [] }
    var out: [Double] = []
    out.reserveCapacity(4)
    for corner in 0..<4 {
      var minX = Double.infinity
      var maxX = -Double.infinity
      var minY = Double.infinity
      var maxY = -Double.infinity
      for frame in history {
        let p = frame[corner]
        minX = min(minX, Double(p.x))
        maxX = max(maxX, Double(p.x))
        minY = min(minY, Double(p.y))
        maxY = max(maxY, Double(p.y))
      }
      let drift = max(maxX - minX, maxY - minY)
      out.append(max(0.0, min(1.0, 1.0 - drift / 0.1)))
    }
    return out
  }

  func reset() { history.removeAll() }
}
