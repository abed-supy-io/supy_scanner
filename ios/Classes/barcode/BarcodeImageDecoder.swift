import CoreGraphics
import Foundation
import UIKit
import Vision

/// One-shot still-image barcode decode backing the `decodeImage` channel
/// method.
///
/// Loads an image already on disk and decodes it with Vision (default) or the
/// bundled zxing-cpp core (`useNativeCore`). Emits maps identical in shape to
/// the live-preview detections (`DetectedBarcode.toMap()`).
///
/// All work runs on a background queue; the caller marshals `completion` to
/// main at the channel boundary.
enum BarcodeImageDecoder {

  private static let workQueue = DispatchQueue(
    label: "io.supy.scanner.decodeImage",
    qos: .userInitiated
  )

  static func decode(
    image: UIImage,
    wireFormats: [String],
    useNativeCore: Bool,
    completion: @escaping ([[String: Any?]]) -> Void
  ) {
    workQueue.async {
      guard let cgImage = image.cgImage else {
        completion([])
        return
      }
      let detections: [DetectedBarcode]
      if useNativeCore, SupyNativeCore.hasZxing(),
        let native = decodeWithNativeCore(cgImage, wireFormats: wireFormats)
      {
        detections = native
      } else {
        detections = decodeWithVision(cgImage, wireFormats: wireFormats)
      }
      completion(detections.map { $0.toMap() })
    }
  }

  private static func decodeWithVision(
    _ cgImage: CGImage,
    wireFormats: [String]
  ) -> [DetectedBarcode] {
    let request = VNDetectBarcodesRequest()
    if let symbologies = SymbologyMapper.toVisionSymbologies(wireFormats) {
      request.symbologies = symbologies
    }
    // Fixtures are upright; orientation normalization is out of scope for the
    // deterministic still-image path.
    let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
    do {
      try handler.perform([request])
    } catch {
      return []
    }
    guard let observations = request.results as? [VNBarcodeObservation] else {
      return []
    }
    let width = CGFloat(cgImage.width)
    let height = CGFloat(cgImage.height)
    return observations.compactMap { obs -> DetectedBarcode? in
      guard let raw = obs.payloadStringValue else { return nil }
      let wire = SymbologyMapper.visionToWire(obs.symbology, payload: raw)
      let box = visionRectToPixelRect(
        obs.boundingBox,
        imageWidth: width,
        imageHeight: height
      )
      return DetectedBarcode(rawValue: raw, format: wire, boundingBox: box)
    }
  }

  private static func decodeWithNativeCore(
    _ cgImage: CGImage,
    wireFormats: [String]
  ) -> [DetectedBarcode]? {
    let width = cgImage.width
    let height = cgImage.height
    guard width > 0, height > 0 else { return nil }

    // Draw into a grayscale bitmap context. The backing buffer is top-left
    // raster order (row 0 == top), matching the camera Y-plane convention the
    // core already consumes, so corner coordinates come back in top-left pixel
    // space — consistent with the Vision path above.
    var luma = [UInt8](repeating: 0, count: width * height)
    guard
      let ctx = CGContext(
        data: &luma,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width,
        space: CGColorSpaceCreateDeviceGray(),
        bitmapInfo: CGImageAlphaInfo.none.rawValue
      )
    else {
      return nil
    }
    ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

    let mask = SupyFormatMask.fromWireNames(wireFormats)
    let decoded = luma.withUnsafeBufferPointer { buf -> [NativeBarcode]? in
      guard let base = buf.baseAddress else { return nil }
      return SupyNativeCore.decodeBarcodes(
        luma: base,
        width: Int32(width),
        height: Int32(height),
        rowStride: Int32(width),
        formats: mask,
        tryHarder: true,
        tryRotate: true
      )
    }
    guard let decoded = decoded else { return nil }
    return decoded.map {
      DetectedBarcode(
        rawValue: $0.rawValue,
        format: $0.format,
        boundingBox: $0.boundingBox
      )
    }
  }

  /// Vision's bounding box is normalized with a bottom-left origin. Convert to
  /// pixel coords with a top-left origin to match the Android wire format.
  private static func visionRectToPixelRect(
    _ rect: CGRect,
    imageWidth: CGFloat,
    imageHeight: CGFloat
  ) -> CGRect {
    let x = rect.origin.x * imageWidth
    let y = (1.0 - rect.origin.y - rect.height) * imageHeight
    let w = rect.width * imageWidth
    let h = rect.height * imageHeight
    return CGRect(x: x, y: y, width: w, height: h)
  }
}
