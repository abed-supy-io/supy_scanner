import AVFoundation
import Flutter
import UIKit
import Vision

/// PlatformView hosting an `AVCaptureSession` preview for the embedded live
/// text-pattern (generic data-capture) scanner (DC7).
///
/// The native side runs `VNRecognizeTextRequest` per frame and ships the
/// recognized-text geometry (`frame_text` events); the Dart side
/// (`SupyTextPatternMatcher`) runs the regex patterns over it. This view
/// therefore exposes only camera lifecycle: torch / pause / resume + a
/// `preview_started` event — there is no native pattern matching.
///
/// Threading rules (per CLAUDE.md):
///   - `AVCaptureSession` configuration and start/stop run on a dedicated
///     background queue (never `.main`).
///   - `VNRequest` work runs on the detector's background queue.
///   - `FlutterEventSink` invocations are marshalled to `.main`.
final class SupyDataCaptureScannerView: NSObject, FlutterPlatformView,
  FlutterStreamHandler
{

  private let container: PreviewContainerView
  private let session: AVCaptureSession = AVCaptureSession()
  private let sessionQueue: DispatchQueue = DispatchQueue(
    label: "io.supy.scanner.datacapture.session",
    qos: .userInitiated
  )
  private var previewLayer: AVCaptureVideoPreviewLayer?
  private var videoDevice: AVCaptureDevice?

  private let methodChannel: FlutterMethodChannel
  private let eventChannel: FlutterEventChannel

  private var eventSink: FlutterEventSink?
  private var previewStartedAnnounced: Bool = false
  private var sessionConfigured: Bool = false
  private var runningObservation: NSKeyValueObservation?
  private var sessionInterrupted: Bool = false

  private let detector: TextFrameDetector
  private let videoDataOutput: AVCaptureVideoDataOutput = AVCaptureVideoDataOutput()

  init(
    frame: CGRect,
    viewId: Int64,
    creationParams: [String: Any?]?,
    messenger: FlutterBinaryMessenger
  ) {
    self.container = PreviewContainerView(frame: frame)
    self.container.backgroundColor = .black

    let prefix = "io.supy.scanner/v1/datacapture"
    self.methodChannel = FlutterMethodChannel(
      name: "\(prefix)/\(viewId)",
      binaryMessenger: messenger
    )
    self.eventChannel = FlutterEventChannel(
      name: "\(prefix)/\(viewId)/events",
      binaryMessenger: messenger
    )

    let languages = (creationParams?["languages"] as? [String]) ?? []
    self.detector = TextFrameDetector(languages: languages)

    super.init()

    self.methodChannel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call: call, result: result)
    }
    self.eventChannel.setStreamHandler(self)

    // Detector callbacks fire on its own queue — marshal to main in sendEvent.
    detector.onFrameText = { [weak self] tree in
      self?.emitFrameText(tree)
    }
    detector.onError = { [weak self] message in
      self?.emitError(code: "unknown", message: message)
    }

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
    let error = note.userInfo?[AVCaptureSessionErrorKey] as? NSError
    if isNotAuthorizedError(error) {
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

  private func isNotAuthorizedError(_ error: NSError?) -> Bool {
    guard let error = error else { return false }
    return error.domain == AVFoundationErrorDomain &&
      error.code == AVError.Code.applicationIsNotAuthorizedToUseDevice.rawValue
  }

  /// Always call instead of `session.startRunning()` directly. Must be invoked
  /// from `sessionQueue`.
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
    let tier = SupyDeviceTier.detect()
    session.sessionPreset = SupyDataCaptureScannerView.sessionPreset(for: tier)

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

    videoDataOutput.alwaysDiscardsLateVideoFrames = true
    videoDataOutput.videoSettings = [
      kCVPixelBufferPixelFormatTypeKey as String:
        kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
    ]
    videoDataOutput.setSampleBufferDelegate(
      detector,
      queue: detector.sampleBufferQueue
    )
    if session.canAddOutput(videoDataOutput) {
      session.addOutput(videoDataOutput)
    }

    SupyDataCaptureScannerView.applyFpsCap(tier: tier, device: device)

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

  private func emitFrameText(_ tree: [String: Any]) {
    var payload = tree
    payload["type"] = "frame_text"
    sendEvent(payload)
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
        self?.safeStartRunning()
        DispatchQueue.main.async { result(nil) }
      }
    case "setTorch":
      let on = (call.arguments as? [String: Any])?["on"] as? Bool ?? false
      setTorch(on: on, result: result)
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
        // Swallow — parity with the barcode view.
      }
      DispatchQueue.main.async { result(nil) }
    }
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

  // MARK: - Teardown

  deinit {
    methodChannel.setMethodCallHandler(nil)
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
    NotificationCenter.default.removeObserver(self)
    videoDataOutput.setSampleBufferDelegate(nil, queue: nil)
    let session = self.session
    sessionQueue.async {
      if session.isRunning {
        session.stopRunning()
      }
    }
  }

  // MARK: - Perf tier

  private static func sessionPreset(for tier: SupyDeviceTier) -> AVCaptureSession.Preset {
    switch tier {
    case .high: return .high
    case .mid: return .hd1280x720
    case .low: return .vga640x480
    }
  }

  private static func applyFpsCap(tier: SupyDeviceTier, device: AVCaptureDevice) {
    // OCR is heavier than barcode decode, so always cap frame delivery — use
    // the per-tier cap where present, otherwise a conservative 10fps ceiling.
    let fps = tier.analyzerFpsCap ?? 10
    do {
      try device.lockForConfiguration()
      let duration = CMTime(value: 1, timescale: CMTimeScale(fps))
      device.activeVideoMinFrameDuration = duration
      device.activeVideoMaxFrameDuration = duration
      device.unlockForConfiguration()
    } catch {
      // Best-effort; perf cap is advisory.
    }
  }
}

