import CoreGraphics
import UIKit
import XCTest

@testable import supy_scanner

/// Tests for `DocumentEnhancer` and the `SupyDocumentFilter` wire parser.
///
/// These are pure-logic tests — no VisionKit, no camera. We synthesize a
/// UIImage in memory, run the filter chain, then sample pixels off the
/// returned image and assert measurable properties:
///
/// - `.original` returns the input image untouched (identity).
/// - `.color` does NOT bleach paper to pure white — the tone-curve endpoint
///    at 0.96 should leave a bright-grey patch near ~245, not 255.
/// - `.grayscale` desaturates every pixel (R≈G≈B).
/// - `.blackAndWhite` produces a near-bimodal histogram (only near-0 or
///    near-255 luma).
/// - Every filter tolerates a 1×1 degenerate input without crashing.
final class DocumentEnhancerTests: XCTestCase {

  // MARK: - Wire parser

  func testParseDefaultsToColor() {
    XCTAssertEqual(SupyDocumentFilter.parse(nil), .color)
    XCTAssertEqual(SupyDocumentFilter.parse(""), .color)
    XCTAssertEqual(SupyDocumentFilter.parse("unknown"), .color)
    XCTAssertEqual(SupyDocumentFilter.parse("color"), .color)
  }

  func testParseAcceptsScanbotStyleAliases() {
    XCTAssertEqual(SupyDocumentFilter.parse("grayscale"), .grayscale)
    XCTAssertEqual(SupyDocumentFilter.parse("GRAYSCALE"), .grayscale)
    XCTAssertEqual(SupyDocumentFilter.parse("blackAndWhite"), .blackAndWhite)
    XCTAssertEqual(SupyDocumentFilter.parse("black_and_white"), .blackAndWhite)
    XCTAssertEqual(SupyDocumentFilter.parse("original"), .original)
    XCTAssertEqual(SupyDocumentFilter.parse("none"), .original)
  }

  // MARK: - Identity bypass

  func testOriginalReturnsInputUnchanged() {
    let input = makeSolidImage(width: 32, height: 32, rgb: (200, 200, 200))
    let output = DocumentEnhancer.enhance(input, filter: .original)
    // `.original` is an explicit no-op bypass — same UIImage instance back.
    XCTAssertTrue(output === input)
  }

  // MARK: - Color filter — paper-tone preservation

  /// On a uniform bright-grey patch (~230), the color chain must NOT push the
  /// page to pure white. The tone curve anchors paper at 0.96, so we expect
  /// the mean luma to land below 255 (with margin for the unsharp mask).
  func testColorFilterDoesNotBleachToPureWhite() {
    let input = makeSolidImage(width: 64, height: 64, rgb: (230, 228, 222))
    let output = DocumentEnhancer.enhance(input, filter: .color)
    let mean = meanRGB(of: output)
    // Paper-tone endpoint is 0.96 → ceiling ≈ 245. Allow headroom for
    // illumination flatten + unsharp ringing.
    XCTAssertLessThan(mean.r, 252, "color filter bleached red channel to ~white")
    XCTAssertLessThan(mean.g, 252, "color filter bleached green channel to ~white")
    XCTAssertLessThan(mean.b, 252, "color filter bleached blue channel to ~white")
    XCTAssertGreaterThan(mean.r, 200, "color filter crushed paper tone too dark")
  }

  // MARK: - Grayscale

  func testGrayscaleFilterDesaturatesOutput() {
    let input = makeSolidImage(width: 64, height: 64, rgb: (180, 120, 60))
    let output = DocumentEnhancer.enhance(input, filter: .grayscale)
    let mean = meanRGB(of: output)
    let spread = max(abs(mean.r - mean.g), max(abs(mean.g - mean.b), abs(mean.r - mean.b)))
    XCTAssertLessThan(spread, 4, "grayscale filter left channels separated (R=\(mean.r) G=\(mean.g) B=\(mean.b))")
  }

  // MARK: - Black & white

  /// B&W binarization should produce a near-bimodal histogram: nearly every
  /// pixel ends up either very dark (<32) or very bright (>224), with very
  /// few midtones. We seed a mid-grey input with a dark stripe so there's
  /// content for the threshold to find.
  func testBlackAndWhiteFilterProducesBimodalHistogram() {
    let input = makeStripedImage(width: 64, height: 64, bright: 220, dark: 60, stripe: 8)
    let output = DocumentEnhancer.enhance(input, filter: .blackAndWhite)
    let bins = lumaHistogramBins(of: output)
    let midtone = bins.midtone
    let total = bins.dark + bins.midtone + bins.bright
    XCTAssertGreaterThan(total, 0)
    // Less than 10% midtone pixels — the rest landed in the dark/bright bins.
    XCTAssertLessThan(Double(midtone) / Double(total), 0.1,
                      "B&W output not bimodal: dark=\(bins.dark) mid=\(bins.midtone) bright=\(bins.bright)")
  }

