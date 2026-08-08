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

  private let container: PreviewContainerView
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
  /// Set when AVFoundation has put the session into an interrupted state
  /// (background, phone call, another app stealing the camera, FigCaptureSource
  /// XPC failure). Calling `startRunning()` while this is true throws
  /// `NSGenericException: startRunning may not be called between calls to
  /// beginConfiguration and commitConfiguration` on some iPhones — AVFoundation
  /// keeps its own internal config block open across the interruption.
  private var sessionInterrupted: Bool = false

  // S2-02: Vision detector + its data output.
  private let detector: BarcodeDetector = BarcodeDetector()
  private let videoDataOutput: AVCaptureVideoDataOutput = AVCaptureVideoDataOutput()
  private let initialWireFormats: [String]
  private let initialCameraConfig: InitialCameraConfig
  /// Resolved at construction — three-layer gate (caller arg && build linked
  /// zxing-cpp). Per-frame native-decode is the detector's job; this flag is
  /// only here so `setFormats` can re-sync the detector's native mask too.
  private let nativeCoreEnabled: Bool

  private var thermalGovernor: SupyThermalGovernor?
  /// True while the OS thermal state has forced us to stop the capture session.
  /// Distinct from `sessionInterrupted` so a user-initiated `resume` doesn't
  /// blow past a thermal pause.
  private var thermalPaused: Bool = false

  /// Luma-variance idle gate. Lives on the detector queue (single-threaded
  /// access there) — never touch from any other queue.
  private let idleDetector: SupyIdleDetector = SupyIdleDetector(
    thresholdMs: SupyDeviceTier.detect().idlePauseThresholdMs
  )

  private struct InitialCameraConfig {
    let initialZoom: CGFloat
    let minFocusDistanceLock: Bool
    let scanRange: String

    static func from(_ params: [String: Any?]?) -> InitialCameraConfig {
      let block = params?["camera"] as? [String: Any]
      let zoom = (block?["initialZoom"] as? Double).map { CGFloat($0) } ?? 1.0
      let lock = (block?["minFocusDistanceLock"] as? Bool) ?? false
      let range = (block?["scanRange"] as? String) ?? "standard"
      return InitialCameraConfig(
        initialZoom: zoom,
        minFocusDistanceLock: lock,
        scanRange: range
      )
    }
  }

  init(
    frame: CGRect,
    viewId: Int64,
    creationParams: [String: Any?]?,
    messenger: FlutterBinaryMessenger
  ) {
    self.container = PreviewContainerView(frame: frame)
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
    self.initialCameraConfig = InitialCameraConfig.from(creationParams)
    // Three-layer gate matching Android (`SupyBarcodeScannerView.kt`): caller
    // opted in, build linked zxing-cpp. Resolve once at construction so the
    // detector doesn't probe the C ABI per-frame.
    let requestedNativeCore =
      (creationParams?["useNativeCore"] as? Bool) ?? false
    self.nativeCoreEnabled = requestedNativeCore && SupyNativeCore.hasZxing()

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
    detector.shouldSkipFrame = { [weak self] pixelBuffer in
      guard let self = self else { return false }
      let nowMs = Int64(ProcessInfo.processInfo.systemUptime * 1000)
      let transitioned = self.idleDetector.update(pixelBuffer, nowMs: nowMs)
      if transitioned {
        self.sendEvent([
          "type": self.idleDetector.isIdle ? "idle_pause" : "idle_resume",
        ])
        if self.idleDetector.isIdle, self.videoDevice?.isTorchActive == true {
          self.sendEvent(["type": "torch_idle_suggested"])
        }
      }
      return self.idleDetector.isIdle
    }
    detector.setSymbologies(
      SymbologyMapper.toVisionSymbologies(initialWireFormats)
    )
    detector.setUseNativeCore(nativeCoreEnabled, formats: initialWireFormats)

    registerSessionNotifications()
    configureSessionAsync()

    let governor = SupyThermalGovernor { [weak self] state, shouldPause, shouldThrottle in
      self?.handleThermalChange(
        state: state,
        shouldPause: shouldPause,
        shouldThrottle: shouldThrottle
      )
    }
    self.thermalGovernor = governor
    governor.start()
  }

  // MARK: - Thermal

  private func handleThermalChange(
    state: SupyThermalGovernor.State,
    shouldPause: Bool,
    shouldThrottle: Bool
  ) {
    sendEvent([
      "type": "thermal",
      "state": state.rawValue,
      "paused": shouldPause,
      "throttled": shouldThrottle,
    ])
    sessionQueue.async { [weak self] in
      guard let self = self else { return }
      if shouldPause {
        self.thermalPaused = true
        if self.session.isRunning {
          self.session.stopRunning()
        }
      } else {
        let wasPaused = self.thermalPaused
        self.thermalPaused = false
        if let device = self.videoDevice {
          self.applyThermalFpsAdjustment(device: device, throttle: shouldThrottle)
        }
        if wasPaused {
          self.safeStartRunning()
        }
      }
    }
  }

  /// Halves the camera's max frame rate while throttled. Restores the
  /// per-tier cap (or uncaps on HIGH) on recovery.
  private func applyThermalFpsAdjustment(device: AVCaptureDevice, throttle: Bool) {
    let tier = SupyDeviceTier.detect()
    let baseFps = tier.analyzerFpsCap ?? 30
    let targetFps = throttle ? max(10, baseFps / 2) : baseFps
    do {
      try device.lockForConfiguration()
      let duration = CMTime(value: 1, timescale: CMTimeScale(targetFps))
      device.activeVideoMinFrameDuration = duration
      device.activeVideoMaxFrameDuration = duration
      device.unlockForConfiguration()
    } catch {
      // Best-effort.
    }
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
    // AVFoundation often hands us back a session that can recover with a fresh
    // startRunning once we're back on the queue. If the error was a media
    // services reset we'd need to rebuild inputs — out of scope for the v1
    // patch; surface it to Flutter and let the host recreate the view.
    // Mid-session permission revocation (Settings → Privacy → Camera off) lands
    // here too, as `AVError.applicationIsNotAuthorizedToUseDevice` — surface it as
    // `permission_denied` so the host can distinguish from hardware failure.
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
  /// from `sessionQueue`. No-ops if the session is interrupted (AVFoundation
  /// would throw) or already running.
  private func safeStartRunning() {
    guard !sessionInterrupted else { return }
    guard !thermalPaused else { return }
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
    session.sessionPreset = SupyBarcodeScannerView.sessionPreset(for: tier)

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

    SupyBarcodeScannerView.applyFpsCap(tier: tier, device: device)

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

    applyInitialCameraConfig()
    safeStartRunning()
  }

  private func applyInitialCameraConfig() {
    guard let device = videoDevice else { return }
    do {
      try device.lockForConfiguration()
      if initialCameraConfig.initialZoom != 1.0 {
        let clamped = max(
          device.minAvailableVideoZoomFactor,
          min(initialCameraConfig.initialZoom, device.maxAvailableVideoZoomFactor)
        )
        device.videoZoomFactor = clamped
      }
      let wantsClose = initialCameraConfig.minFocusDistanceLock
        || initialCameraConfig.scanRange == "close"
      if wantsClose && device.isAutoFocusRangeRestrictionSupported {
        device.autoFocusRangeRestriction = .near
        if device.isFocusModeSupported(.continuousAutoFocus) {
          device.focusMode = .continuousAutoFocus
        }
      }
      device.unlockForConfiguration()
    } catch {
      // Best-effort — preview still starts with default config.
    }
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
    case "setZoom":
      let factor = (call.arguments as? [String: Any])?["factor"] as? Double ?? 1.0
      setZoom(factor: CGFloat(factor), result: result)
    case "flipCamera":
      flipCamera(result: result)
    case "setMinFocusDistanceLock":
      let on = (call.arguments as? [String: Any])?["on"] as? Bool ?? false
      setMinFocusDistanceLock(on: on, result: result)
    case "setFormats":
      let formats =
        (call.arguments as? [String: Any])?["formats"] as? [String] ?? []
      detector.setSymbologies(SymbologyMapper.toVisionSymbologies(formats))
      detector.setUseNativeCore(nativeCoreEnabled, formats: formats)
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

  private func setZoom(factor: CGFloat, result: @escaping FlutterResult) {
    sessionQueue.async { [weak self] in
      guard let device = self?.videoDevice else {
        DispatchQueue.main.async { result(nil) }
        return
      }
      let clamped = max(device.minAvailableVideoZoomFactor,
                        min(factor, device.maxAvailableVideoZoomFactor))
      do {
        try device.lockForConfiguration()
        device.videoZoomFactor = clamped
        device.unlockForConfiguration()
      } catch {
        // Swallow — best-effort.
      }
      let applied = Double(device.videoZoomFactor)
      DispatchQueue.main.async { result(["zoom": applied]) }
    }
  }

  private func flipCamera(result: @escaping FlutterResult) {
    sessionQueue.async { [weak self] in
      guard let self = self else { return }
      let currentPosition = self.videoDevice?.position ?? .back
      let nextPosition: AVCaptureDevice.Position =
        currentPosition == .back ? .front : .back
      guard let nextDevice = AVCaptureDevice.default(
        .builtInWideAngleCamera, for: .video, position: nextPosition
      ) else {
        DispatchQueue.main.async {
          result(["position": currentPosition == .front ? "front" : "back"])
        }
        return
      }

      // Build the new input first so we don't tear down the existing one
      // unless the swap is guaranteed to succeed. If construction fails,
      // leave the session untouched and report the current position.
      let newInput: AVCaptureDeviceInput
      do {
        newInput = try AVCaptureDeviceInput(device: nextDevice)
      } catch {
        DispatchQueue.main.async {
          result(["position": currentPosition == .front ? "front" : "back"])
        }
        return
      }

      self.session.beginConfiguration()
      let previousInputs = self.session.inputs
      for input in previousInputs {
        self.session.removeInput(input)
      }
      let swapped: Bool
      if self.session.canAddInput(newInput) {
        self.session.addInput(newInput)
        self.videoDevice = nextDevice
        swapped = true
      } else {
        // Restore previous inputs to avoid committing a zero-input session.
        for input in previousInputs where self.session.canAddInput(input) {
          self.session.addInput(input)
        }
        swapped = false
      }
      self.session.commitConfiguration()

      if swapped {
        // The new device needs the configured initial zoom / focus lock
        // re-applied (lens-specific state doesn't transfer), and the host
        // needs a fresh preview_started so it can refresh flash availability.
        self.applyInitialCameraConfig()
        DispatchQueue.main.async {
          self.previewStartedAnnounced = false
          if self.session.isRunning {
            self.previewStartedAnnounced = true
            self.emitPreviewStarted()
          }
          result(["position": nextPosition == .front ? "front" : "back"])
        }
      } else {
        DispatchQueue.main.async {
          result(["position": currentPosition == .front ? "front" : "back"])
        }
      }
    }
  }

  private func setMinFocusDistanceLock(on: Bool, result: @escaping FlutterResult) {
    sessionQueue.async { [weak self] in
      guard let device = self?.videoDevice else {
        DispatchQueue.main.async { result(nil) }
        return
      }
      do {
        try device.lockForConfiguration()
        if on {
          // Close-focus heuristic: lock autofocus to macro range when supported.
          if device.isAutoFocusRangeRestrictionSupported {
            device.autoFocusRangeRestriction = .near
          }
          if device.isFocusModeSupported(.continuousAutoFocus) {
            device.focusMode = .continuousAutoFocus
          }
        } else {
          if device.isAutoFocusRangeRestrictionSupported {
            device.autoFocusRangeRestriction = .none
          }
        }
        device.unlockForConfiguration()
      } catch {
        // Swallow — best-effort.
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
    // Signal stream completion to the Dart side before detaching the handler,
    // so subscribers see a clean `onDone` instead of a silent drop. Sink calls
    // must happen on the platform thread.
    if let sink = eventSink {
      eventSink = nil
      if Thread.isMainThread {
        sink(FlutterEndOfEventStream)
      } else {
        DispatchQueue.main.async { sink(FlutterEndOfEventStream) }
      }
    }
    eventChannel.setStreamHandler(nil)
    thermalGovernor?.stop()
    thermalGovernor = nil
    runningObservation?.invalidate()
    runningObservation = nil
    NotificationCenter.default.removeObserver(self)
    // Detach the sample-buffer delegate synchronously so AVFoundation cannot
    // dispatch one more `captureOutput(_:didOutput:from:)` after the owning
    // view has been torn down. `stopRunning()` is async on `sessionQueue` and
    // would otherwise leave a window where a stale frame can fire through the
    // detector against a deinitialized view.
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

  /// Caps the camera's frame delivery rate for MID/LOW tiers. HIGH tier
  /// leaves the device on its native cadence. Must be called inside a
  /// `session.beginConfiguration() / commitConfiguration()` block.
  private static func applyFpsCap(tier: SupyDeviceTier, device: AVCaptureDevice) {
    guard let fps = tier.analyzerFpsCap else { return }
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

/// Host view for `AVCaptureVideoPreviewLayer`. Keeps the layer sized to its
/// bounds across layout passes so the preview isn't stuck at zero size when
/// the platform view is created before Flutter has finalized the frame.
final class PreviewContainerView: UIView {
  private weak var previewLayer: AVCaptureVideoPreviewLayer?

  func attach(previewLayer: AVCaptureVideoPreviewLayer) {
    previewLayer.frame = bounds
    layer.addSublayer(previewLayer)
    self.previewLayer = previewLayer
    setNeedsLayout()
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    guard let previewLayer = previewLayer else { return }
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    previewLayer.frame = bounds
    if let connection = previewLayer.connection,
       connection.isVideoOrientationSupported {
      connection.videoOrientation = Self.currentVideoOrientation()
    }
    CATransaction.commit()
  }

  private static func currentVideoOrientation() -> AVCaptureVideoOrientation {
    let interfaceOrientation: UIInterfaceOrientation
    if let scene = UIApplication.shared.connectedScenes
      .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene {
      interfaceOrientation = scene.interfaceOrientation
    } else {
      interfaceOrientation = .portrait
    }
    switch interfaceOrientation {
    case .landscapeLeft: return .landscapeLeft
    case .landscapeRight: return .landscapeRight
    case .portraitUpsideDown: return .portraitUpsideDown
    default: return .portrait
    }
  }
}