/// Per-frame Vision text recognizer feeding the data-capture view.
///
/// Runs `VNRecognizeTextRequest` synchronously on `sampleBufferQueue` for each
/// delivered frame and builds the block → line → element tree consumed by
/// `SupyRecognizedText.fromMap`. Mirrors `OcrRunner.recognizeStructured`:
/// Vision has no block concept, so all lines wrap into one synthetic block
/// whose box is the union of its lines; boxes flip from Vision's bottom-left
/// to Supy's top-left `[0..1]` convention.
final class TextFrameDetector: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {

  let sampleBufferQueue = DispatchQueue(
    label: "io.supy.scanner.datacapture.detect",
    qos: .userInitiated
  )

  var onFrameText: (([String: Any]) -> Void)?
  var onError: ((String) -> Void)?

  private let languages: [String]

  init(languages: [String]) {
    self.languages = languages
    super.init()
  }

  func captureOutput(
    _ output: AVCaptureOutput,
    didOutput sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection
  ) {
    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

    let request = VNRecognizeTextRequest()
    // Live path: prioritize latency over the last few percent of accuracy.
    request.recognitionLevel = .fast
    request.usesLanguageCorrection = false
    if !languages.isEmpty {
      request.recognitionLanguages = languages
    }

    let handler = VNImageRequestHandler(
      cvPixelBuffer: pixelBuffer,
      // Back camera in portrait delivers landscape-right buffers; `.right`
      // presents upright text to Vision.
      orientation: .right,
      options: [:]
    )
    do {
      try handler.perform([request])
    } catch {
      onError?("Text recognition failed: \(error.localizedDescription)")
      return
    }

    let tree = Self.buildTree(
      observations: request.results ?? [],
      includeElements: true
    )
    onFrameText?(tree)
  }

  private static func buildTree(
    observations: [VNRecognizedTextObservation],
    includeElements: Bool
  ) -> [String: Any] {
    guard !observations.isEmpty else {
      return ["fullText": "", "blocks": []]
    }

    var lines: [[String: Any]] = []
    var lineTexts: [String] = []
    var union: CGRect?

    for obs in observations {
      guard let candidate = obs.topCandidates(1).first else { continue }
      let text = candidate.string
      lineTexts.append(text)
      union = union.map { $0.union(obs.boundingBox) } ?? obs.boundingBox

      var elements: [[String: Any]] = []
      if includeElements {
        elements = words(in: candidate, text: text)
      }
      lines.append([
        "text": text,
        "boundingBox": normRect(obs.boundingBox),
        "elements": elements,
      ])
    }

    let fullText = lineTexts.joined(separator: "\n")
    let block: [String: Any] = [
      "text": fullText,
      "boundingBox": normRect(union ?? .zero),
      "lines": lines,
    ]
    return ["fullText": fullText, "blocks": [block]]
  }

  private static func words(
    in candidate: VNRecognizedText,
    text: String
  ) -> [[String: Any]] {
    var out: [[String: Any]] = []
    var idx = text.startIndex
    while idx < text.endIndex {
      while idx < text.endIndex, text[idx].isWhitespace {
        idx = text.index(after: idx)
      }
      guard idx < text.endIndex else { break }
      let start = idx
      while idx < text.endIndex, !text[idx].isWhitespace {
        idx = text.index(after: idx)
      }
      let word = String(text[start..<idx])
      let box: CGRect
      if let rect = try? candidate.boundingBox(for: start..<idx)?.boundingBox {
        box = rect
      } else {
        box = .zero
      }
      out.append(["text": word, "boundingBox": normRect(box)])
    }
    return out
  }

  private static func normRect(_ bb: CGRect) -> [String: Double] {
    return [
      "left": Double(bb.origin.x),
      "top": Double(1.0 - bb.origin.y - bb.size.height),
      "width": Double(bb.size.width),
      "height": Double(bb.size.height),
    ]
  }
}