  // MARK: - Degenerate input

  func testAllFiltersTolerateOnePixelInput() {
    let tiny = makeSolidImage(width: 1, height: 1, rgb: (128, 128, 128))
    for filter in [SupyDocumentFilter.color, .grayscale, .blackAndWhite, .original] {
      let out = DocumentEnhancer.enhance(tiny, filter: filter)
      XCTAssertGreaterThan(out.size.width, 0, "filter \(filter) returned empty image")
      XCTAssertGreaterThan(out.size.height, 0, "filter \(filter) returned empty image")
    }
  }

  // MARK: - Image helpers

  private func makeSolidImage(width: Int, height: Int, rgb: (UInt8, UInt8, UInt8)) -> UIImage {
    return makeImage(width: width, height: height) { _, _ in rgb }
  }

  /// Horizontal stripes: every `stripe`-pixel band alternates dark/bright.
  private func makeStripedImage(width: Int, height: Int, bright: UInt8, dark: UInt8, stripe: Int) -> UIImage {
    return makeImage(width: width, height: height) { _, y in
      let v = (y / stripe) % 2 == 0 ? bright : dark
      return (v, v, v)
    }
  }

  private func makeImage(width: Int, height: Int, sample: (Int, Int) -> (UInt8, UInt8, UInt8)) -> UIImage {
    let bytesPerPixel = 4
    let bytesPerRow = width * bytesPerPixel
    var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
    for y in 0..<height {
      for x in 0..<width {
        let (r, g, b) = sample(x, y)
        let i = y * bytesPerRow + x * bytesPerPixel
        pixels[i + 0] = r
        pixels[i + 1] = g
        pixels[i + 2] = b
        pixels[i + 3] = 255
      }
    }
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    let bitmapInfo: CGBitmapInfo = [
      .byteOrder32Big,
      CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
    ]
    let provider = CGDataProvider(data: Data(pixels) as CFData)!
    let cg = CGImage(
      width: width, height: height,
      bitsPerComponent: 8, bitsPerPixel: 32,
      bytesPerRow: bytesPerRow,
      space: colorSpace,
      bitmapInfo: bitmapInfo,
      provider: provider,
      decode: nil, shouldInterpolate: false,
      intent: .defaultIntent
    )!
    return UIImage(cgImage: cg, scale: 1, orientation: .up)
  }

  /// Sample every pixel and return the mean R/G/B (0–255).
  private func meanRGB(of image: UIImage) -> (r: Int, g: Int, b: Int) {
    let pixels = readRGBA(image)
    var rSum = 0, gSum = 0, bSum = 0, count = 0
    var i = 0
    while i < pixels.count {
      rSum += Int(pixels[i + 0])
      gSum += Int(pixels[i + 1])
      bSum += Int(pixels[i + 2])
      count += 1
      i += 4
    }
    guard count > 0 else { return (0, 0, 0) }
    return (rSum / count, gSum / count, bSum / count)
  }

  /// Bucket each pixel's luma into dark (<32), bright (>224), or midtone.
  private func lumaHistogramBins(of image: UIImage) -> (dark: Int, midtone: Int, bright: Int) {
    let pixels = readRGBA(image)
    var dark = 0, mid = 0, bright = 0
    var i = 0
    while i < pixels.count {
      // Rec. 601 luma is close enough for a bimodality check.
      let luma = (Int(pixels[i + 0]) * 299
                  + Int(pixels[i + 1]) * 587
                  + Int(pixels[i + 2]) * 114) / 1000
      if luma < 32 { dark += 1 }
      else if luma > 224 { bright += 1 }
      else { mid += 1 }
      i += 4
    }
    return (dark, mid, bright)
  }

  /// Render `image` into a fresh RGBA8 sRGB bitmap so we can read pixels
  /// regardless of how Core Image returned it.
  private func readRGBA(_ image: UIImage) -> [UInt8] {
    guard let cg = image.cgImage else { return [] }
    let w = cg.width
    let h = cg.height
    let bytesPerRow = w * 4
    var buffer = [UInt8](repeating: 0, count: bytesPerRow * h)
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue
      | CGImageAlphaInfo.premultipliedLast.rawValue
    guard let ctx = CGContext(
      data: &buffer,
      width: w, height: h,
      bitsPerComponent: 8,
      bytesPerRow: bytesPerRow,
      space: colorSpace,
      bitmapInfo: bitmapInfo
    ) else { return [] }
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
    return buffer
  }
}
