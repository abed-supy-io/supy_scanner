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

  // MARK: - Pipeline entry (DocumentProcessor)

  /// CIImage-based enhancement used by `DocumentProcessor` after detection,
  /// crop, deskew and resize have run. [input]'s pixels are already upright
  /// (orientation baked in), so the result is rendered `.up` at scale 1 — never
  /// re-orient here. Honors the [options] flags; returns `nil` only when Core
  /// Image cannot produce an image at all (caller falls back to the input).
  static func enhance(
    _ input: CIImage,
    options: DocumentProcessingOptions,
    like template: UIImage,
    context: CIContext
  ) -> UIImage? {
    guard options.filter != .original else {
      return DocumentProcessor.render(input, like: template, context: context)
    }

    // Stage 2: light edge-preserving denoise (before contrast, so we don't
    // amplify sensor grain in the tone curve).
    var working = options.denoise ? applyDenoise(input) : input

    // Stage 6: illumination / shadow flatten.
    if options.shadowRemoval {
      working = applyIlluminationFlatten(working)
    }

    switch options.filter {
    case .color, .grayscale:
      // Stage 7: contrast. Whitening lets us push the paper endpoint higher.
      working = applyToneCurve(
        working,
        paperPoint: options.backgroundWhitening ? 0.99 : 0.96,
        textLift: 0.18
      )
      // Stage 8a: color-safe background whitening (keeps colored stamps/logos).
      if options.backgroundWhitening {
        working = applyBackgroundWhitening(working)
      }
      // Stage 3: halo-safe sharpen.
      if options.sharpen {
        working = applyUnsharpMask(working, radius: 1.2, intensity: 0.5)
      }
      let saturation: Double = options.filter == .grayscale ? 0 : 1.05
      working = applySaturation(working, saturation: saturation)
      return DocumentProcessor.render(working, like: template, context: context)

    case .blackAndWhite:
      // Stage 8b: Sauvola adaptive threshold on the normalized page.
      working = applyToneCurve(working, paperPoint: 0.94, textLift: 0.12)
      working = applySaturation(working, saturation: 0)
      return sauvolaBinarize(working, like: template, context: context)
        ?? binarize(working, like: template)
        ?? DocumentProcessor.render(working, like: template, context: context)

    case .original:
      return DocumentProcessor.render(input, like: template, context: context)
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

  // MARK: - Denoise

  /// Mild edge-preserving denoise. Keeps text edges (low `noiseLevel`) while
  /// smoothing flat paper before the contrast stage amplifies grain.
  private static func applyDenoise(_ input: CIImage) -> CIImage {
    let nr = CIFilter.noiseReduction()
    nr.inputImage = input
    nr.noiseLevel = 0.02
    nr.sharpness = 0.4
    return nr.outputImage ?? input
  }

  // MARK: - Background whitening (color-preserving)

  /// Pushes bright, near-neutral paper toward pure white while leaving
  /// saturated regions (colored stamps, signatures, logos) untouched.
  ///
  /// The mask is `neutrality × brightness`: a pixel is whitened only where it
  /// is both low-chroma (so red/blue ink survives) and already light (so black
  /// text survives). We blend toward white through that mask — this is the
  /// chroma-gated alternative to a per-channel levels stretch, which would
  /// bleach colored ink.
  private static func applyBackgroundWhitening(
    _ input: CIImage,
    strength: CGFloat = 0.9
  ) -> CIImage {
    let extent = input.extent
    guard extent.width > 0, extent.height > 0 else { return input }

    // Luminance copy (all channels = perceptual gray).
    let gray = applySaturation(input, saturation: 0)

    // Chroma magnitude = |input − gray|, amplified and summed into every
    // channel so it reads as a single scalar per pixel.
    let diff = CIFilter.differenceBlendMode()
    diff.inputImage = input
    diff.backgroundImage = gray
    guard let chroma = diff.outputImage else { return input }

    let amplify: CGFloat = 4.0
    let chromaMag = CIFilter.colorMatrix()
    chromaMag.inputImage = chroma
    chromaMag.rVector = CIVector(x: amplify, y: amplify, z: amplify, w: 0)
    chromaMag.gVector = CIVector(x: amplify, y: amplify, z: amplify, w: 0)
    chromaMag.bVector = CIVector(x: amplify, y: amplify, z: amplify, w: 0)
    chromaMag.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
    guard let chromaMagImg = chromaMag.outputImage else { return input }

    // neutral = 1 − chroma (high where the pixel is near-gray).
    let neutral = CIFilter.colorMatrix()
    neutral.inputImage = chromaMagImg
    neutral.rVector = CIVector(x: -1, y: 0, z: 0, w: 0)
    neutral.gVector = CIVector(x: 0, y: -1, z: 0, w: 0)
    neutral.bVector = CIVector(x: 0, y: 0, z: -1, w: 0)
    neutral.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
    neutral.biasVector = CIVector(x: 1, y: 1, z: 1, w: 0)
    guard let neutralRaw = neutral.outputImage else { return input }

    // mask = neutral × brightness (paper only), clamped and scaled by strength.
    let mult = CIFilter.multiplyBlendMode()
    mult.inputImage = neutralRaw
    mult.backgroundImage = gray
    guard let maskRaw = mult.outputImage else { return input }

    let clamp = CIFilter.colorClamp()
    clamp.inputImage = maskRaw
    clamp.minComponents = CIVector(x: 0, y: 0, z: 0, w: 0)
    clamp.maxComponents = CIVector(x: 1, y: 1, z: 1, w: 1)
    guard let maskClamped = clamp.outputImage else { return input }

    let scale = CIFilter.colorMatrix()
    scale.inputImage = maskClamped
    scale.rVector = CIVector(x: strength, y: 0, z: 0, w: 0)
    scale.gVector = CIVector(x: 0, y: strength, z: 0, w: 0)
    scale.bVector = CIVector(x: 0, y: 0, z: strength, w: 0)
    scale.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
    guard let mask = scale.outputImage else { return input }

    // Blend white over the original through the mask's red channel.
    let white = CIFilter.constantColorGenerator()
    white.color = CIColor(red: 1, green: 1, blue: 1)
    guard let whiteImg = white.outputImage?.cropped(to: extent) else { return input }

    let blend = CIFilter.blendWithRedMask()
    blend.inputImage = whiteImg
    blend.backgroundImage = input
    blend.maskImage = mask
    return blend.outputImage?.cropped(to: extent) ?? input
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

  // MARK: - Sauvola adaptive threshold

  /// True Sauvola binarization: per-pixel threshold
  /// `T = m·(1 + k·(s/R − 1))` over a local window, where `m`/`s` are the
  /// local mean/standard deviation. Preferred over the box-blur `binarize`
  /// for text: it survives uneven lighting and faint strokes.
  ///
  /// Renders [input] to a single-channel grayscale buffer, computes the local
  /// stats with summed-area tables (O(pixels), window-size-independent), and
  /// emits a 1-bit-look grayscale `CGImage`. Pixels are already upright, so the
  /// result is `.up` at scale 1. Returns `nil` on any allocation/context
  /// failure so the caller can fall back.
  private static func sauvolaBinarize(
    _ input: CIImage,
    like template: UIImage,
    context: CIContext
  ) -> UIImage? {
    let extent = input.extent
    let width = Int(extent.width.rounded())
    let height = Int(extent.height.rounded())
    guard width > 1, height > 1 else { return nil }
    guard let cg = context.createCGImage(input, from: extent) else { return nil }

    let gray = CGColorSpaceCreateDeviceGray()
    let count = width * height
    var src = [UInt8](repeating: 0, count: count)
    let drawn: Bool = src.withUnsafeMutableBytes { raw -> Bool in
      guard let base = raw.baseAddress,
            let ctx = CGContext(
              data: base, width: width, height: height,
              bitsPerComponent: 8, bytesPerRow: width, space: gray,
              bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
      ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
      return true
    }
    guard drawn else { return nil }

    // Summed-area tables (Double for exact sums over up to ~6.5M pixels).
    let iw = width + 1
    let ih = height + 1
    var sum = [Double](repeating: 0, count: iw * ih)
    var sqSum = [Double](repeating: 0, count: iw * ih)
    src.withUnsafeBufferPointer { s in
      sum.withUnsafeMutableBufferPointer { I in
        sqSum.withUnsafeMutableBufferPointer { I2 in
          for y in 0..<height {
            var rowSum = 0.0
            var rowSqSum = 0.0
            let srcRow = y * width
            let iRow = (y + 1) * iw
            let iPrev = y * iw
            for x in 0..<width {
              let v = Double(s[srcRow + x])
              rowSum += v
              rowSqSum += v * v
              I[iRow + x + 1] = I[iPrev + x + 1] + rowSum
              I2[iRow + x + 1] = I2[iPrev + x + 1] + rowSqSum
            }
          }
        }
      }
    }

    // Window radius ~ 1/40 of the short edge; k/R are the classic Sauvola
    // constants tuned for document text.
    let radius = max(7, min(width, height) / 40)
    let k = 0.34
    let R = 128.0

    var out = [UInt8](repeating: 0, count: count)
    sum.withUnsafeBufferPointer { I in
      sqSum.withUnsafeBufferPointer { I2 in
        src.withUnsafeBufferPointer { s in
          out.withUnsafeMutableBufferPointer { o in
            for y in 0..<height {
              let y0 = max(0, y - radius)
              let y1 = min(height, y + radius + 1)
              for x in 0..<width {
                let x0 = max(0, x - radius)
                let x1 = min(width, x + radius + 1)
                let area = Double((x1 - x0) * (y1 - y0))
                let a = I[y1 * iw + x1]
                let b = I[y0 * iw + x1]
                let c = I[y1 * iw + x0]
                let d = I[y0 * iw + x0]
                let s1 = a - b - c + d
                let a2 = I2[y1 * iw + x1]
                let b2 = I2[y0 * iw + x1]
                let c2 = I2[y1 * iw + x0]
                let d2 = I2[y0 * iw + x0]
                let s2 = a2 - b2 - c2 + d2
                let mean = s1 / area
                let variance = max(0, s2 / area - mean * mean)
                let std = variance.squareRoot()
                let threshold = mean * (1 + k * (std / R - 1))
                o[y * width + x] = Double(s[y * width + x]) > threshold ? 255 : 0
              }
            }
          }
        }
      }
    }

    return out.withUnsafeMutableBytes { raw -> UIImage? in
      guard let base = raw.baseAddress,
            let ctx = CGContext(
              data: base, width: width, height: height,
              bitsPerComponent: 8, bytesPerRow: width, space: gray,
              bitmapInfo: CGImageAlphaInfo.none.rawValue
            ),
            let outCG = ctx.makeImage() else { return nil }
      return UIImage(cgImage: outCG, scale: 1, orientation: .up)
    }
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
