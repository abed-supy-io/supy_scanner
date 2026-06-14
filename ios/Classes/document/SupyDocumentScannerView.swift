import AVFoundation
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
  private let detector: DocumentDetector = DocumentDetector()

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
    let error = note.userInfo?[AVCaptureSessionErrorKey] as? NSError
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
    case "captureAndRectify":
      // V1-S6-02 stub. Sprint 4 must land `warpPerspective` in the native
      // core before this can return a real page.
      result(
        FlutterError(
          code: "UNIMPLEMENTED",
          message: "captureAndRectify awaits Sprint 4 warpPerspective",
          details: nil
        )
      )
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
