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

  /// Cap the *document* live-detection rate, in FPS. Unlike `analyzerFpsCap`
  /// (which caps the camera's hardware frame delivery for the barcode
  /// pipeline), this throttles only the Vision segmentation + overlay-repaint
  /// work — the preview layer keeps the camera's native cadence so the video
  /// stays smooth. `VNDetectDocumentSegmentationRequest` is a neural-net
  /// segmentation model (much heavier than the barcode rectangle detector),
  /// and edge guidance needs no more than ~20 FPS, so every tier — including
  /// HIGH — is capped here.
  var documentDetectorFpsCap: Int {
    switch self {
    case .high: return 20
    case .mid: return 15
    case .low: return 12
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
    case .low: return min(requested, 0.88)
    }
  }

  // Cached: device tier doesn't change at runtime (thermal state does, but
  // that's tracked separately by ThermalGovernor).
  private static var cached: SupyDeviceTier?

  // Debug-only tier override. Honored by `detect()` so engineers can repro
  // tier-low behaviour on a tier-high CI device. Set via the
  // `debugForceTier` MethodChannel call from Dart, which is gated by
  // `kDebugMode`; the native setter is further gated on `#if DEBUG` at the
  // call site (see SupyScannerPlugin.swift) so release builds strip it.
  private static var debugOverride: SupyDeviceTier?

  static func detect() -> SupyDeviceTier {
    if let override = debugOverride { return override }
    if let cached = cached { return cached }
    let resolved = compute()
    cached = resolved
    return resolved
  }

  /// Forces `detect()` to return `tier` until cleared. Pass `nil` to clear.
  /// Caller is responsible for gating on `#if DEBUG`.
  static func setDebugOverride(_ tier: SupyDeviceTier?) {
    debugOverride = tier
  }

  /// Current debug override or nil if none. Test/inspection helper.
  static func currentDebugOverride() -> SupyDeviceTier? {
    return debugOverride
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
