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

  /// Optional pre-Vision gate. Invoked on the detection queue with the
  /// incoming pixel buffer. Returning `true` skips the Vision request for
  /// this frame — used by the idle detector to suppress ML work on static
  /// scenes.
  var shouldSkipFrame: ((CVPixelBuffer) -> Bool)?

  private let detectionQueue: DispatchQueue = DispatchQueue(
    label: "io.supy.scanner.detection",
    qos: .userInitiated
  )

  private var request: VNDetectBarcodesRequest
  private var symbologies: [VNBarcodeSymbology]?

  // Backpressure — drop frames while a request is in flight.
  private var inFlight: Bool = false
  private let inFlightLock = NSLock()

  // Native-core (zxing-cpp) opt-in. Resolved by the caller — three-layer gate
  // (caller arg && build linked zxing && per-PV opt-in), same shape as
  // Android's `nativeCoreEnabled`. When true the detector tries native decode
  // first and falls back to Vision only on a non-nil-zero result.
  private var nativeCoreEnabled: Bool = false
  private var nativeFormatMask: SupyFormatMask = .all
  // libdmtx Data Matrix ROI-assist gate. True iff [nativeCoreEnabled] AND the
  // build linked libdmtx. Mirrors Android's `nativeDmLocateEnabled`.
  private var nativeDmLocateEnabled: Bool = false
  // Reusable Y-plane crop buffer for the DM ROI path. Grown ×1.5 as needed,
  // mirrors Android's per-analyzer `cropBuffer`.
  private var cropBuffer: [UInt8] = []
  // V1-S2-06.3 — analyzer-thread-only ring of the last two DM-located frames
  // used by `temporalMedianLuma3`. Mirrors Android's `DatamatrixTemporalRing`.
  private let temporalRing = DatamatrixTemporalRing()

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

  /// Enables the native-core decode path. Caller is responsible for verifying
  /// `SupyNativeCore.hasZxing()` before passing `true`. [formats] is the same
  /// wire-name list the Vision path receives via `setSymbologies`.
  func setUseNativeCore(_ enabled: Bool, formats: [String]) {
    detectionQueue.async { [weak self] in
      guard let self = self else { return }
      self.nativeCoreEnabled = enabled
      self.nativeFormatMask = SupyFormatMask.fromWireNames(formats)
      self.nativeDmLocateEnabled = enabled && SupyNativeCore.hasLibdmtx()
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

    if shouldSkipFrame?(pixelBuffer) == true {
      return
    }

    if nativeCoreEnabled, tryNativeDecode(pixelBuffer) {
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
      dispatchPrecondition(condition: .notOnQueue(.main))
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

  /// Runs the native-core (zxing-cpp) decode on the pixel buffer's Y-plane.
  /// Returns true when the native call ran successfully — even if it found
  /// zero barcodes — so the Vision request is skipped for this frame.
  /// Returns false (Vision fallback) when the pixel format isn't a planar
  /// luma layout we know, the lock fails, or the native core returns nil
  /// (e.g. zxing-cpp not linked into the build).
  private func tryNativeDecode(_ pixelBuffer: CVPixelBuffer) -> Bool {
    // We require a planar pixel format whose plane 0 is luma. AVCaptureSession
    // delivers `kCVPixelFormatType_420YpCbCr8BiPlanar{Video,Full}Range` by
    // default — both expose Y as plane 0.
    let pf = CVPixelBufferGetPixelFormatType(pixelBuffer)
    guard
      pf == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        || pf == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
    else {
      return false
    }

    let lockResult = CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
    guard lockResult == kCVReturnSuccess else { return false }
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

    guard
      let basePtr = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0)
    else {
      return false
    }
    let luma = basePtr.assumingMemoryBound(to: UInt8.self)
    let width = Int32(CVPixelBufferGetWidthOfPlane(pixelBuffer, 0))
    let height = Int32(CVPixelBufferGetHeightOfPlane(pixelBuffer, 0))
    let rowStride = Int32(CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0))

    var allDetections: [DetectedBarcode] = []

    // DM ROI-assist path: when DM is requested and libdmtx is linked, locate
    // candidate regions on the luma plane, crop each into a Y-only sub-buffer,
    // and re-enter zxing-cpp with DM-only formats + tryHarder=true. Translate
    // located corners back to input pixel space. Mirrors the Android path in
    // `SupyBarcodeScannerView.kt#tryNativeDecode`.
    let dmRequested = SupyFormatMask.includesDataMatrix(nativeFormatMask)
    var dmRanLocator = false
    if nativeDmLocateEnabled, dmRequested {
      if let regions = SupyNativeCore.locateDatamatrix(
        luma: luma,
        width: width,
        height: height,
        rowStride: rowStride,
        maxRegions: 4,
        timeoutMs: 20
      ) {
        dmRanLocator = true
        var frameBoxes: [DatamatrixTemporalRing.Box] = []
        for quad in regions {
          guard let box = boxFromQuad(quad, width: Int(width), height: Int(height)) else { continue }
          frameBoxes.append(box)

          // V1-S2-06.3 — attempt temporal-median fusion against the prior two
          // DM-located frames. On success, decode the fused crop (post-Sauvola
          // binarization) instead of the raw single-frame crop. On any failure
          // (no IoU match, geometry change, native error) fall through to the
          // raw-crop path unchanged.
          if let fused = temporalRing.tryFuse(
            curLuma: luma,
            curW: Int(width),
            curH: Int(height),
            curRowStride: Int(rowStride),
            curBox: box
          ),
            let fusedDetections = decodeFusedCrop(fused)
          {
            allDetections.append(contentsOf: fusedDetections)
            continue
          }

          if let cropDetections = decodeDmRegion(
            luma: luma,
            width: Int(width),
            height: Int(height),
            rowStride: Int(rowStride),
            quad: quad
          ) {
            allDetections.append(contentsOf: cropDetections)
          }
        }
        if !frameBoxes.isEmpty {
          temporalRing.push(
            luma: luma,
            width: Int(width),
            height: Int(height),
            rowStride: Int(rowStride),
            boxes: frameBoxes
          )
        }
      }
    }

    // Full-frame decode for the non-DM portion of the mask. When DM was the
    // only requested format AND the locator ran, skip the full-frame decode
    // entirely — the ROI pass is authoritative for DM.
    let remainderMask: SupyFormatMask =
      dmRanLocator
      ? SupyFormatMask.maskWithoutDataMatrix(nativeFormatMask)
      : nativeFormatMask
    if !remainderMask.isEmpty {
      let decoded = SupyNativeCore.decodeBarcodes(
        luma: luma,
        width: width,
        height: height,
        rowStride: rowStride,
        formats: remainderMask,
        tryHarder: false,
        tryRotate: false
      )
      guard let decoded = decoded else { return false }
      for item in decoded {
        allDetections.append(
          DetectedBarcode(
            rawValue: item.rawValue,
            format: item.format,
            boundingBox: item.boundingBox
          )
        )
      }
    }

    if !allDetections.isEmpty {
      onDetections?(allDetections)
    }
    return true
  }

  /// Crops a Data Matrix region out of the source luma plane and re-runs
  /// zxing-cpp on the crop with DM-only formats and `tryHarder=true`.
  /// [quad] is in input-image pixel space (TL/TR/BR/BL).
  private func decodeDmRegion(
    luma: UnsafePointer<UInt8>,
    width: Int,
    height: Int,
    rowStride: Int,
    quad: [CGPoint]
  ) -> [DetectedBarcode]? {
    guard quad.count == 4 else { return nil }

    let xs = quad.map { Int($0.x.rounded()) }
    let ys = quad.map { Int($0.y.rounded()) }
    var minX = max(0, xs.min() ?? 0)
    var maxX = min(width, xs.max() ?? 0)
    var minY = max(0, ys.min() ?? 0)
    var maxY = min(height, ys.max() ?? 0)
    if maxX <= minX || maxY <= minY { return nil }

    // ~6% padding clamped, ≥12×12 min — mirrors Android.
    let padX = max(1, (maxX - minX) * 6 / 100)
    let padY = max(1, (maxY - minY) * 6 / 100)
    minX = max(0, minX - padX)
    minY = max(0, minY - padY)
    maxX = min(width, maxX + padX)
    maxY = min(height, maxY + padY)

    var cropW = maxX - minX
    var cropH = maxY - minY
    if cropW < 12 {
      let grow = (12 - cropW + 1) / 2
      minX = max(0, minX - grow)
      maxX = min(width, maxX + grow)
      cropW = maxX - minX
    }
    if cropH < 12 {
      let grow = (12 - cropH + 1) / 2
      minY = max(0, minY - grow)
      maxY = min(height, maxY + grow)
      cropH = maxY - minY
    }
    if cropW < 12 || cropH < 12 { return nil }

    let cropStride = cropW
    let needed = cropStride * cropH
    if cropBuffer.count < needed {
      cropBuffer = [UInt8](repeating: 0, count: max(needed, (cropBuffer.count * 3) / 2))
    }

    cropBuffer.withUnsafeMutableBufferPointer { buf in
      guard let dst = buf.baseAddress else { return }
      for row in 0..<cropH {
        let srcRow = luma.advanced(by: (minY + row) * rowStride + minX)
        let dstRow = dst.advanced(by: row * cropStride)
        dstRow.update(from: srcRow, count: cropW)
      }
    }

    // Adaptive (Sauvola) binarization in-place on the crop. On failure, fall
    // through to raw-luma decode rather than dropping the frame. Mirrors the
    // Android V1-S2-05.1 try/catch fallback in `tryDatamatrixRoiAssist`.
    _ = cropBuffer.withUnsafeMutableBufferPointer { buf -> Bool in
      guard let base = buf.baseAddress else { return false }
      return SupyNativeCore.binarizeLumaInPlace(
        luma: base,
        width: Int32(cropW),
        height: Int32(cropH),
        rowStride: Int32(cropStride),
        mode: .sauvola2D
      )
    }

    let dmMask: SupyFormatMask = [.dataMatrix]
    let detections: [DetectedBarcode]? = cropBuffer.withUnsafeBufferPointer {
      buf -> [DetectedBarcode]? in
      guard let base = buf.baseAddress else { return nil }
      let decoded = SupyNativeCore.decodeBarcodes(
        luma: base,
        width: Int32(cropW),
        height: Int32(cropH),
        rowStride: Int32(cropStride),
        formats: dmMask,
        tryHarder: true,
        tryRotate: false
      )
      guard let decoded = decoded else { return nil }
      let originX = CGFloat(minX)
      let originY = CGFloat(minY)
      return decoded.map { item in
        let box = item.boundingBox
        let shifted = CGRect(
          x: box.origin.x + originX,
          y: box.origin.y + originY,
          width: box.width,
          height: box.height
        )
        return DetectedBarcode(
          rawValue: item.rawValue,
          format: item.format,
          boundingBox: shifted
        )
      }
    }
    return detections
  }

  /// Pre-pad axis-aligned bbox from a locator quad, clamped to frame. Used to
  /// feed the temporal ring with raw locator output — padding is the
  /// decode-time concern in `decodeDmRegion`.
  private func boxFromQuad(_ quad: [CGPoint], width: Int, height: Int)
    -> DatamatrixTemporalRing.Box?
  {
    guard quad.count == 4 else { return nil }
    let xs = quad.map { Int($0.x.rounded()) }
    let ys = quad.map { Int($0.y.rounded()) }
    let minX = max(0, xs.min() ?? 0)
    let maxX = min(width - 1, xs.max() ?? 0)
    let minY = max(0, ys.min() ?? 0)
    let maxY = min(height - 1, ys.max() ?? 0)
    if maxX <= minX || maxY <= minY { return nil }
    return DatamatrixTemporalRing.Box(x0: minX, y0: minY, x1: maxX, y1: maxY)
  }

  /// Decodes a temporal-median-fused crop. Same Sauvola-binarize → DM-only
  /// zxing path as `decodeDmRegion`, but on the fused luma instead of a raw
  /// single-frame crop. Returns nil when the binarize call succeeds-and-misses
  /// or when zxing returns an unrecoverable error; the caller falls back to
  /// the raw-crop path on nil.
  private func decodeFusedCrop(_ fused: DatamatrixTemporalRing.FusedCrop)
    -> [DetectedBarcode]?
  {
    let cropW = fused.width
    let cropH = fused.height
    let cropStride = cropW
    let needed = cropStride * cropH
    if cropBuffer.count < needed {
      cropBuffer = [UInt8](repeating: 0, count: max(needed, (cropBuffer.count * 3) / 2))
    }
    cropBuffer.withUnsafeMutableBufferPointer { buf in
      guard let dst = buf.baseAddress else { return }
      dst.update(from: fused.luma, count: needed)
    }
    _ = cropBuffer.withUnsafeMutableBufferPointer { buf -> Bool in
      guard let base = buf.baseAddress else { return false }
      return SupyNativeCore.binarizeLumaInPlace(
        luma: base,
        width: Int32(cropW),
        height: Int32(cropH),
        rowStride: Int32(cropStride),
        mode: .sauvola2D
      )
    }
    let dmMask: SupyFormatMask = [.dataMatrix]
    return cropBuffer.withUnsafeBufferPointer { buf -> [DetectedBarcode]? in
      guard let base = buf.baseAddress else { return nil }
      let decoded = SupyNativeCore.decodeBarcodes(
        luma: base,
        width: Int32(cropW),
        height: Int32(cropH),
        rowStride: Int32(cropStride),
        formats: dmMask,
        tryHarder: true,
        tryRotate: false
      )
      guard let decoded = decoded, !decoded.isEmpty else { return nil }
      let originX = CGFloat(fused.srcX0)
      let originY = CGFloat(fused.srcY0)
      return decoded.map { item in
        let box = item.boundingBox
        let shifted = CGRect(
          x: box.origin.x + originX,
          y: box.origin.y + originY,
          width: box.width,
          height: box.height
        )
        return DetectedBarcode(
          rawValue: item.rawValue,
          format: item.format,
          boundingBox: shifted
        )
      }
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
