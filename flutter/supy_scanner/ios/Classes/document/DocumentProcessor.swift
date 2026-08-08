import CoreImage
import UIKit
import Vision

/// Configuration for the enterprise document pipeline. Mirrors the Dart
/// `DocumentProcessingOptions` wire shape (nested under the `processing` key of
/// the `scanDocument` args). Every field has a default that reproduces the
/// paper-preserving "color" scan; callers opt into B&W / different crops.
struct DocumentProcessingOptions {
  /// Run document/corner detection when no seed quad is supplied.
  var detectDocument: Bool
  /// Warp the detected quad to a rectangle (perspective correction).
  var perspectiveCorrection: Bool
  /// Crop to the detected document (drops finger / table / letterbox).
  var autoCrop: Bool
  /// Fraction each corner is bled outward before the warp so the outermost
  /// text/edge survives. Clamped to the image.
  var cropMargin: CGFloat
  /// Correct residual small-angle skew after cropping (CIStraighten).
  var deskew: Bool
  /// Flatten uneven lighting / shadow gradients (divide-by-blur).
  var shadowRemoval: Bool
  /// Push near-neutral paper toward white while preserving colored stamps /
  /// signatures / logos.
  var backgroundWhitening: Bool
  /// Output look. `.color` (default) / `.grayscale` / `.blackAndWhite`
  /// (Sauvola adaptive threshold) / `.original` (skip enhancement).
  var filter: SupyDocumentFilter
  /// Light edge-preserving denoise.
  var denoise: Bool
  /// Halo-safe unsharp sharpening.
  var sharpen: Bool
  /// Longest-edge cap for the exported image in pixels. `0` = no cap. Keeps
  /// files small while staying OCR-legible (~2200 px ≈ 300 DPI on A4).
  var maxDimension: Int
  /// JPEG quality (0–100) applied by the caller when encoding.
  var quality: Int

  /// v1.0-equivalent color scan with detection + crop + smart resize enabled.
  static let `default` = DocumentProcessingOptions(
    detectDocument: true,
    perspectiveCorrection: true,
    autoCrop: true,
    cropMargin: 0.02,
    deskew: true,
    shadowRemoval: true,
    backgroundWhitening: true,
    filter: .color,
    denoise: true,
    sharpen: true,
    maxDimension: 2200,
    quality: 95
  )

  /// Parses the nested `processing` map from the `scanDocument` args. Missing
  /// keys fall back to `.default`; `filter` falls back to the top-level
  /// `filter` arg so existing callers keep their look without a `processing`
  /// block. `quality` falls back to the top-level `jpegQuality`.
  static func parse(
    _ args: [String: Any]?,
    fallbackFilter: SupyDocumentFilter,
    fallbackQuality: Int
  ) -> DocumentProcessingOptions {
    var opts = DocumentProcessingOptions.default
    opts.filter = fallbackFilter
    opts.quality = fallbackQuality

    guard let map = args?["processing"] as? [String: Any] else { return opts }

    if let v = map["detectDocument"] as? Bool { opts.detectDocument = v }
    if let v = map["perspectiveCorrection"] as? Bool { opts.perspectiveCorrection = v }
    if let v = map["autoCrop"] as? Bool { opts.autoCrop = v }
    if let v = map["cropMargin"] as? Double { opts.cropMargin = CGFloat(v) }
    if let v = map["deskew"] as? Bool { opts.deskew = v }
    if let v = map["shadowRemoval"] as? Bool { opts.shadowRemoval = v }
    if let v = map["backgroundWhitening"] as? Bool { opts.backgroundWhitening = v }
    if let v = map["denoise"] as? Bool { opts.denoise = v }
    if let v = map["sharpen"] as? Bool { opts.sharpen = v }
    if let v = map["maxDimension"] as? Int { opts.maxDimension = v }
    if let v = map["enhancement"] as? String {
      opts.filter = SupyDocumentFilter.parse(v)
    }
    if let v = map["quality"] as? Int { opts.quality = v }
    return opts
  }
}

/// The shared, decode-once/encode-once document pipeline. One orchestrator for
/// both iOS capture paths (VisionKit still + embedded AVFoundation still): it
/// composes detection (`DocumentStillRefiner`), perspective/crop
/// (`DocumentRectifyPipeline` / direct warp), deskew, the enhancement chain
/// (`DocumentEnhancer`), and a smart resize — reusing the shared `CIContext`
/// so a page is decoded to a `CGImage`, transformed entirely in Core Image,
/// and rendered exactly once.
///
/// Pure w.r.t. Flutter: call on a background queue; the caller owns encoding
/// and the channel boundary.
enum DocumentProcessor {

