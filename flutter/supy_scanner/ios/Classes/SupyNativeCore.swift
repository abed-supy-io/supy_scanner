// Thin Swift facade over the supy_scanner native core.
//
// Swift talks to the Obj-C `SupyNativeCoreBridge` class instead of calling
// the C ABI directly. CocoaPods' auto-generated umbrella module doesn't
// reliably expose C symbols from parent-directory headers to in-module
// Swift files, so an Obj-C wrapper in Classes/ is the portable path.

import CoreGraphics
import Foundation

// Under Swift Package Manager the Obj-C bridge is its own module; under
// CocoaPods it lands in this same umbrella module and needs no import.
#if SWIFT_PACKAGE
import supy_scanner_objc
#endif

/// Cross-platform mirror of Android's `NativeBarcode` (Kotlin value type).
/// Corners are pixel-space in the source luma frame (top-left origin),
/// TL/TR/BR/BL order. Matches `supy_core_decode_corners` contract.
struct NativeBarcode {
    let rawValue: String
    let format: String
    let topLeft: CGPoint
    let topRight: CGPoint
    let bottomRight: CGPoint
    let bottomLeft: CGPoint

    /// Axis-aligned bounding box derived from the four corners. Mirrors
    /// `emitNativeDetections` in `SupyBarcodeScannerView.kt`.
    var boundingBox: CGRect {
        let xs = [topLeft.x, topRight.x, bottomRight.x, bottomLeft.x]
        let ys = [topLeft.y, topRight.y, bottomRight.y, bottomLeft.y]
        let minX = xs.min() ?? 0
        let maxX = xs.max() ?? 0
        let minY = ys.min() ?? 0
        let maxY = ys.max() ?? 0
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

/// SUPY_FORMAT_* bitmask mirrors of the C ABI macros. Kept here so Swift
/// callers don't import the C header directly.
struct SupyFormatMask: OptionSet {
    let rawValue: UInt32

    static let none = SupyFormatMask([])
    static let aztec = SupyFormatMask(rawValue: 1 << 0)
    static let codabar = SupyFormatMask(rawValue: 1 << 1)
    static let code39 = SupyFormatMask(rawValue: 1 << 2)
    static let code93 = SupyFormatMask(rawValue: 1 << 3)
    static let code128 = SupyFormatMask(rawValue: 1 << 4)
    static let dataMatrix = SupyFormatMask(rawValue: 1 << 5)
    static let ean8 = SupyFormatMask(rawValue: 1 << 6)
    static let ean13 = SupyFormatMask(rawValue: 1 << 7)
    static let itf = SupyFormatMask(rawValue: 1 << 8)
    static let pdf417 = SupyFormatMask(rawValue: 1 << 9)
    static let qr = SupyFormatMask(rawValue: 1 << 10)
    static let upcA = SupyFormatMask(rawValue: 1 << 11)
    static let upcE = SupyFormatMask(rawValue: 1 << 12)
    static let all = SupyFormatMask(rawValue: 0xFFFF_FFFF)

    /// True iff [mask] requests Data Matrix. Mirrors
    /// `FormatMapper.maskIncludesDataMatrix` on Android.
    static func includesDataMatrix(_ mask: SupyFormatMask) -> Bool {
        return mask.contains(.dataMatrix) || mask == .all
    }

    /// [mask] with the Data Matrix bit cleared. Mirrors
    /// `FormatMapper.maskWithoutDataMatrix` on Android. When [mask] is `.all`
    /// (the NONE→ALL coercion target) we lower it to the explicit union of
    /// every known bit minus Data Matrix so the C ABI doesn't re-coerce back.
    static func maskWithoutDataMatrix(_ mask: SupyFormatMask) -> SupyFormatMask {
        if mask == .all {
            var m: SupyFormatMask = [
                .aztec, .codabar, .code39, .code93, .code128,
                .ean8, .ean13, .itf, .pdf417, .qr, .upcA, .upcE,
            ]
            m.remove(.dataMatrix)
            return m
        }
        var m = mask
        m.remove(.dataMatrix)
        return m
    }

    /// Translates wire names (Dart `SupyBarcodeFormat.wireName`) to a mask.
    /// Mirrors `FormatMapper.toSupyFormatMask` on Android. Empty list or any
    /// `"all"` entry returns `.all` to match the C ABI's NONE→ALL coercion.
    static func fromWireNames(_ wire: [String]) -> SupyFormatMask {
        if wire.isEmpty || wire.contains("all") { return .all }
        var mask: SupyFormatMask = .none
        for name in wire {
            switch name {
            case "qr": mask.insert(.qr)
            case "ean13": mask.insert(.ean13)
            case "ean8": mask.insert(.ean8)
            case "upcA": mask.insert(.upcA)
            case "upcE": mask.insert(.upcE)
            case "code39": mask.insert(.code39)
            case "code93": mask.insert(.code93)
            case "code128": mask.insert(.code128)
            case "itf": mask.insert(.itf)
            case "pdf417": mask.insert(.pdf417)
            case "dataMatrix": mask.insert(.dataMatrix)
            case "aztec": mask.insert(.aztec)
            case "codabar": mask.insert(.codabar)
            default: break
            }
        }
        return mask.isEmpty ? .all : mask
    }
}

enum SupyNativeCore {
    static func version() -> String {
        return SupyNativeCoreBridge.version()
    }

    static func abiVersion() -> Int32 {
        return SupyNativeCoreBridge.abiVersion()
    }

    /// True iff the linked native core was built with zxing-cpp. Callers
    /// MUST treat this as a feature flag: short-circuit to Vision when false.
    static func hasZxing() -> Bool {
        return SupyNativeCoreBridge.hasZxing()
    }

    /// Mirrors `supy_binarize_mode_t`. Sauvola is the matrix-code default;
    /// Wolf-Jolion is reserved for the 1D assist path.
    enum BinarizeMode: Int32 {
        case sauvola2D = 0
        case wolfJolion1D = 1
    }

    /// In-place adaptive binarization on a packed (or padded) luma buffer.
    /// Returns true on success. Output bytes are 0 or 255. Worker-thread only.
    static func binarizeLumaInPlace(
        luma: UnsafeMutablePointer<UInt8>,
        width: Int32,
        height: Int32,
        rowStride: Int32,
        mode: BinarizeMode
    ) -> Bool {
        return SupyNativeCoreBridge.binarizeLuma(
            inPlace: luma,
            width: width,
            height: height,
            rowStride: rowStride,
            mode: SupyBinarizeMode(rawValue: mode.rawValue) ?? .sauvola2D
        )
    }

    /// Per-pixel median-of-three across same-geometry luma crops. All four
    /// buffers MUST share width/height/rowStride; [out] may not alias inputs.
    /// Returns true on success. Worker-thread only.
    static func temporalMedianLuma3(
        frame0: UnsafePointer<UInt8>,
        frame1: UnsafePointer<UInt8>,
        frame2: UnsafePointer<UInt8>,
        out: UnsafeMutablePointer<UInt8>,
        width: Int32,
        height: Int32,
        rowStride: Int32
    ) -> Bool {
        return SupyNativeCoreBridge.temporalMedianLuma3(
            frame0,
            frame1: frame1,
            frame2: frame2,
            out: out,
            width: width,
            height: height,
            rowStride: rowStride
        )
    }

    /// True iff the linked native core was built with libdmtx. Mirrors
    /// `supy_core_has_libdmtx`. Use as a feature flag for the Data Matrix
    /// ROI-assist path; callers fall back to the full-frame decode when false.
    static func hasLibdmtx() -> Bool {
        return SupyNativeCoreBridge.hasLibdmtx()
    }

    /// Single-plane Data Matrix locator. Returns one quad per region
    /// (TL/TR/BR/BL, input-image pixel space) on success. Returns an empty
    /// array when the locator ran and found nothing, and `nil` when the
    /// native core is unavailable or the input is bad.
    static func locateDatamatrix(
        luma: UnsafePointer<UInt8>,
        width: Int32,
        height: Int32,
        rowStride: Int32,
        maxRegions: Int32,
        timeoutMs: Int32
    ) -> [[CGPoint]]? {
        guard
            let quads = SupyNativeCoreBridge.locateDatamatrix(
                fromLuma: luma,
                width: width,
                height: height,
                rowStride: rowStride,
                maxRegions: maxRegions,
                timeoutMs: timeoutMs
            )
        else {
            return nil
        }
        return quads.map { q in
            [
                CGPoint(x: q[0].doubleValue, y: q[1].doubleValue),
                CGPoint(x: q[2].doubleValue, y: q[3].doubleValue),
                CGPoint(x: q[4].doubleValue, y: q[5].doubleValue),
                CGPoint(x: q[6].doubleValue, y: q[7].doubleValue),
            ]
        }
    }

    /// Synchronously decodes barcodes from a single-plane Y buffer. The
    /// caller owns [luma] and must keep it valid for the duration of the
    /// call (e.g. between `CVPixelBufferLockBaseAddress` and the matching
    /// unlock). Returns an empty array when decode ran and found nothing,
    /// and `nil` when the native core is unavailable or the input is bad.
    static func decodeBarcodes(
        luma: UnsafePointer<UInt8>,
        width: Int32,
        height: Int32,
        rowStride: Int32,
        formats: SupyFormatMask,
        tryHarder: Bool,
        tryRotate: Bool
    ) -> [NativeBarcode]? {
        guard
            let items = SupyNativeCoreBridge.decodeBarcodes(
                fromLuma: luma,
                width: width,
                height: height,
                rowStride: rowStride,
                formats: formats.rawValue,
                tryHarder: tryHarder,
                tryRotate: tryRotate
            )
        else {
            return nil
        }
        return items.map { item in
            NativeBarcode(
                rawValue: item.rawValue,
                format: item.format,
                topLeft: item.topLeft,
                topRight: item.topRight,
                bottomRight: item.bottomRight,
                bottomLeft: item.bottomLeft
            )
        }
    }
}

// MARK: - Document guidance (CXD auto-snap)

/// Mirror of `supy::scanner::document::FrameState` and Android's
/// `GuidanceFrameState`. Ordinals are wire-stable (0..11) and MUST NOT be
/// reordered — `fromOrdinal` pins the C++ classifier return path.
enum GuidanceFrameState: Int32 {
    // Indices 0..7 are wire-stable; must NOT be reordered.
    case noDocument = 0
    case tooDark = 1
    case tooClose = 2
    case tooFar = 3
    case tooSkewed = 4
    case blurry = 5
    case holdSteady = 6
    case ready = 7
    // CQG additions — appended only. Match the C++ tail at indices 8..11.
    case glare = 8
    case occluded = 9
    case handShake = 10
    case edgeClipped = 11
    // Framing passed but the quad sits too far off-center. The arrow direction
    // is a render detail derived from the signed center offset, not the state.
    case offCenter = 12

    /// Maps a raw ordinal back to a case, falling back to `.noDocument` for an
    /// out-of-range value. Mirrors `GuidanceFrameState.fromOrdinal` on Android.
    static func fromOrdinal(_ ordinal: Int32) -> GuidanceFrameState {
        return GuidanceFrameState(rawValue: ordinal) ?? .noDocument
    }
}

/// Packed result from the C++ classifier: state + opaque 0..1 live quality.
/// Mirrors Android's `GuidanceClassifyResult`.
struct GuidanceClassifyResult: Equatable {
    let state: GuidanceFrameState
    let liveQualityScore: Float
}

/// Per-frame raw measurements fed into the classifier. `perCornerStability` is
/// empty when the analyzer has no per-corner signal this frame (the C++ side
/// then holds its prior occlusion judgement); when populated it must have
/// length 4 (TL/TR/BR/BL). Mirrors Android's `GuidanceFrameMetrics`.
struct GuidanceFrameMetrics {
    var hasDocument: Bool
    var clipsEdge: Bool
    var coverageRatio: Float
    var tiltDegrees: Float
    var meanLuma: Float
    var blurScore: Float
    var quadStability: Float
    var interiorVariance: Float
    // CQG additions.
    var glareRatio: Float = 0.0
    var cornerVelocity: Float = 0.0
    // Signed quad-centroid offset from preview center, per axis, in half-extent
    // fractions: `(centroid - 0.5) * 2`. Positive X = right of center; positive
    // Y = below center.
    var centerOffsetX: Float = 0.0
    var centerOffsetY: Float = 0.0
    var perCornerStability: [Float] = []

    var hasPerCornerStability: Bool { perCornerStability.count == 4 }
}

/// Threshold subset of `supy::scanner::document::GuidanceConfig`. Defaults match
/// the C++ struct's field-initialisers and Android's `GuidanceConfig`; tier
/// wiring overrides `readyStableFrames` per the standalone scanner path.
struct GuidanceConfig {
    var minCoverageRatio: Float = 0.30
    var maxCoverageRatio: Float = 0.90
    var maxTiltDegrees: Float = 20.0
    var minMeanLuma: Float = 60.0
    var minBlurScore: Float = 80.0
    var readyStabilityFloor: Float = 0.75
    var interiorVarianceFloor: Float = 5.0
    var exitMargin: Float = 0.10
    var smoothingAlpha: Float = 0.35
    var readyStableFrames: Int = 5
    var holdSteadyFrames: Int = 6
    var lostDocumentGraceFrames: Int = 3
    var minDwellFrames: Int = 4
    // CQG additions.
    var maxGlareRatio: Float = 0.04
    var glareExitMargin: Float = 0.50
    var maxCornerVelocity: Float = 0.020
    var minPerCornerStability: Float = 0.55
    var edgeClipBlocking: Bool = false
    // Max allowed quad-centroid offset (half-extent fraction) before .offCenter
    // fires once framing otherwise passes. A non-positive value disables center
    // guidance — the Dart layer passes -1 when the consumer turns it off.
    var maxCenterOffset: Float = 0.12

    init() {}

    /// Rebuilds a config from the 19-float wire array produced by
    /// `SupyDocumentGuidanceConfiguration.toConfigFloatArray()` on the Dart
    /// side (passed through PlatformView creationParams). The index order MUST
    /// stay aligned with `toNumberArray()` below. Returns `nil` for a short or
    /// malformed array so the caller can fall back to the field defaults.
    init?(wireArray raw: [NSNumber]) {
        guard raw.count >= 19 else { return nil }
        minCoverageRatio = raw[0].floatValue
        maxCoverageRatio = raw[1].floatValue
        maxTiltDegrees = raw[2].floatValue
        minMeanLuma = raw[3].floatValue
        minBlurScore = raw[4].floatValue
        readyStabilityFloor = raw[5].floatValue
        interiorVarianceFloor = raw[6].floatValue
        exitMargin = raw[7].floatValue
        smoothingAlpha = raw[8].floatValue
        readyStableFrames = raw[9].intValue
        holdSteadyFrames = raw[10].intValue
        lostDocumentGraceFrames = raw[11].intValue
        minDwellFrames = raw[12].intValue
        maxGlareRatio = raw[13].floatValue
        glareExitMargin = raw[14].floatValue
        maxCornerVelocity = raw[15].floatValue
        minPerCornerStability = raw[16].floatValue
        edgeClipBlocking = raw[17].floatValue != 0
        maxCenterOffset = raw[18].floatValue
    }

    /// Packs the 19 thresholds in the wire-coupled order the bridge unpacks by
    /// index. Mirrors `GuidanceConfig.toFloatArray()` in `SupyNativeCore.kt` —
    /// keep both and the C++ JNI/Obj-C++ shims in sync.
    func toNumberArray() -> [NSNumber] {
        return [
            NSNumber(value: minCoverageRatio), NSNumber(value: maxCoverageRatio),
            NSNumber(value: maxTiltDegrees), NSNumber(value: minMeanLuma),
            NSNumber(value: minBlurScore), NSNumber(value: readyStabilityFloor),
            NSNumber(value: interiorVarianceFloor), NSNumber(value: exitMargin),
            NSNumber(value: smoothingAlpha),
            NSNumber(value: Float(readyStableFrames)),
            NSNumber(value: Float(holdSteadyFrames)),
            NSNumber(value: Float(lostDocumentGraceFrames)),
            NSNumber(value: Float(minDwellFrames)),
            // CQG additions — packed after the existing 13 floats.
            NSNumber(value: maxGlareRatio), NSNumber(value: glareExitMargin),
            NSNumber(value: maxCornerVelocity),
            NSNumber(value: minPerCornerStability),
            NSNumber(value: edgeClipBlocking ? Float(1.0) : Float(0.0)),
            NSNumber(value: maxCenterOffset),
        ]
    }
}

/// Swift facade over the stateful `SupyDocumentGuidance` bridge. Holds the
/// classifier state across frames — the iOS twin of Android's handle owned by
/// `SupyNativeCore.guidanceCreate`/`guidanceClassify`. Worker-thread only;
/// not safe for concurrent `classify` calls on the same instance.
final class GuidanceClassifier {
    private let bridge = SupyDocumentGuidance()

    /// Resets the classifier to its initial NoDocument step.
    func reset() {
        bridge.reset()
    }

    /// Classifies a single frame. Falls back to a `.noDocument` / 0.0 pair on a
    /// short/empty return so callers degrade gracefully — mirrors
    /// `guidanceClassify` in `SupyNativeCore.kt`.
    func classify(
        _ metrics: GuidanceFrameMetrics,
        config: GuidanceConfig
    ) -> GuidanceClassifyResult {
        let perCorner: [NSNumber] = metrics.hasPerCornerStability
            ? metrics.perCornerStability.map { NSNumber(value: $0) }
            : []
        let packed = bridge.classifyHasDocument(
            metrics.hasDocument,
            clipsEdge: metrics.clipsEdge,
            coverage: metrics.coverageRatio,
            tilt: metrics.tiltDegrees,
            luma: metrics.meanLuma,
            blur: metrics.blurScore,
            stability: metrics.quadStability,
            interior: metrics.interiorVariance,
            glareRatio: metrics.glareRatio,
            cornerVelocity: metrics.cornerVelocity,
            centerOffsetX: metrics.centerOffsetX,
            centerOffsetY: metrics.centerOffsetY,
            perCornerStability: perCorner,
            config: config.toNumberArray()
        )
        guard packed.count >= 2 else {
            return GuidanceClassifyResult(state: .noDocument, liveQualityScore: 0.0)
        }
        return GuidanceClassifyResult(
            state: GuidanceFrameState.fromOrdinal(packed[0].int32Value),
            liveQualityScore: packed[1].floatValue
        )
    }
}
