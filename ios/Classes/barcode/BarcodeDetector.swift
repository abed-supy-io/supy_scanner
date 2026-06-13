import AVFoundation
import CoreVideo
import Vision

/// Detection payload matching the cross-platform wire format produced by the
/// Android side (`SupyBarcodeScannerView.kt#emitDetections`).
struct DetectedBarcode {
  let rawValue: String
  let format: String
  /// Pixel-space bounding box in the source video frame (origin top-left).
  let boundingBox: CGRect?

  func toMap() -> [String: Any?] {
    var item: [String: Any?] = [
      "rawValue": rawValue,
      "format": format,
    ]
    if let box = boundingBox {
      item["boundingBox"] = [
        "left": Double(box.origin.x),
        "top": Double(box.origin.y),
        "width": Double(box.width),
        "height": Double(box.height),
      ]
    }
    return item
  }
}

/// `AVCaptureVideoDataOutputSampleBufferDelegate` that runs
/// `VNDetectBarcodesRequest` on its own background queue and forwards results
/// to a closure.
///
/// Threading (per CLAUDE.md): all Vision work happens on `detectionQueue`;
/// the caller is responsible for marshalling to main at the channel boundary.
final class BarcodeDetector: NSObject,
  AVCaptureVideoDataOutputSampleBufferDelegate
{

  /// Invoked from the detection queue. Caller marshals to main.
  var onDetections: (([DetectedBarcode]) -> Void)?

  /// Invoked from the detection queue on failure.
  var onError: ((String) -> Void)?

  private let detectionQueue: DispatchQueue = DispatchQueue(
    label: "io.supy.scanner.detection",
    qos: .userInitiated
  )

  private var request: VNDetectBarcodesRequest
  private var symbologies: [VNBarcodeSymbology]?

  // Backpressure — drop frames while a request is in flight.
  private var inFlight: Bool = false
  private let inFlightLock = NSLock()

  override init() {
    self.request = VNDetectBarcodesRequest()
    super.init()
  }

  /// Updates the symbology filter. Pass `nil` to detect all formats.
  func setSymbologies(_ symbologies: [VNBarcodeSymbology]?) {
    detectionQueue.async { [weak self] in
      guard let self = self else { return }
      self.symbologies = symbologies
      let request = VNDetectBarcodesRequest()
      if let symbologies = symbologies {
        request.symbologies = symbologies
      }
      self.request = request
    }
  }

  /// Returns the queue the detector wants frames delivered on.
  var sampleBufferQueue: DispatchQueue { detectionQueue }

  // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

  func captureOutput(
    _ output: AVCaptureOutput,
    didOutput sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection
  ) {
    inFlightLock.lock()
    if inFlight {
      inFlightLock.unlock()
      return
    }
    inFlight = true
    inFlightLock.unlock()

    defer {
      inFlightLock.lock()
      inFlight = false
      inFlightLock.unlock()
    }

    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
      return
    }

    let imageWidth = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
    let imageHeight = CGFloat(CVPixelBufferGetHeight(pixelBuffer))

    let orientation = cgImageOrientation(from: connection.videoOrientation)
    let handler = VNImageRequestHandler(
      cvPixelBuffer: pixelBuffer,
      orientation: orientation,
      options: [:]
    )

    let activeRequest = request
    do {
      try handler.perform([activeRequest])
    } catch {
      onError?("Vision request failed: \(error.localizedDescription)")
      return
    }

    guard
      let observations = activeRequest.results as? [VNBarcodeObservation],
      !observations.isEmpty
    else {
      return
    }

    let detections: [DetectedBarcode] = observations.compactMap { obs in
      guard let raw = obs.payloadStringValue else { return nil }
      let wire = SymbologyMapper.visionToWire(obs.symbology, payload: raw)
      let pixelBox = visionRectToPixelRect(
        obs.boundingBox,
        imageWidth: imageWidth,
        imageHeight: imageHeight
      )
      return DetectedBarcode(rawValue: raw, format: wire, boundingBox: pixelBox)
    }

    if !detections.isEmpty {
      onDetections?(detections)
    }
  }

  // MARK: - Helpers

  /// Vision's bounding box is in normalized image coords with origin
  /// bottom-left. Convert to pixel coords with origin top-left to match the
  /// Android wire format.
  private func visionRectToPixelRect(
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

  private func cgImageOrientation(
    from videoOrientation: AVCaptureVideoOrientation
  ) -> CGImagePropertyOrientation {
    switch videoOrientation {
    case .portrait: return .right
    case .portraitUpsideDown: return .left
    case .landscapeLeft: return .down
    case .landscapeRight: return .up
    @unknown default: return .right
    }
  }
}
