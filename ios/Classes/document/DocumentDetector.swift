import AVFoundation
import CoreImage
import CoreMedia
import CoreVideo
import Foundation
import Vision

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

  static let empty = DocumentFrameMetrics(
    quad: [],
    coverageRatio: 0,
    tiltDegrees: 0,
    meanLuma: 0,
    blurScore: 0,
    clipsEdge: false,
    interiorVariance: 0,
    quadStability: 0
  )

  func toMap() -> [String: Any] {
    return [
      "quad": quad.map { ["x": Double($0.x), "y": Double($0.y)] },
      "coverageRatio": coverageRatio,
      "tiltDegrees": tiltDegrees,
      "meanLuma": meanLuma,
      "blurScore": blurScore,
      "clipsEdge": clipsEdge,
      "interiorVariance": interiorVariance,
      "quadStability": quadStability,
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

  /// Lock guarding `_latestQuad`. The detector itself only writes from
  /// `sampleBufferQueue`, but `captureAndRectify` reads from the session
  /// queue, so we need a tiny mutex.
  private let latestQuadLock = NSLock()
  private var _latestQuad: [CGPoint] = []

  /// Returns the most recent top-left-origin normalized quad accepted by the
  /// detector, or an empty array if there's no current detection. Thread-safe.
  func snapshotLatestQuad() -> [CGPoint] {
    latestQuadLock.lock()
    defer { latestQuadLock.unlock() }
    return _latestQuad
  }

  private func setLatestQuad(_ quad: [CGPoint]) {
    latestQuadLock.lock()
    _latestQuad = quad
    latestQuadLock.unlock()
  }

  /// Edge clip threshold in normalized units. A quad point within this
  /// distance of any preview edge counts as `clipsEdge`.
  private let edgeClipMargin: CGFloat = 0.02

  // Lightweight throttle: skip every other frame when the previous request
  // is still in flight. Prevents Vision backpressure on slow devices.
  private var inFlight: Bool = false

  /// Quad-aspect / area / confidence gates applied uniformly to both the
  /// iOS-16 rectangles request and the iOS-17 segmentation post-processing.
  /// Kept tighter than Vision's defaults so we don't promote laptop screens
  /// or table edges to "candidate document".
  private static let minAspectRatio: CGFloat = 0.4
  private static let maxAspectRatio: CGFloat = 1.0
  private static let minBoundingArea: CGFloat = 0.2
  private static let minConfidence: VNConfidence = 0.7

  /// Quads whose interior variance falls below this floor are treated as
  /// uniform patches (blank table, monitor, sky) and discarded. Empirically
  /// well below textured paper but above sensor noise on a uniform surface.
  private static let interiorVarianceFloor: Double = 5.0

  /// Owns the rolling per-corner drift buffer used to compute `quadStability`.
  /// Cleared on every no-quad frame so the buffer never bleeds across
  /// re-acquisitions of the document.
  // Mutated only from `sampleBufferQueue` via the synchronous `handler.perform`
  // completion. Do not touch from any other queue.
  private let stabilityTracker = QuadStabilityTracker(windowSize: 6)

  func captureOutput(
    _ output: AVCaptureOutput,
    didOutput sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection
  ) {
    guard !inFlight else { return }
    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
      return
    }
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
      if quad.count == 4 && interiorVariance >= Self.interiorVarianceFloor {
        acceptedQuad = quad
        // Push the *flipped* (top-left-origin) quad into the tracker so
        // stability units match what downstream consumers see.
        let flipped = quad.map { CGPoint(x: $0.x, y: 1 - $0.y) }
        stability = self.stabilityTracker.push(flipped)
      } else {
        acceptedQuad = []
        self.stabilityTracker.reset()
        stability = 0
      }

      let metrics = Self.buildMetrics(
        rawQuad: acceptedQuad,
        meanLuma: lumaMetrics.meanLuma,
        blurScore: lumaMetrics.blurScore,
        edgeClipMargin: self.edgeClipMargin,
        interiorVariance: interiorVariance,
        quadStability: stability
      )
      // Cache the emitted (top-left-origin) quad so capture-and-rectify can
      // pick it up without re-running detection. Cleared whenever the quad
      // is rejected — `metrics.quad` is `[]` in that case.
      self.setLatestQuad(metrics.quad)
      self.onMetrics?(metrics)
    }

    do {
      try handler.perform([request])
    } catch {
      inFlight = false
      onError?("Vision request failed: \(error.localizedDescription)")
      stabilityTracker.reset()
      setLatestQuad([])
      onMetrics?(
        DocumentFrameMetrics(
          quad: [],
          coverageRatio: 0,
          tiltDegrees: 0,
          meanLuma: lumaMetrics.meanLuma,
          blurScore: lumaMetrics.blurScore,
          clipsEdge: false,
          interiorVariance: 0,
          quadStability: 0
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
        guard
          let best = filtered.max(by: { lhs, rhs in
            area(of: lhs) < area(of: rhs)
          })
        else {
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
      guard
        let best = results.max(by: { lhs, rhs in
          area(of: lhs) < area(of: rhs)
        })
      else {
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
    req.maximumObservations = 1
    req.quadratureTolerance = 30
    return req
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
    quadStability: Double
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
        quadStability: 0
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
      quadStability: quadStability
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

    // Crop to the central 60% of the frame, then stride to ~96px on the long
    // edge. Keeps the cost flat regardless of camera resolution.
    let cropFraction: Double = 0.6
    let cropW = Int(Double(width) * cropFraction)
    let cropH = Int(Double(height) * cropFraction)
    let xOffset = (width - cropW) / 2
    let yOffset = (height - cropH) / 2
    let targetLong = 96
    let strideStep = max(1, max(cropW, cropH) / targetLong)
    let ptr = base.assumingMemoryBound(to: UInt8.self)

    var lumaSum: Int = 0
    var lumaCount: Int = 0
    // Keep a 1-D buffer of sampled luma values so we can run a 3x3 Laplacian
    // over the downsample grid.
    var samples: [Int16] = []
    samples.reserveCapacity((cropH / strideStep + 1) * (cropW / strideStep + 1))
    var sampledCols = 0

    var y = yOffset
    var rowCount = 0
    while y < yOffset + cropH {
      let row = ptr.advanced(by: y * bytesPerRow)
      var x = xOffset
      var colCount = 0
      while x < xOffset + cropW {
        let v = Int(row[x])
        lumaSum += v
        lumaCount += 1
        samples.append(Int16(v))
        x += strideStep
        colCount += 1
      }
      if rowCount == 0 { sampledCols = colCount }
      y += strideStep
      rowCount += 1
    }

    guard lumaCount > 0, sampledCols > 2, samples.count >= sampledCols * 3 else {
      return LumaMetrics(meanLuma: 0, blurScore: 0)
    }

    let meanLuma = Double(lumaSum) / Double(lumaCount)

    // 3x3 Laplacian (4-neighbour) over the downsampled grid.
    let rowsSampled = samples.count / sampledCols
    var laplacianSum: Double = 0
    var laplacianSqSum: Double = 0
    var laplacianN: Int = 0
    for ry in 1..<(rowsSampled - 1) {
      for rx in 1..<(sampledCols - 1) {
        let i = ry * sampledCols + rx
        let center = Int(samples[i])
        let up = Int(samples[i - sampledCols])
        let down = Int(samples[i + sampledCols])
        let left = Int(samples[i - 1])
        let right = Int(samples[i + 1])
        let l = (4 * center) - up - down - left - right
        laplacianSum += Double(l)
        laplacianSqSum += Double(l * l)
        laplacianN += 1
      }
    }
    guard laplacianN > 0 else {
      return LumaMetrics(meanLuma: meanLuma, blurScore: 0)
    }
    let mean = laplacianSum / Double(laplacianN)
    let variance = (laplacianSqSum / Double(laplacianN)) - (mean * mean)

    return LumaMetrics(meanLuma: meanLuma, blurScore: max(0, variance))
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

  func reset() { history.removeAll() }
}
