import Accelerate
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

/// Per-page visual filter applied after VisionKit returns its capture.
///
/// Mirrors the Dart `SupyDocumentFilter` enum names exactly. This is the
/// surface that produces Scanbot-class output: VisionKit auto-enhances toward
/// pure white and crushes midtones, so for every filter except `.original`
/// we re-process the page through Core Image + vImage.
enum SupyDocumentFilter: String {
  case color
  case grayscale
  case blackAndWhite
  case original

  static func parse(_ wire: String?) -> SupyDocumentFilter {
    switch wire?.lowercased() {
    case "grayscale": return .grayscale
    case "blackandwhite", "black_and_white": return .blackAndWhite
    case "original", "none": return .original
    default: return .color
    }
  }
}

/// Re-processes VisionKit's washed-out output into a Scanbot-class scan:
/// preserves paper tone, lifts text contrast, normalizes illumination, crisps
/// edges. All work runs synchronously on the caller's queue; callers must
/// invoke from a background queue (the document presenter's `ioQueue`).
enum DocumentEnhancer {

  /// Lazy shared context — Core Image context creation is non-trivial (Metal
  /// device init, ~50–100ms) and we want it reused across pages within a
  /// scan session AND across the live preview / rectify path in
  /// `SupyDocumentScannerView`. Re-creating it per page or per view is the
  /// kind of thing that produces visible UI hitches.
  static let sharedContext: CIContext = {
    return CIContext(options: [
      .useSoftwareRenderer: false,
      .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any,
    ])
  }()

  /// Applies the chain for [filter] to [image] and returns the result. On
  /// any failure the original image is returned unchanged — we never lose
  /// a page over a filter glitch.
  static func enhance(_ image: UIImage, filter: SupyDocumentFilter) -> UIImage {
    guard filter != .original else { return image }
    guard let cg = image.cgImage ?? cgImage(from: image) else { return image }
    let ciImage = CIImage(cgImage: cg)

    switch filter {
    case .color:
      return render(applyColorChain(ciImage), like: image) ?? image
    case .grayscale:
      let colored = applyColorChain(ciImage)
      let desaturated = applySaturation(colored, saturation: 0)
      return render(desaturated, like: image) ?? image
    case .blackAndWhite:
      let normalized = applyIlluminationFlatten(ciImage)
      let stretched = applyToneCurve(normalized, paperPoint: 0.92, textLift: 0.10)
      let mono = applySaturation(stretched, saturation: 0)
      return binarize(mono, like: image) ?? render(mono, like: image) ?? image
    case .original:
      return image
    }
  }

  // MARK: - Chains

  /// The "color" chain — the new default. Goal: paper warmth preserved,
  /// text dark and crisp, illumination flat. Five stages: illumination
  /// flatten → tone curve → unsharp mask → mild saturation lift.
  private static func applyColorChain(_ input: CIImage) -> CIImage {
    let flattened = applyIlluminationFlatten(input)
    let toned = applyToneCurve(flattened, paperPoint: 0.96, textLift: 0.18)
    let sharp = applyUnsharpMask(toned, radius: 1.5, intensity: 0.6)
    let saturated = applySaturation(sharp, saturation: 1.05)
    return saturated
  }

  // MARK: - Filter stages

  /// Divides the image by a heavily-blurred copy of itself to remove
  /// shadow gradients and uneven lighting. The trick: scale the blur by
  /// the page's mean luminance so we lift dark areas without bleaching.
  private static func applyIlluminationFlatten(_ input: CIImage) -> CIImage {
    let extent = input.extent
    let shortEdge = min(extent.width, extent.height)
    // Box-blur radius proportional to page size — ~ 1/30 of the short edge.
    // Big enough to smooth out lighting, small enough not to blur text.
    let radius = max(15.0, shortEdge / 30.0)

    let blur = CIFilter.boxBlur()
    blur.inputImage = input.clampedToExtent()
    blur.radius = Float(radius)
    guard let blurred = blur.outputImage?.cropped(to: extent) else { return input }

    // divide-blend: input / blurred. Core Image's "CIDivideBlendMode" expects
    // background ÷ foreground, so background=input, foreground=blurred.
    let divide = CIFilter.divideBlendMode()
    divide.inputImage = blurred
    divide.backgroundImage = input
    guard let divided = divide.outputImage else { return input }

    // The divide tends to push the image very bright; pull it back to ~92%
    // of full white so paper tone survives. CIColorMatrix scales RGB.
    let scale: CGFloat = 0.92
    let scaler = CIFilter.colorMatrix()
    scaler.inputImage = divided
    scaler.rVector = CIVector(x: scale, y: 0, z: 0, w: 0)
    scaler.gVector = CIVector(x: 0, y: scale, z: 0, w: 0)
    scaler.bVector = CIVector(x: 0, y: 0, z: scale, w: 0)
    scaler.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
    return scaler.outputImage ?? divided
  }

