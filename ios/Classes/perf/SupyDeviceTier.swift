import Foundation
import UIKit

/// Device performance tier used by perf-adaptive code paths (analyzer
/// resolution, FPS caps, OCR downscaling, idle thresholds).
///
/// See docs/PERFORMANCE.md → "Device-class adaptive — flagships keep their
/// power" for the policy table this implements.
enum SupyDeviceTier {
  case high
  case mid
  case low

  /// Target analyzer dimensions for the embedded barcode pipeline.
  /// `nil` means: leave session preset alone (preview-native).
  var barcodeAnalyzerSize: (width: Int32, height: Int32)? {
    switch self {
    case .high: return nil
    case .mid: return (960, 720)
    case .low: return (640, 480)
    }
  }

  /// Cap analyzer dispatch FPS. `nil` = uncapped.
  var analyzerFpsCap: Int? {
    switch self {
    case .high: return nil
    case .mid: return 24
    case .low: return 20
    }
  }

  /// Idle pause threshold in milliseconds, or `nil` to disable.
  var idlePauseThresholdMs: Int? {
    switch self {
    case .high: return nil
    case .mid: return 8_000
    case .low: return 4_000
    }
  }

  /// Long-edge cap (px) for OCR input images. `nil` = no downscale.
  var ocrLongEdgeCap: Int? {
    switch self {
    case .high: return nil
    case .mid: return 1600
    case .low: return 1280
    }
  }

  func jpegQuality(requested: Double) -> Double {
    switch self {
    case .high, .mid: return requested
    case .low: return min(requested, 0.75)
    }
  }

  // Cached: device tier doesn't change at runtime (thermal state does, but
  // that's tracked separately by ThermalGovernor).
  private static var cached: SupyDeviceTier?

  static func detect() -> SupyDeviceTier {
    if let cached = cached { return cached }
    let resolved = compute()
    cached = resolved
    return resolved
  }

  private static func compute() -> SupyDeviceTier {
    let cores = ProcessInfo.processInfo.processorCount
    let thermal = ProcessInfo.processInfo.thermalState

    if cores <= 4 { return .low }

    // Don't promote a device to HIGH while it's already running hot — it'll
    // just thermal-throttle into MID/LOW work moments later. ThermalGovernor
    // re-downgrades dynamically; this is the static fallback at boot.
    let thermallyFine = thermal == .nominal || thermal == .fair

    if cores >= 6 && thermallyFine { return .high }
    return .mid
  }
}
