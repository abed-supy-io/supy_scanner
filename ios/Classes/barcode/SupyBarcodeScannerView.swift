import AVFoundation
import Flutter
import UIKit

/// PlatformView hosting an `AVCaptureSession` preview for embedded barcode
/// scanning.
///
/// S2-01 scope: camera lifecycle + torch + per-view MethodChannel/EventChannel
/// parity with the Android side. Vision-based detection lands in S2-02.
///
/// Threading rules (per CLAUDE.md):
///   - `AVCaptureSession` configuration and start/stop run on a dedicated
///     background queue (never `.main`).
///   - `FlutterEventSink` invocations are marshalled to `.main`.
final class SupyBarcodeScannerView: NSObject, FlutterPlatformView,
  FlutterStreamHandler
{

  private let container: UIView
  private let session: AVCaptureSession = AVCaptureSession()
  private let sessionQueue: DispatchQueue = DispatchQueue(
    label: "io.supy.scanner.session",
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

  // S2-02: Vision detector + its data output.
  private let detector: BarcodeDetector = BarcodeDetector()
  private let videoDataOutput: AVCaptureVideoDataOutput = AVCaptureVideoDataOutput()
  private let initialWireFormats: [String]

  init(
    frame: CGRect,
    viewId: Int64,
    creationParams: [String: Any?]?,
    messenger: FlutterBinaryMessenger
  ) {
    self.container = UIView(frame: frame)
    self.container.backgroundColor = .black

    let prefix = "io.supy.scanner/v1/barcode"
    self.methodChannel = FlutterMethodChannel(
      name: "\(prefix)/\(viewId)",
      binaryMessenger: messenger
    )
    self.eventChannel = FlutterEventChannel(
      name: "\(prefix)/\(viewId)/events",
      binaryMessenger: messenger
    )

    self.initialWireFormats =
      (creationParams?["formats"] as? [String]) ?? []

    super.init()

    self.methodChannel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call: call, result: result)
    }
    self.eventChannel.setStreamHandler(self)

    // Wire detector callbacks. Both fire on the detection queue — marshal to
    // main inside `sendEvent`.
    detector.onDetections = { [weak self] detections in
      self?.emitDetections(detections)
    }
    detector.onError = { [weak self] message in
      self?.emitError(code: "unknown", message: message)
    }
    detector.setSymbologies(
      SymbologyMapper.toVisionSymbologies(initialWireFormats)
    )

    configureSessionAsync()
  }

  // MARK: - FlutterPlatformView

  func view() -> UIView {
    return container
  }

  // MARK: - Session lifecycle

  private func configureSessionAsync() {
    let status = AVCaptureDevice.authorizationStatus(for: .video)
    guard status == .authorized else {
      emitError(
        code: status == .denied || status == .restricted
          ? "permission_denied" : "camera_unavailable",
        message: "Camera authorization not granted (status: \(status.rawValue))."
      )
      return
    }

    sessionQueue.async { [weak self] in
      self?.configureSession()
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
        kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
    ]
    videoDataOutput.setSampleBufferDelegate(
      detector,
      queue: detector.sampleBufferQueue
    )
    if session.canAddOutput(videoDataOutput) {
      session.addOutput(videoDataOutput)
    }

    session.commitConfiguration()
    sessionConfigured = true

    DispatchQueue.main.async { [weak self] in
      self?.attachPreviewLayer()
    }

    // KVO: announce preview_started once isRunning flips true.
    runningObservation = session.observe(\.isRunning, options: [.new]) {
      [weak self] _, change in
      guard let self = self, let running = change.newValue, running else { return }
      if !self.previewStartedAnnounced {
        self.previewStartedAnnounced = true
        self.emitPreviewStarted()
      }
    }

    session.startRunning()
  }

  private func attachPreviewLayer() {
    let layer = AVCaptureVideoPreviewLayer(session: session)
    layer.videoGravity = .resizeAspectFill
    layer.frame = container.bounds
    container.layer.addSublayer(layer)
    previewLayer = layer

    // Keep the preview sized to the container.
    container.layer.setNeedsLayout()
    NotificationCenter.default.addObserver(
      forName: UIApplication.didChangeStatusBarOrientationNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.previewLayer?.frame = self?.container.bounds ?? .zero
    }
  }

  // MARK: - Events

  private func emitPreviewStarted() {
    let flashAvailable = videoDevice?.hasTorch == true
    sendEvent([
      "type": "preview_started",
      "flashAvailable": flashAvailable,
    ])
  }

  private func emitDetections(_ detections: [DetectedBarcode]) {
    let items = detections.map { $0.toMap() }
    if items.isEmpty { return }
    sendEvent([
      "type": "detection",
      "items": items,
    ])
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
        guard let self = self else { return }
        if !self.session.isRunning {
          self.session.startRunning()
        }
        DispatchQueue.main.async { result(nil) }
      }
    case "setTorch":
      let on = (call.arguments as? [String: Any])?["on"] as? Bool ?? false
      setTorch(on: on, result: result)
    case "setFormats":
      let formats =
        (call.arguments as? [String: Any])?["formats"] as? [String] ?? []
      detector.setSymbologies(SymbologyMapper.toVisionSymbologies(formats))
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func setTorch(on: Bool, result: @escaping FlutterResult) {
    // Parity with Android `LifecycleCameraController.enableTorch`: silently
    // no-op when the device lacks a torch. Consumers should gate on the
    // `flashAvailable` field of the `preview_started` event.
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
        // Swallow — Android equivalent does not surface this either.
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
    // Replay preview_started if the session is already running.
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
    eventChannel.setStreamHandler(nil)
    runningObservation?.invalidate()
    runningObservation = nil
    NotificationCenter.default.removeObserver(self)
    let session = self.session
    sessionQueue.async {
      if session.isRunning {
        session.stopRunning()
      }
    }
  }
}