  /// Tone curve that anchors paper at ~paperPoint (NOT 1.0) and lifts the
  /// quarter-tones by textLift. The 0.96 endpoint is what keeps the page
  /// from clipping to pure white — the single biggest delta vs VisionKit's
  /// default tone mapping.
  private static func applyToneCurve(
    _ input: CIImage,
    paperPoint: CGFloat,
    textLift: CGFloat
  ) -> CIImage {
    let curve = CIFilter.toneCurve()
    curve.inputImage = input
    curve.point0 = CGPoint(x: 0.00, y: 0.00)
    curve.point1 = CGPoint(x: 0.25, y: max(0.0, 0.25 - textLift))
    curve.point2 = CGPoint(x: 0.50, y: 0.50)
    curve.point3 = CGPoint(x: 0.75, y: 0.85)
    curve.point4 = CGPoint(x: 1.00, y: paperPoint)
    return curve.outputImage ?? input
  }

  private static func applyUnsharpMask(
    _ input: CIImage,
    radius: Double,
    intensity: Double
  ) -> CIImage {
    let sharpen = CIFilter.unsharpMask()
    sharpen.inputImage = input
    sharpen.radius = Float(radius)
    sharpen.intensity = Float(intensity)
    return sharpen.outputImage ?? input
  }

  private static func applySaturation(_ input: CIImage, saturation: Double) -> CIImage {
    let ctrl = CIFilter.colorControls()
    ctrl.inputImage = input
    ctrl.saturation = Float(saturation)
    ctrl.brightness = 0
    ctrl.contrast = 1.0
    return ctrl.outputImage ?? input
  }

  // MARK: - Binarization (B&W filter)

  /// Mean-threshold binarization with a local box-blur reference.
  /// Approximates Sauvola: a pixel is black if it sits below
  /// `(localMean - bias)`. Cheap, robust, and produces the crisp
  /// black-on-white look users expect from a "B&W" filter.
  private static func binarize(_ input: CIImage, like template: UIImage) -> UIImage? {
    let extent = input.extent
    let shortEdge = min(extent.width, extent.height)
    let radius = max(20.0, shortEdge / 24.0)

    let blur = CIFilter.boxBlur()
    blur.inputImage = input.clampedToExtent()
    blur.radius = Float(radius)
    guard let blurred = blur.outputImage?.cropped(to: extent) else { return nil }

    // Subtract: input - (blurred - bias). Pixels darker than local mean by
    // more than bias survive as ink; everything else clamps to white.
    let bias: CGFloat = 0.08
    let biasShift = CIFilter.colorMatrix()
    biasShift.inputImage = blurred
    biasShift.rVector = CIVector(x: 1, y: 0, z: 0, w: 0)
    biasShift.gVector = CIVector(x: 0, y: 1, z: 0, w: 0)
    biasShift.bVector = CIVector(x: 0, y: 0, z: 1, w: 0)
    biasShift.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
    biasShift.biasVector = CIVector(x: -bias, y: -bias, z: -bias, w: 0)
    guard let biased = biasShift.outputImage else { return nil }

    // Difference: input < biased → ink. Use CIColorThreshold-like math via
    // subtract + clamp + invert + threshold.
    let diff = CIFilter.subtractBlendMode()
    diff.inputImage = biased
    diff.backgroundImage = input
    guard let difference = diff.outputImage else { return nil }

    // Hard threshold at 0.5 — anything brighter than mid-grey becomes black
    // ink, the rest becomes paper.
    let threshold = CIFilter.colorMatrix()
    threshold.inputImage = difference
    let big: CGFloat = 8
    threshold.rVector = CIVector(x: big, y: 0, z: 0, w: 0)
    threshold.gVector = CIVector(x: 0, y: big, z: 0, w: 0)
    threshold.bVector = CIVector(x: 0, y: 0, z: big, w: 0)
    threshold.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
    threshold.biasVector = CIVector(x: -3, y: -3, z: -3, w: 0)
    guard let thresholded = threshold.outputImage?.cropped(to: extent) else { return nil }

    return render(thresholded, like: template)
  }

  // MARK: - Rendering

  /// Renders [ciImage] back to a UIImage that matches [template]'s scale
  /// and orientation. Uses an sRGB-tagged CGImage so JPEG encoding doesn't
  /// re-interpret the color space.
  private static func render(_ ciImage: CIImage, like template: UIImage) -> UIImage? {
    let extent = ciImage.extent
    guard extent.width > 0, extent.height > 0 else { return nil }
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    guard let cg = sharedContext.createCGImage(ciImage, from: extent, format: .RGBA8, colorSpace: colorSpace)
    else { return nil }
    return UIImage(cgImage: cg, scale: template.scale, orientation: template.imageOrientation)
  }

  /// Last-resort UIImage → CGImage path (e.g. CIImage-backed images).
  private static func cgImage(from image: UIImage) -> CGImage? {
    if let direct = image.cgImage { return direct }
    let size = image.size
    UIGraphicsBeginImageContextWithOptions(size, false, image.scale)
    defer { UIGraphicsEndImageContext() }
    image.draw(in: CGRect(origin: .zero, size: size))
    return UIGraphicsGetImageFromCurrentImageContext()?.cgImage
  }
}
