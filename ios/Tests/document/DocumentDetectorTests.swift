import CoreVideo
import CoreGraphics
import XCTest

@testable import supy_scanner

/// Tests for the interior-variance gate and quad-stability tracker added to
/// `DocumentDetector` as part of the document-scanner smart-guidance work.
///
/// These are pure-logic tests — no AVCapture, no Vision. We build a
/// `CVPixelBuffer` in `kCVPixelFormatType_420YpCbCr8BiPlanarFullRange` format
/// with synthetic luma content and feed it to `computeInteriorVariance`.
final class DocumentDetectorTests: XCTestCase {

  // MARK: - Interior variance

  func testInteriorVarianceRejectsUniformPatch() {
    let pixelBuffer = makePixelBuffer(width: 64, height: 64, fill: 128)
    let detector = DocumentDetector()
    let variance = detector.computeInteriorVariance(
      pixelBuffer: pixelBuffer,
      normalizedQuad: [
        CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.9, y: 0.1),
        CGPoint(x: 0.9, y: 0.9), CGPoint(x: 0.1, y: 0.9),
      ]
    )
    // 5.0 is the FSM's interior-variance floor
    XCTAssertLessThan(variance, 5.0)
  }

  func testInteriorVarianceFlagsTexturedPatch() {
    let pixelBuffer = makeCheckerboardBuffer(width: 64, height: 64, cell: 4)
    let detector = DocumentDetector()
    let variance = detector.computeInteriorVariance(
      pixelBuffer: pixelBuffer,
      normalizedQuad: [
        CGPoint(x: 0.05, y: 0.05), CGPoint(x: 0.95, y: 0.05),
        CGPoint(x: 0.95, y: 0.95), CGPoint(x: 0.05, y: 0.95),
      ]
    )
    XCTAssertGreaterThan(variance, 100.0)
  }

  // MARK: - Quad stability

  func testStabilityTrackerReportsHighStabilityForStaticQuad() {
    let tracker = QuadStabilityTracker(windowSize: 6)
    let q: [CGPoint] = [
      CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.9, y: 0.1),
      CGPoint(x: 0.9, y: 0.9), CGPoint(x: 0.1, y: 0.9),
    ]
    for _ in 0..<6 { _ = tracker.push(q) }
    XCTAssertGreaterThan(tracker.stability(), 0.95)
  }

  func testStabilityTrackerReportsLowStabilityForJittery() {
    let tracker = QuadStabilityTracker(windowSize: 6)
    let base: [CGPoint] = [
      CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.9, y: 0.1),
      CGPoint(x: 0.9, y: 0.9), CGPoint(x: 0.1, y: 0.9),
    ]
    for i in 0..<6 {
      let jitter = CGFloat(i) * 0.05
      _ = tracker.push(base.map { CGPoint(x: $0.x + jitter, y: $0.y) })
    }
    XCTAssertLessThan(tracker.stability(), 0.05)
  }

  // MARK: - Helpers

  /// Build a 4:2:0 bi-planar CVPixelBuffer with all luma pixels set to `fill`
  /// and chroma to neutral 128 (the chroma plane is unused by the detector).
  private func makePixelBuffer(width: Int, height: Int, fill: UInt8) -> CVPixelBuffer {
    var pb: CVPixelBuffer?
    let attrs: [CFString: Any] = [
      kCVPixelBufferIOSurfacePropertiesKey: [:],
    ]
    let status = CVPixelBufferCreate(
      kCFAllocatorDefault,
      width, height,
      kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
      attrs as CFDictionary,
      &pb
    )
    precondition(status == kCVReturnSuccess, "Failed to create pixel buffer: \(status)")
    let buffer = pb!
    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
    fillPlane(buffer, planeIndex: 0) { _, _ in fill }
    fillPlane(buffer, planeIndex: 1) { _, _ in 128 }
    return buffer
  }

  /// Build a checkerboard luma plane with cells of `cell` pixels alternating
  /// 0 / 255 so the Laplacian responds strongly at every cell boundary.
  private func makeCheckerboardBuffer(width: Int, height: Int, cell: Int) -> CVPixelBuffer {
    var pb: CVPixelBuffer?
    let attrs: [CFString: Any] = [
      kCVPixelBufferIOSurfacePropertiesKey: [:],
    ]
    let status = CVPixelBufferCreate(
      kCFAllocatorDefault,
      width, height,
      kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
      attrs as CFDictionary,
      &pb
    )
    precondition(status == kCVReturnSuccess, "Failed to create pixel buffer: \(status)")
    let buffer = pb!
    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
    fillPlane(buffer, planeIndex: 0) { x, y in
      ((x / cell) + (y / cell)) % 2 == 0 ? 0 : 255
    }
    fillPlane(buffer, planeIndex: 1) { _, _ in 128 }
    return buffer
  }

  private func fillPlane(
    _ buffer: CVPixelBuffer,
    planeIndex: Int,
    sample: (Int, Int) -> UInt8
  ) {
    guard let base = CVPixelBufferGetBaseAddressOfPlane(buffer, planeIndex) else { return }
    let w = CVPixelBufferGetWidthOfPlane(buffer, planeIndex)
    let h = CVPixelBufferGetHeightOfPlane(buffer, planeIndex)
    let stride = CVPixelBufferGetBytesPerRowOfPlane(buffer, planeIndex)
    let ptr = base.assumingMemoryBound(to: UInt8.self)
    for y in 0..<h {
      let row = ptr.advanced(by: y * stride)
      for x in 0..<w {
        row[x] = sample(x, y)
      }
    }
  }
}
