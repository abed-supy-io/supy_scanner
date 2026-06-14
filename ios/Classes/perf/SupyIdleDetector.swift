import CoreVideo
import Foundation

/// iOS counterpart to `IdleDetector.kt`. Computes a strided luma variance on
/// the pixel buffer and flips `isIdle` when the scene has been static for at
/// least `thresholdMs`. Any motion (variance spike) flips it back.
///
/// Not thread-safe — call from a single detector queue.
final class SupyIdleDetector {

  private let thresholdMs: Int?
  private let varianceThreshold: Double
  private let motionVariance: Double

  private(set) var isIdle: Bool = false
  private var stillSinceMs: Int64 = 0

  init(
    thresholdMs: Int?,
    varianceThreshold: Double = 60.0,
    motionVariance: Double = 200.0
  ) {
    self.thresholdMs = thresholdMs
    self.varianceThreshold = varianceThreshold
    self.motionVariance = motionVariance
  }

  /// Updates state from a pixel buffer. Returns true on `idle ↔ active`
  /// transition so callers can emit an event.
  func update(_ pixelBuffer: CVPixelBuffer, nowMs: Int64) -> Bool {
    guard let threshold = thresholdMs else { return false }
    let variance = Self.sampleVariance(pixelBuffer)

    if variance >= motionVariance {
      stillSinceMs = 0
      if isIdle {
        isIdle = false
        return true
      }
      return false
    }

    if variance <= varianceThreshold {
      if stillSinceMs == 0 { stillSinceMs = nowMs }
      if !isIdle && nowMs - stillSinceMs >= Int64(threshold) {
        isIdle = true
        return true
      }
      return false
    }

    stillSinceMs = 0
    return false
  }

  private static func sampleVariance(_ pixelBuffer: CVPixelBuffer) -> Double {
    CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)
    guard width > 0, height > 0 else { return 0 }

    let bytesPerRow: Int
    let baseAddress: UnsafeMutableRawPointer?
    if CVPixelBufferIsPlanar(pixelBuffer) {
      // Y plane on 420f / 420v pixel formats.
      bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
      baseAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0)
    } else {
      bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
      baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer)
    }
    guard let base = baseAddress else { return 0 }
    let ptr = base.assumingMemoryBound(to: UInt8.self)

    let stepX = max(1, width / 32)
    let stepY = max(1, height / 32)

    var count: Int64 = 0
    var sum: Int64 = 0
    var sumSq: Int64 = 0
    var y = 0
    while y < height {
      let rowBase = y * bytesPerRow
      var x = 0
      while x < width {
        let v = Int64(ptr[rowBase + x])
        sum += v
        sumSq += v * v
        count += 1
        x += stepX
      }
      y += stepY
    }
    guard count > 0 else { return 0 }
    let mean = Double(sum) / Double(count)
    let meanSq = Double(sumSq) / Double(count)
    return meanSq - mean * mean
  }
}