  /// Runs the full pipeline over [image] and returns the processed page.
  ///
  /// - [seedQuad]/[analyzerSize]: the embedded view's analyzer-space quad and
  ///   the analyzer buffer size. When both are supplied the crop is driven by
  ///   that quad (refined on-still); otherwise the still is detected from
  ///   scratch (the VisionKit path, which has no preview seed).
  ///
  /// Never throws away a page: any stage that fails falls back to the prior
  /// image, so the worst case is the un-processed capture.
  static func process(
    _ image: UIImage,
    seedQuad: [CGPoint]? = nil,
    analyzerSize: CGSize? = nil,
    options: DocumentProcessingOptions,
    context: CIContext = DocumentEnhancer.sharedContext
  ) -> UIImage {
    guard let cg = image.cgImage ?? cgImage(from: image) else { return image }

    // Bake EXIF orientation into a working CIImage so quads (top-left origin)
    // and pixels agree for the rest of the pipeline.
    let base = CIImage(cgImage: cg)
    let oriented = orientedForCurrentImage(base, image: image)

    // Stages 1–4: detect → perspective-correct → crop.
    var working = oriented
    var cropped = false
    if options.perspectiveCorrection || options.autoCrop {
      if let seed = seedQuad, let asize = analyzerSize, seed.count == 4 {
        // Embedded path: map the preview quad into still space + refine.
        if let out = DocumentRectifyPipeline.rectify(
          still: oriented,
          analyzerQuad: seed,
          analyzerSize: asize,
          context: context
        ) {
          working = CIImage(cgImage: out.image)
          cropped = true
        }
      } else if options.detectDocument {
        // VisionKit / import path: detect the largest document quad on the
        // full-res still and warp it.
        if let quad = DocumentStillRefiner.detectBestQuad(still: oriented) {
          let expanded = DocumentRectifyPipeline.expandQuad(quad, by: options.cropMargin)
          if let warped = warp(oriented, quad: expanded, context: context) {
            working = warped
            cropped = true
          }
        }
      }
    }

    // Stage 5: deskew. Redundant once we've warped a detected quad (output is
    // axis-aligned), so only run it on the un-cropped fallback.
    if options.deskew && !cropped {
      working = deskew(working) ?? working
    }

    // Stage 9 (moved early): smart resize. Capping here means every downstream
    // filter runs on the export-sized image — faster, and Sauvola/denoise are
    // tuned for output resolution rather than a 12MP sensor frame.
    working = resize(working, maxDimension: options.maxDimension) ?? working

    // Stages 6–8 + 2–3: illumination/shadow, whitening, contrast, filter,
    // denoise, sharpen — all inside DocumentEnhancer, rendered once.
    return DocumentEnhancer.enhance(working, options: options, like: image, context: context)
      ?? render(working, like: image, context: context)
      ?? image
  }

  /// Enhancement tail only — smart resize + the `DocumentEnhancer` chain — for
  /// inputs that are already detected, cropped and upright (the embedded
  /// rectify path, which owns its own quad + metadata via
  /// `DocumentRectifyPipeline`). Skips detection/crop/deskew so the caller's
  /// quad stays authoritative.
  static func enhanceOnly(
    _ image: UIImage,
    options: DocumentProcessingOptions,
    context: CIContext = DocumentEnhancer.sharedContext
  ) -> UIImage {
    guard let cg = image.cgImage ?? cgImage(from: image) else { return image }
    var working = CIImage(cgImage: cg)
    working = resize(working, maxDimension: options.maxDimension) ?? working
    return DocumentEnhancer.enhance(working, options: options, like: image, context: context)
      ?? render(working, like: image, context: context)
      ?? image
  }

  // MARK: - Perspective

  /// Warps [oriented] so [quad] (normalized [0,1], top-left origin, TL/TR/BR/BL)
  /// becomes an axis-aligned rectangle. Mirrors `DocumentRectifyPipeline`'s warp
  /// but takes a quad already in the still's own space (no preview mapping).
  private static func warp(
    _ oriented: CIImage,
    quad: [CGPoint],
    context: CIContext
  ) -> CIImage? {
    guard quad.count == 4 else { return nil }
    let size = oriented.extent.size
    guard size.width > 0, size.height > 0 else { return nil }
    guard let filter = CIFilter(name: "CIPerspectiveCorrection") else { return nil }
    let w = size.width
    let h = size.height
    // Quad is top-left origin; CIImage is bottom-left — flip Y once.
    let tl = CGPoint(x: quad[0].x * w, y: (1 - quad[0].y) * h)
    let tr = CGPoint(x: quad[1].x * w, y: (1 - quad[1].y) * h)
    let br = CGPoint(x: quad[2].x * w, y: (1 - quad[2].y) * h)
    let bl = CGPoint(x: quad[3].x * w, y: (1 - quad[3].y) * h)
    filter.setValue(oriented, forKey: kCIInputImageKey)
    filter.setValue(CIVector(cgPoint: tl), forKey: "inputTopLeft")
    filter.setValue(CIVector(cgPoint: tr), forKey: "inputTopRight")
    filter.setValue(CIVector(cgPoint: bl), forKey: "inputBottomLeft")
    filter.setValue(CIVector(cgPoint: br), forKey: "inputBottomRight")
    guard let out = filter.outputImage else { return nil }
    // Re-origin to (0,0) so downstream extents stay sane.
    return out.transformed(by: CGAffineTransform(
      translationX: -out.extent.origin.x, y: -out.extent.origin.y))
  }

