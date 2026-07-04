import AVFoundation
import CoreImage
import Flutter
import UIKit

/// PlatformView hosting an `AVCaptureSession` preview for embedded document
/// scanning with live edge-guidance.
///
/// S(doc-spike)-02 scope: camera lifecycle + per-view MethodChannel/EventChannel.
/// Emits `preview_started` once the session is running; `frame_metrics` from
/// the document detector lands in the next step. The Vision-based detector
/// itself is wired in S(doc-spike)-03.
///
/// Threading rules (per CLAUDE.md):
///   - `AVCaptureSession` configuration and start/stop run on a dedicated
///     background queue (never `.main`).
///   - `FlutterEventSink` invocations are marshalled to `.main`.
final class SupyDocumentScannerView: NSObject, FlutterPlatformView,
  FlutterStreamHandler
{

  private let container: PreviewContainerView
  private let session: AVCaptureSession = AVCaptureSession()
  private let sessionQueue: DispatchQueue = DispatchQueue(
    label: "io.supy.scanner.document.session",
    qos: .userInitiated
  )
  private var previewLayer: AVCaptureVideoPreviewLayer?
  private var videoDevice: AVCaptureDevice?
  private let videoDataOutput: AVCaptureVideoDataOutput = AVCaptureVideoDataOutput()
  private let photoOutput: AVCapturePhotoOutput = AVCapturePhotoOutput()
  private let detector: DocumentDetector = DocumentDetector()

  /// On-device guidance classifier (shared C++ core). Classifies each frame's
  /// metrics into a `GuidanceFrameState`; the resolved ordinal rides on the
  /// `frame_metrics` payload so Dart skips its fallback FSM. Accessed only from
  /// the detector callback (analyzer queue) and reset on `resume`.
  private let guidanceClassifier: GuidanceClassifier = GuidanceClassifier()
  /// Thresholds handed down via creationParams; defaults match the Dart config.
  private var guidanceConfig: GuidanceConfig = GuidanceConfig()

  /// Outstanding photo captures keyed by `AVCaptureResolvedPhotoSettings.uniqueID`.
  /// `captureAndRectify`/`captureFullFrame` populate this before invoking
  /// `photoOutput.capturePhoto`; the delegate drains it on completion. All
  /// access happens on `sessionQueue`.
  private var pendingCaptures: [Int64: PendingCapture] = [:]

  private let methodChannel: FlutterMethodChannel
  private let eventChannel: FlutterEventChannel

  private var eventSink: FlutterEventSink?
  private var previewStartedAnnounced: Bool = false
  private var sessionConfigured: Bool = false
  private var runningObservation: NSKeyValueObservation?
  /// See `SupyBarcodeScannerView.sessionInterrupted` for the failure mode this
  /// guards against. Same root cause, same fix.
  private var sessionInterrupted: Bool = false

  init(
    frame: CGRect,
    viewId: Int64,
    creationParams: [String: Any?]?,
    messenger: FlutterBinaryMessenger
  ) {
    self.container = PreviewContainerView(frame: frame)
    self.container.backgroundColor = .black

    let prefix = "io.supy.scanner/v1/document"
    self.methodChannel = FlutterMethodChannel(
      name: "\(prefix)/\(viewId)",
      binaryMessenger: messenger
    )
    self.eventChannel = FlutterEventChannel(
      name: "\(prefix)/\(viewId)/events",
      binaryMessenger: messenger
    )

    if let raw = creationParams?["guidanceConfig"] as? [NSNumber],
      let parsed = GuidanceConfig(wireArray: raw)
    {
      self.guidanceConfig = parsed
    }

    super.init()

    self.methodChannel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call: call, result: result)
    }
    self.eventChannel.setStreamHandler(self)

    registerSessionNotifications()
    configureSessionAsync()
  }

  private func registerSessionNotifications() {
    let center = NotificationCenter.default
    center.addObserver(
      self,
      selector: #selector(handleSessionWasInterrupted(_:)),
      name: .AVCaptureSessionWasInterrupted,
      object: session
    )
    center.addObserver(
      self,
      selector: #selector(handleSessionInterruptionEnded(_:)),
      name: .AVCaptureSessionInterruptionEnded,
      object: session
    )
    center.addObserver(
      self,
      selector: #selector(handleSessionRuntimeError(_:)),
      name: .AVCaptureSessionRuntimeError,
      object: session
    )
  }

  @objc private func handleSessionWasInterrupted(_ note: Notification) {
    sessionInterrupted = true
  }

  @objc private func handleSessionInterruptionEnded(_ note: Notification) {
    sessionInterrupted = false
    sessionQueue.async { [weak self] in
      self?.safeStartRunning()
    }
  }

  @objc private func handleSessionRuntimeError(_ note: Notification) {
    // Mid-session camera-permission revocation surfaces here as
    // `AVError.applicationIsNotAuthorizedToUseDevice` — distinguish it from
    // hardware errors so retailer code can route to the settings-deep-link.
    let error = note.userInfo?[AVCaptureSessionErrorKey] as? NSError
    if let error = error,
      error.domain == AVFoundationErrorDomain,
      error.code == AVError.Code.applicationIsNotAuthorizedToUseDevice.rawValue
    {
      emitError(
        code: "permission_denied",
        message: "Camera permission revoked mid-session."
      )
      return
    }
    emitError(
      code: "camera_unavailable",
      message: "AVCaptureSession runtime error: \(error?.localizedDescription ?? "unknown")"
    )
  }

  private func safeStartRunning() {
    guard !sessionInterrupted else { return }
    guard !session.isRunning else { return }
    session.startRunning()
  }

  // MARK: - FlutterPlatformView

  func view() -> UIView {
    return container
  }

  // MARK: - Session lifecycle

  private func configureSessionAsync() {
    let status = AVCaptureDevice.authorizationStatus(for: .video)
    switch status {
    case .authorized:
      sessionQueue.async { [weak self] in self?.configureSession() }
    case .notDetermined:
      AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
        guard let self = self else { return }
        if granted {
          self.sessionQueue.async { [weak self] in self?.configureSession() }
        } else {
          self.emitError(
            code: "permission_denied",
            message: "Camera permission denied by the user."
          )
        }
      }
    case .denied, .restricted:
      emitError(
        code: "permission_denied",
        message: "Camera authorization not granted (status: \(status.rawValue))."
      )
    @unknown default:
      emitError(
        code: "camera_unavailable",
        message: "Unknown camera authorization status (\(status.rawValue))."
      )
    }
  }

  private func configureSession() {
    guard !sessionConfigured else { return }

    session.beginConfiguration()
    session.sessionPreset = .high

    guard
      let device = AVCaptureDevice.default(
        .builtInWideAngleCamera, for: .video, position: .back
      )
    else {
      session.commitConfiguration()
      emitError(code: "camera_unavailable", message: "No back camera available.")
      return
    }
    videoDevice = device

    do {
      let input = try AVCaptureDeviceInput(device: device)
      if session.canAddInput(input) {
        session.addInput(input)
      } else {
        session.commitConfiguration()
        emitError(
          code: "camera_unavailable",
          message: "Cannot attach camera input to capture session."
        )
        return
      }
    } catch {
      session.commitConfiguration()
      emitError(
        code: "camera_unavailable",
        message: "Camera input init failed: \(error.localizedDescription)"
      )
      return
    }

    // Throttle live detection to a tier-aware cadence. The camera keeps its
    // native frame rate (preview stays smooth); the detector simply skips
    // analyzing frames that arrive sooner than this spacing, which roughly
    // halves Neural-Engine load and `frame_metrics` overlay repaints vs. the
    // previous run-flat-out behaviour. Set before the session starts
    // delivering buffers, so there's no concurrent access to the property.
    let fpsCap = SupyDeviceTier.detect().documentDetectorFpsCap
    detector.minFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fpsCap))

    videoDataOutput.alwaysDiscardsLateVideoFrames = true
    videoDataOutput.videoSettings = [
      kCVPixelBufferPixelFormatTypeKey as String:
        kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
    ]
    videoDataOutput.setSampleBufferDelegate(
      detector,
      queue: detector.sampleBufferQueue
    )
    if session.canAddOutput(videoDataOutput) {
      session.addOutput(videoDataOutput)
      if let connection = videoDataOutput.connection(with: .video) {
        if connection.isVideoOrientationSupported {
          connection.videoOrientation = .portrait
        }
      }
    } else {
      session.commitConfiguration()
      emitError(
        code: "camera_unavailable",
        message: "Cannot attach video data output to capture session."
      )
      return
    }

    detector.onMetrics = { [weak self] metrics in
      self?.emitFrameMetrics(metrics)
    }
    detector.onError = { [weak self] message in
      // Canonical `unknown`; detector-failure detail rides in `message`.
      self?.emitError(code: "unknown", message: "Detector failed: \(message)")
    }

    // Photo output for stills (captureAndRectify / captureFullFrame).
    if session.canAddOutput(photoOutput) {
      session.addOutput(photoOutput)
    }

    session.commitConfiguration()
    sessionConfigured = true

    DispatchQueue.main.async { [weak self] in
      self?.attachPreviewLayer()
    }

    runningObservation = session.observe(\.isRunning, options: [.new]) {
      [weak self] _, change in
      guard let self = self, let running = change.newValue, running else { return }
      if !self.previewStartedAnnounced {
        self.previewStartedAnnounced = true
        self.emitPreviewStarted()
      }
    }

    safeStartRunning()
  }

  private func attachPreviewLayer() {
    let layer = AVCaptureVideoPreviewLayer(session: session)
    layer.videoGravity = .resizeAspectFill
    container.attach(previewLayer: layer)
    previewLayer = layer
  }

  // MARK: - Events

  private func emitPreviewStarted() {
    let flashAvailable = videoDevice?.hasTorch == true
    sendEvent([
      "type": "preview_started",
      "flashAvailable": flashAvailable,
    ])
  }

  private func emitFrameMetrics(_ metrics: DocumentFrameMetrics) {
    var payload: [String: Any?] = [:]
    for (key, value) in metrics.toMap() {
      payload[key] = value
    }
    payload["type"] = "frame_metrics"

    // Classify on-device with the shared C++ core and ship the resolved state
    // so Dart trusts it instead of re-running its fallback FSM. Stays on the
    // detector's analyzer queue — `GuidanceClassifier` is single-threaded.
    let result = guidanceClassifier.classify(
      guidanceMetrics(from: metrics),
      config: guidanceConfig
    )
    payload["state"] = Int(result.state.rawValue)
    payload["liveQualityScore"] = Double(result.liveQualityScore)

    sendEvent(payload)
  }

  /// Bridges the detector's `DocumentFrameMetrics` (Double-valued, with a quad)
  /// to the classifier's `GuidanceFrameMetrics` (Float-valued, document-as-flag).
  /// `hasDocument` is true only for a complete 4-corner quad.
  private func guidanceMetrics(from m: DocumentFrameMetrics)
    -> GuidanceFrameMetrics
  {
    // Signed quad-centroid offset from preview center, in half-extent
    // fractions. Shares `DocumentFrameMetrics.centerOffset` with the wire map.
    let offset = m.centerOffset
    return GuidanceFrameMetrics(
      hasDocument: m.quad.count == 4,
      clipsEdge: m.clipsEdge,
      coverageRatio: Float(m.coverageRatio),
      tiltDegrees: Float(m.tiltDegrees),
      meanLuma: Float(m.meanLuma),
      blurScore: Float(m.blurScore),
      quadStability: Float(m.quadStability),
      interiorVariance: Float(m.interiorVariance),
      glareRatio: Float(m.glareRatio),
      cornerVelocity: Float(m.cornerVelocity),
      centerOffsetX: Float(offset.x),
      centerOffsetY: Float(offset.y),
      perCornerStability: m.perCornerStability.map { Float($0) }
    )
  }

  private func emitError(code: String, message: String) {
    sendEvent([
      "type": "error",
      "code": code,
      "message": message,
    ])
  }

  private func sendEvent(_ payload: [String: Any?]) {
    let dispatch: () -> Void = { [weak self] in
      guard let sink = self?.eventSink else { return }
      sink(payload)
    }
    if Thread.isMainThread {
      dispatch()
    } else {
      DispatchQueue.main.async(execute: dispatch)
    }
  }

  // MARK: - MethodChannel

  private func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    dispatchPrecondition(condition: .onQueue(.main))
    switch call.method {
    case "pause":
      sessionQueue.async { [weak self] in
        self?.session.stopRunning()
        DispatchQueue.main.async { result(nil) }
      }
    case "resume":
      sessionQueue.async { [weak self] in
        // Drop stale guidance hysteresis so a paused→resumed view starts from
        // NoDocument rather than a latched ready/glare state.
        self?.guidanceClassifier.reset()
        self?.safeStartRunning()
        DispatchQueue.main.async { result(nil) }
      }
    case "setTorch":
      let on = (call.arguments as? [String: Any])?["on"] as? Bool ?? false
      setTorch(on: on, result: result)
    case "captureAndRectify":
      let quality = Self.parseJpegQuality(call.arguments)
      captureAndRectify(jpegQuality: quality, result: result)
    case "captureFullFrame":
      let quality = Self.parseJpegQuality(call.arguments)
      captureFullFrame(jpegQuality: quality, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func setTorch(on: Bool, result: @escaping FlutterResult) {
    sessionQueue.async { [weak self] in
      guard let device = self?.videoDevice, device.hasTorch else {
        DispatchQueue.main.async { result(nil) }
        return
      }
      do {
        try device.lockForConfiguration()
        device.torchMode = on ? .on : .off
        device.unlockForConfiguration()
      } catch {
        // Best-effort.
      }
      DispatchQueue.main.async { result(nil) }
    }
  }

  // MARK: - Still capture

  private func captureAndRectify(jpegQuality: CGFloat, result: @escaping FlutterResult) {
    let quad = detector.snapshotLatestQuad()
    guard quad.count == 4 else {
      DispatchQueue.main.async {
        result(
          FlutterError(
            code: "captureUnsupported",
            message: "No quad detected",
            details: nil
          )
        )
      }
      return
    }
    sessionQueue.async { [weak self] in
      guard let self = self else { return }
      let settings = self.makePhotoSettings()
      self.pendingCaptures[settings.uniqueID] = PendingCapture(
        result: result,
        quad: quad,
        jpegQuality: jpegQuality
      )
      let delegate = PhotoCaptureDelegate(owner: self)
      // Retain the delegate until the callback fires — AVFoundation only
      // holds a weak ref.
      objc_setAssociatedObject(
        settings,
        &PhotoCaptureDelegate.assocKey,
        delegate,
        .OBJC_ASSOCIATION_RETAIN
      )
      self.photoOutput.capturePhoto(with: settings, delegate: delegate)
    }
  }

  private func captureFullFrame(jpegQuality: CGFloat, result: @escaping FlutterResult) {
    sessionQueue.async { [weak self] in
      guard let self = self else { return }
      let settings = self.makePhotoSettings()
      self.pendingCaptures[settings.uniqueID] = PendingCapture(
        result: result,
        quad: nil,
        jpegQuality: jpegQuality
      )
      let delegate = PhotoCaptureDelegate(owner: self)
      objc_setAssociatedObject(
        settings,
        &PhotoCaptureDelegate.assocKey,
        delegate,
        .OBJC_ASSOCIATION_RETAIN
      )
      self.photoOutput.capturePhoto(with: settings, delegate: delegate)
    }
  }

  private func makePhotoSettings() -> AVCapturePhotoSettings {
    let settings: AVCapturePhotoSettings
    if photoOutput.availablePhotoCodecTypes.contains(.jpeg) {
      settings = AVCapturePhotoSettings(format: [
        AVVideoCodecKey: AVVideoCodecType.jpeg
      ])
    } else {
      settings = AVCapturePhotoSettings()
    }
    return settings
  }

  /// Called from `PhotoCaptureDelegate` on AVFoundation's internal queue.
  /// We bounce onto `sessionQueue` immediately so all reads/removals of
  /// `pendingCaptures` happen on the same queue as the writes — no cross-
  /// queue dictionary mutation.
  fileprivate func finishPhotoCapture(
    settingsID: Int64,
    photo: AVCapturePhoto?,
    error: Error?
  ) {
    sessionQueue.async { [weak self] in
      guard let self = self else { return }
      guard let pending = self.pendingCaptures.removeValue(forKey: settingsID)
      else { return }
      if let error = error {
        DispatchQueue.main.async {
          pending.result(
            FlutterError(
              code: "captureFailed",
              message: "Photo capture failed: \(error.localizedDescription)",
              details: nil
            )
          )
        }
        return
      }
      guard let photo = photo, let data = photo.fileDataRepresentation() else {
        DispatchQueue.main.async {
          pending.result(
            FlutterError(
              code: "captureFailed",
              message: "Photo capture returned no data",
              details: nil
            )
          )
        }
        return
      }

      // Heavy work (CI decode + rectify + JPEG encode) stays off the session
      // queue so we don't block subsequent camera ops.
      DispatchQueue.global(qos: .userInitiated).async { [weak self] in
        guard let self = self else { return }
        if let quad = pending.quad {
          self.processRectifyCapture(
            data: data, quad: quad, jpegQuality: pending.jpegQuality, result: pending.result)
        } else {
          self.processFullFrameCapture(
            data: data, jpegQuality: pending.jpegQuality, result: pending.result)
        }
      }
    }
  }

  private func processRectifyCapture(
    data: Data,
    quad: [CGPoint],
    jpegQuality: CGFloat,
    result: @escaping FlutterResult
  ) {
    guard let ciImage = CIImage(data: data),
          let filter = CIFilter(name: "CIPerspectiveCorrection") else {
      DispatchQueue.main.async {
        result(
          FlutterError(
            code: "captureFailed",
            message: "Could not initialize rectification filter",
            details: nil
          )
        )
      }
      return
    }
    let imgW = ciImage.extent.width
    let imgH = ciImage.extent.height
    // `DocumentFrameMetrics.quad` is top-left-origin (DocumentDetector flips
    // Vision's bottom-left output once before emitting). CIImage extent is
    // bottom-left, so we flip Y here exactly once.
    let tl = CGPoint(x: quad[0].x * imgW, y: (1 - quad[0].y) * imgH)
    let tr = CGPoint(x: quad[1].x * imgW, y: (1 - quad[1].y) * imgH)
    let br = CGPoint(x: quad[2].x * imgW, y: (1 - quad[2].y) * imgH)
    let bl = CGPoint(x: quad[3].x * imgW, y: (1 - quad[3].y) * imgH)
    filter.setValue(ciImage, forKey: kCIInputImageKey)
    filter.setValue(CIVector(cgPoint: tl), forKey: "inputTopLeft")
    filter.setValue(CIVector(cgPoint: tr), forKey: "inputTopRight")
    filter.setValue(CIVector(cgPoint: bl), forKey: "inputBottomLeft")
    filter.setValue(CIVector(cgPoint: br), forKey: "inputBottomRight")

    guard let outCI = filter.outputImage,
          let cg = DocumentEnhancer.sharedContext.createCGImage(outCI, from: outCI.extent) else {
      DispatchQueue.main.async {
        result(
          FlutterError(
            code: "captureFailed",
            message: "Could not render rectified image",
            details: nil
          )
        )
      }
      return
    }
    let uiImage = UIImage(cgImage: cg)
    guard let jpeg = uiImage.jpegData(compressionQuality: jpegQuality) else {
      DispatchQueue.main.async {
        result(
          FlutterError(
            code: "captureFailed",
            message: "Could not encode rectified JPEG",
            details: nil
          )
        )
      }
      return
    }
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("supy-doc-\(UUID().uuidString).jpg")
    do {
      try jpeg.write(to: url, options: .atomic)
    } catch {
      DispatchQueue.main.async {
        result(
          FlutterError(
            code: "captureFailed",
            message: "Could not write JPEG: \(error.localizedDescription)",
            details: nil
          )
        )
      }
      return
    }
    let payload: [String: Any] = [
      "path": url.path,
      "widthPx": cg.width,
      "heightPx": cg.height,
      "quad": quad.map { ["x": Double($0.x), "y": Double($0.y)] },
      // Legacy keys for existing `SupyDocumentPage.fromMap` consumers
      // (`controller.capture()`). Additive — never remove.
      "uri": "file://\(url.path)",
      "width": cg.width,
      "height": cg.height,
    ]
    DispatchQueue.main.async { result(payload) }
  }

  private func processFullFrameCapture(
    data: Data,
    jpegQuality: CGFloat,
    result: @escaping FlutterResult
  ) {
    guard let image = UIImage(data: data),
          let jpeg = image.jpegData(compressionQuality: jpegQuality) else {
      DispatchQueue.main.async {
        result(
          FlutterError(
            code: "captureFailed",
            message: "Could not decode/encode full-frame JPEG",
            details: nil
          )
        )
      }
      return
    }
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("supy-doc-\(UUID().uuidString).jpg")
    do {
      try jpeg.write(to: url, options: .atomic)
    } catch {
      DispatchQueue.main.async {
        result(
          FlutterError(
            code: "captureFailed",
            message: "Could not write JPEG: \(error.localizedDescription)",
            details: nil
          )
        )
      }
      return
    }
    let widthPx = Int(image.size.width * image.scale)
    let heightPx = Int(image.size.height * image.scale)
    let payload: [String: Any] = [
      "path": url.path,
      "widthPx": widthPx,
      "heightPx": heightPx,
      "uri": "file://\(url.path)",
      "width": widthPx,
      "height": heightPx,
    ]
    DispatchQueue.main.async { result(payload) }
  }

  // MARK: - FlutterStreamHandler

  func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    self.eventSink = events
    if session.isRunning && !previewStartedAnnounced {
      previewStartedAnnounced = true
      emitPreviewStarted()
    }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    self.eventSink = nil
    return nil
  }

  // MARK: - Teardown helpers

  fileprivate struct PendingCapture {
    let result: FlutterResult
    /// `nil` for full-frame captures; populated with a normalized
    /// top-left-origin quad for rectify captures.
    let quad: [CGPoint]?
    /// JPEG compression quality (0.0–1.0). Matches the presenter's
    /// `jpegQuality` arg so both capture paths produce identical fidelity.
    let jpegQuality: CGFloat
  }

  /// Parses the `jpegQuality` arg (0–100 int, like the presenter) from a
  /// method-call argument map into a Core-Graphics-friendly 0.0–1.0 ratio.
  /// Defaults to 0.95 (`SupyDocumentScanOptions.jpegQuality` default) when
  /// missing or out of range.
  fileprivate static func parseJpegQuality(_ args: Any?) -> CGFloat {
    let raw = (args as? [String: Any])?["jpegQuality"] as? Int ?? 95
    let clamped = max(0, min(100, raw))
    return CGFloat(clamped) / 100.0
  }

  // MARK: - Teardown

  deinit {
    NotificationCenter.default.removeObserver(self)
    methodChannel.setMethodCallHandler(nil)
    // Signal stream completion to the Dart side before detaching the handler.
    // Sink calls must happen on the platform thread.
    if let sink = eventSink {
      eventSink = nil
      if Thread.isMainThread {
        sink(FlutterEndOfEventStream)
      } else {
        DispatchQueue.main.async { sink(FlutterEndOfEventStream) }
      }
    }
    eventChannel.setStreamHandler(nil)
    runningObservation?.invalidate()
    runningObservation = nil
    detector.onMetrics = nil
    detector.onError = nil
    videoDataOutput.setSampleBufferDelegate(nil, queue: nil)
    let session = self.session
    sessionQueue.async {
      if session.isRunning {
        session.stopRunning()
      }
    }
  }
}

/// AVFoundation only retains photo-capture delegates weakly. We pin one
/// instance per outstanding capture via `objc_setAssociatedObject` on the
/// `AVCapturePhotoSettings` object — that retains the delegate for the
/// lifetime of the request and lets ARC tear it down once the settings go
/// out of scope after the callback fires.
private final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
  static var assocKey: UInt8 = 0
  private weak var owner: SupyDocumentScannerView?

  init(owner: SupyDocumentScannerView) {
    self.owner = owner
    super.init()
  }

  func photoOutput(
    _ output: AVCapturePhotoOutput,
    didFinishProcessingPhoto photo: AVCapturePhoto,
    error: Error?
  ) {
    let id = photo.resolvedSettings.uniqueID
    owner?.finishPhotoCapture(settingsID: id, photo: photo, error: error)
  }
}
