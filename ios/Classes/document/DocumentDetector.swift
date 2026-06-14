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

  static let empty = DocumentFrameMetrics(
    quad: [],
    coverageRatio: 0,
    tiltDegrees: 0,
    meanLuma: 0,
    blurScore: 0,
    clipsEdge: false
  )

  func toMap() -> [String: Any] {
    return [
      "quad": quad.map { ["x": Double($0.x), "y": Double($0.y)] },
      "coverageRatio": coverageRatio,
      "tiltDegrees": tiltDegrees,
      "meanLuma": meanLuma,
      "blurScore": blurScore,
      "clipsEdge": clipsEdge,
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

  /// Edge clip threshold in normalized units. A quad point within this
  /// distance of any preview edge counts as `clipsEdge`.
  private let edgeClipMargin: CGFloat = 0.02

  // Lightweight throttle: skip every other frame when the previous request
  // is still in flight. Prevents Vision backpressure on slow devices.
  private var inFlight: Bool = false

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
      let metrics = Self.buildMetrics(
        rawQuad: quad,
        meanLuma: lumaMetrics.meanLuma,
        blurScore: lumaMetrics.blurScore,
        edgeClipMargin: self.edgeClipMargin
      )
      self.onMetrics?(metrics)
    }

    do {
      try handler.perform([request])
    } catch {
      inFlight = false
      onError?("Vision request failed: \(error.localizedDescription)")
      onMetrics?(
        DocumentFrameMetrics(
          quad: [],
          coverageRatio: 0,
          tiltDegrees: 0,
          meanLuma: lumaMetrics.meanLuma,
          blurScore: lumaMetrics.blurScore,
          clipsEdge: false
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
        guard let best = results.first else {
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
    req.minimumAspectRatio = 0.3
    req.maximumAspectRatio = 1.0
    req.minimumSize = 0.2
    req.maximumObservations = 1
    req.quadratureTolerance = 25
    return req
  }

  private static func area(of obs: VNRectangleObservation) -> CGFloat {
    let w = hypot(obs.topRight.x - obs.topLeft.x, obs.topRight.y - obs.topLeft.y)
    let h = hypot(obs.bottomLeft.x - obs.topLeft.x, obs.bottomLeft.y - obs.topLeft.y)
    return w * h
  }

  // MARK: - Metrics

  /// Flip Y so the Flutter side gets top-left-origin coordinates, then derive
  /// coverage, tilt, and edge-clip flags.
  private static func buildMetrics(
    rawQuad: [CGPoint],
    meanLuma: Double,
    blurScore: Double,
    edgeClipMargin: CGFloat
  ) -> DocumentFrameMetrics {
    guard rawQuad.count == 4 else {
      return DocumentFrameMetrics(
        quad: [],
        coverageRatio: 0,
        tiltDegrees: 0,
        meanLuma: meanLuma,
        blurScore: blurScore,
        clipsEdge: false
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
      clipsEdge: clips
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
}