  // MARK: - Deskew

  /// Corrects small residual rotation by detecting the dominant rectangle and
  /// straightening by its edge angle. Only acts on angles below ~7° (larger
  /// angles mean detection is unreliable — leave the page as-is rather than
  /// rotate garbage).
  private static func deskew(_ input: CIImage) -> CIImage? {
    guard let angle = estimateSkew(input) else { return nil }
    guard abs(angle) > 0.005, abs(angle) < 0.12 else { return nil } // ~0.3°..7°
    let straighten = CIFilter(name: "CIStraightenFilter")
    straighten?.setValue(input, forKey: kCIInputImageKey)
    straighten?.setValue(-angle, forKey: kCIInputAngleKey)
    guard let out = straighten?.outputImage else { return nil }
    return out.transformed(by: CGAffineTransform(
      translationX: -out.extent.origin.x, y: -out.extent.origin.y))
  }

  /// Radians the top edge of the dominant document rectangle is rotated from
  /// horizontal. Positive == counter-clockwise. `nil` when nothing is found.
  private static func estimateSkew(_ input: CIImage) -> CGFloat? {
    let request = VNDetectRectanglesRequest()
    request.maximumObservations = 1
    request.minimumConfidence = 0.6
    request.minimumAspectRatio = 0.3
    let handler = VNImageRequestHandler(ciImage: input, options: [:])
    do { try handler.perform([request]) } catch { return nil }
    guard let obs = (request.results as? [VNRectangleObservation])?.first else { return nil }
    // Vision points are bottom-left origin, normalized. Top edge slope:
    let dx = obs.topRight.x - obs.topLeft.x
    let dy = obs.topRight.y - obs.topLeft.y
    guard dx != 0 || dy != 0 else { return nil }
    return atan2(dy, dx)
  }

  // MARK: - Resize

  /// Lanczos-scales [input] so its longest edge is at most [maxDimension] px.
  /// No-op when [maxDimension] is `0` or the image already fits.
  private static func resize(_ input: CIImage, maxDimension: Int) -> CIImage? {
    guard maxDimension > 0 else { return nil }
    let extent = input.extent
    let longest = max(extent.width, extent.height)
    guard longest > CGFloat(maxDimension) else { return nil }
    let scale = CGFloat(maxDimension) / longest
    let lanczos = CIFilter(name: "CILanczosScaleTransform")
    lanczos?.setValue(input, forKey: kCIInputImageKey)
    lanczos?.setValue(scale, forKey: kCIInputScaleKey)
    lanczos?.setValue(1.0, forKey: kCIInputAspectRatioKey)
    guard let out = lanczos?.outputImage else { return nil }
    return out.transformed(by: CGAffineTransform(
      translationX: -out.extent.origin.x, y: -out.extent.origin.y))
  }

  // MARK: - Rendering helpers

  static func render(
    _ ciImage: CIImage,
    like template: UIImage,
    context: CIContext
  ) -> UIImage? {
    let extent = ciImage.extent
    guard extent.width > 0, extent.height > 0 else { return nil }
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    guard let cg = context.createCGImage(
      ciImage, from: extent, format: .RGBA8, colorSpace: colorSpace
    ) else { return nil }
    // Orientation is already baked into the pixels — emit `.up` at scale 1.
    return UIImage(cgImage: cg, scale: 1, orientation: .up)
  }

  private static func orientedForCurrentImage(_ ci: CIImage, image: UIImage) -> CIImage {
    let exif = cgOrientation(image.imageOrientation)
    return exif == .up ? ci : ci.oriented(exif)
  }

  private static func cgOrientation(_ o: UIImage.Orientation) -> CGImagePropertyOrientation {
    switch o {
    case .up: return .up
    case .down: return .down
    case .left: return .left
    case .right: return .right
    case .upMirrored: return .upMirrored
    case .downMirrored: return .downMirrored
    case .leftMirrored: return .leftMirrored
    case .rightMirrored: return .rightMirrored
    @unknown default: return .up
    }
  }

  private static func cgImage(from image: UIImage) -> CGImage? {
    if let direct = image.cgImage { return direct }
    let size = image.size
    UIGraphicsBeginImageContextWithOptions(size, false, image.scale)
    defer { UIGraphicsEndImageContext() }
    image.draw(in: CGRect(origin: .zero, size: size))
    return UIGraphicsGetImageFromCurrentImageContext()?.cgImage
  }
}
