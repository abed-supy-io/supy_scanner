import AVFoundation
import AudioToolbox
import Flutter
import UIKit
import Vision

/// Presents a full-screen continuous barcode scanner over the host app's
/// root view controller and bridges the assembled result back to the
/// `scanBarcodesBatch` MethodChannel call.
///
/// Parity with Android `BatchBarcodeScannerActivity`:
///   - Same-payload dedupe window (default 800ms).
///   - Already-seen payloads silently increment `duplicateCount`.
///   - Optional beep + haptic on a fresh unique scan.
///   - Optional `maxBatchCount` cap (0 = unlimited).
final class BatchBarcodeScannerPresenter: NSObject {

  private var pendingResult: FlutterResult?

  func present(args: [String: Any]?, result: @escaping FlutterResult) {
    guard pendingResult == nil else {
      result(
        FlutterError(
          code: "unknown",
          message: "A batch barcode scan is already in progress",
          details: nil
        )
      )
      return
    }

    let status = AVCaptureDevice.authorizationStatus(for: .video)
    switch status {
    case .denied, .restricted:
      result(
        FlutterError(
          code: "permission_denied",
          message: "Camera permission not granted",
          details: nil
        )
      )
      return
    case .notDetermined, .authorized:
      break
    @unknown default:
      break
    }

    guard let rootViewController = Self.rootViewController() else {
      result(
        FlutterError(
          code: "camera_unavailable",
          message: "No root view controller to present from",
          details: nil
        )
      )
      return
    }

    pendingResult = result

    let formats = (args?["formats"] as? [String]) ?? []
    let maxBatchCount = (args?["maxBatchCount"] as? Int) ?? 0
    let dedupeWindowMs = (args?["dedupeWindowMs"] as? Int) ?? 800
    let beep = (args?["beep"] as? Bool) ?? true
    let vibrate = (args?["vibrate"] as? Bool) ?? true

    let vc = BatchBarcodeScannerViewController(
      symbologies: SymbologyMapper.toVisionSymbologies(formats),
      maxBatchCount: maxBatchCount,
      dedupeWindowMs: dedupeWindowMs,
      beep: beep,
      vibrate: vibrate
    )
    vc.modalPresentationStyle = .fullScreen
    vc.onFinish = { [weak self] outcome in
      vc.dismiss(animated: true)
      self?.complete(outcome: outcome)
    }

    DispatchQueue.main.async {
      rootViewController.present(vc, animated: true)
    }
  }

  private func complete(outcome: BatchBarcodeScannerViewController.Outcome) {
    let result = pendingResult
    pendingResult = nil
    let dispatch: () -> Void = {
      switch outcome {
      case .cancelled:
        result?(
          FlutterError(
            code: "cancelled",
            message: "User cancelled the batch scan",
            details: nil
          )
        )
      case .failed(let code, let message):
        result?(
          FlutterError(code: code, message: message, details: nil)
        )
      case .success(let items, let duplicateCount):
        result?([
          "items": items,
          "duplicateCount": duplicateCount,
        ])
      }
    }
    if Thread.isMainThread {
      dispatch()
    } else {
      DispatchQueue.main.async(execute: dispatch)
    }
  }

  private static func rootViewController() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
    let keyWindow = scenes
      .flatMap { $0.windows }
      .first(where: { $0.isKeyWindow })
    var top = keyWindow?.rootViewController
    while let presented = top?.presentedViewController {
      top = presented
    }
    return top
  }
}

/// Full-screen UIViewController that runs `AVCaptureSession` + the shared
/// `BarcodeDetector`, accumulating unique scans until Done or the cap is
/// reached.
final class BatchBarcodeScannerViewController: UIViewController {

  enum Outcome {
    case success(items: [[String: String]], duplicateCount: Int)
    case cancelled
    case failed(code: String, message: String)
  }

  var onFinish: ((Outcome) -> Void)?

  private let session: AVCaptureSession = AVCaptureSession()
  private let sessionQueue: DispatchQueue = DispatchQueue(
    label: "io.supy.scanner.batch.session",
    qos: .userInitiated
  )
  private let detector: BarcodeDetector = BarcodeDetector()
  private let videoDataOutput: AVCaptureVideoDataOutput = AVCaptureVideoDataOutput()

  private var previewLayer: AVCaptureVideoPreviewLayer?

  private let symbologies: [VNBarcodeSymbology]?
  private let maxBatchCount: Int
  private let dedupeWindowMs: Int
  private let beep: Bool
  private let vibrate: Bool

  private let stateLock = NSLock()
  private var items: [[String: String]] = []
  private var seen: Set<String> = []
  private var lastSeenAt: [String: CFAbsoluteTime] = [:]
  private var duplicateCount: Int = 0
  private var finished: Bool = false

  /// Mirrors `SupyBarcodeScannerView.sessionInterrupted`. AVFoundation keeps
  /// an internal config block open across interruptions; calling
  /// `startRunning()` while interrupted raises NSGenericException on some
  /// iPhones. Gate on this in `safeStartRunning()`.
  private var sessionInterrupted: Bool = false

  private let counterLabel: UILabel = UILabel()
  private let doneButton: UIButton = UIButton(type: .system)
  private let cancelButton: UIButton = UIButton(type: .system)
  private let impact: UIImpactFeedbackGenerator =
    UIImpactFeedbackGenerator(style: .medium)

  init(
    symbologies: [VNBarcodeSymbology]?,
    maxBatchCount: Int,
    dedupeWindowMs: Int,
    beep: Bool,
    vibrate: Bool
  ) {
    self.symbologies = symbologies
    self.maxBatchCount = maxBatchCount
    self.dedupeWindowMs = dedupeWindowMs
    self.beep = beep
    self.vibrate = vibrate
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  override var prefersStatusBarHidden: Bool { true }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .black
    buildChrome()
    registerSessionNotifications()

    detector.setSymbologies(symbologies)
    detector.onDetections = { [weak self] detections in
      self?.handleDetections(detections)
    }
    detector.onError = { [weak self] message in
      self?.finishFailed(code: "unknown", message: message)
    }

    let status = AVCaptureDevice.authorizationStatus(for: .video)
    if status == .notDetermined {
      AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
        guard let self = self else { return }
        if granted {
          self.sessionQueue.async { self.configureSession() }
        } else {
          DispatchQueue.main.async {
            self.finishFailed(
              code: "permission_denied",
              message: "Camera permission not granted"
            )
          }
        }
      }
    } else {
      sessionQueue.async { [weak self] in self?.configureSession() }
    }
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    previewLayer?.frame = view.bounds
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    sessionQueue.async { [weak self] in
      guard let self = self else { return }
      if self.session.isRunning {
        self.session.stopRunning()
      }
    }
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  // MARK: - Session interruption guard

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
    DispatchQueue.main.async { [weak self] in
      self?.finishFailed(
        code: "camera_unavailable",
        message: "AVCaptureSession runtime error: \(error?.localizedDescription ?? "unknown")"
      )
    }
  }

  /// Must be called from `sessionQueue`.
  private func safeStartRunning() {
    guard !sessionInterrupted else { return }
    guard !session.isRunning else { return }
    session.startRunning()
  }

  // MARK: - UI

  private func buildChrome() {
    counterLabel.translatesAutoresizingMaskIntoConstraints = false
    counterLabel.textColor = .white
    counterLabel.font = .systemFont(ofSize: 17, weight: .semibold)
    counterLabel.textAlignment = .center
    counterLabel.backgroundColor = UIColor.black.withAlphaComponent(0.55)
    counterLabel.layer.cornerRadius = 14
    counterLabel.layer.masksToBounds = true
    view.addSubview(counterLabel)

    cancelButton.translatesAutoresizingMaskIntoConstraints = false
    cancelButton.setTitle("Cancel", for: .normal)
    cancelButton.setTitleColor(.white, for: .normal)
    cancelButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .regular)
    cancelButton.backgroundColor = UIColor.black.withAlphaComponent(0.55)
    cancelButton.layer.cornerRadius = 22
    cancelButton.contentEdgeInsets = UIEdgeInsets(
      top: 10, left: 22, bottom: 10, right: 22)
    cancelButton.addTarget(
      self, action: #selector(onCancelTapped), for: .touchUpInside)
    view.addSubview(cancelButton)

    doneButton.translatesAutoresizingMaskIntoConstraints = false
    doneButton.setTitle("Done", for: .normal)
    doneButton.setTitleColor(.white, for: .normal)
    doneButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
    // Supy brand primary (matches `SupyScannerPalette.scanbotDark.primary`).
    // Mirrored on Android in BatchBarcodeScannerActivity.kt.
    doneButton.backgroundColor = UIColor(
      red: 0x1A / 255.0, green: 0xC0 / 255.0, blue: 0xE5 / 255.0, alpha: 1.0)
    doneButton.layer.cornerRadius = 22
    doneButton.contentEdgeInsets = UIEdgeInsets(
      top: 10, left: 28, bottom: 10, right: 28)
    doneButton.addTarget(
      self, action: #selector(onDoneTapped), for: .touchUpInside)
    view.addSubview(doneButton)

    NSLayoutConstraint.activate([
      counterLabel.topAnchor.constraint(
        equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
      counterLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      counterLabel.heightAnchor.constraint(equalToConstant: 36),
      counterLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 120),

      cancelButton.leadingAnchor.constraint(
        equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
      cancelButton.bottomAnchor.constraint(
        equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),

      doneButton.trailingAnchor.constraint(
        equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
      doneButton.bottomAnchor.constraint(
        equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
    ])

    refreshCounter()
  }

  private func refreshCounter() {
    let count = items.count
    let text: String
    if maxBatchCount > 0 {
      text = "  \(count) / \(maxBatchCount)  "
    } else {
      text = "  \(count)  "
    }
    if Thread.isMainThread {
      counterLabel.text = text
    } else {
      DispatchQueue.main.async { [weak self] in
        self?.counterLabel.text = text
      }
    }
  }

  // MARK: - Session

  private func configureSession() {
    session.beginConfiguration()
    session.sessionPreset = .high

    guard
      let device = AVCaptureDevice.default(
        .builtInWideAngleCamera, for: .video, position: .back)
    else {
      session.commitConfiguration()
      DispatchQueue.main.async { [weak self] in
        self?.finishFailed(
          code: "camera_unavailable", message: "No back camera available")
      }
      return
    }

    do {
      let input = try AVCaptureDeviceInput(device: device)
      guard session.canAddInput(input) else {
        session.commitConfiguration()
        DispatchQueue.main.async { [weak self] in
          self?.finishFailed(
            code: "camera_unavailable",
            message: "Cannot attach camera input")
        }
        return
      }
      session.addInput(input)
    } catch {
      session.commitConfiguration()
      DispatchQueue.main.async { [weak self] in
        self?.finishFailed(
          code: "camera_unavailable",
          message: "Camera input init failed: \(error.localizedDescription)")
      }
      return
    }

    videoDataOutput.alwaysDiscardsLateVideoFrames = true
    videoDataOutput.videoSettings = [
      kCVPixelBufferPixelFormatTypeKey as String:
        kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
    ]
    videoDataOutput.setSampleBufferDelegate(
      detector, queue: detector.sampleBufferQueue)
    if session.canAddOutput(videoDataOutput) {
      session.addOutput(videoDataOutput)
    }

    session.commitConfiguration()

    DispatchQueue.main.async { [weak self] in
      self?.attachPreview()
    }

    safeStartRunning()
  }

  private func attachPreview() {
    let layer = AVCaptureVideoPreviewLayer(session: session)
    layer.videoGravity = .resizeAspectFill
    layer.frame = view.bounds
    view.layer.insertSublayer(layer, at: 0)
    previewLayer = layer
  }

  // MARK: - Detection

  private func handleDetections(_ detections: [DetectedBarcode]) {
    let now = CFAbsoluteTimeGetCurrent()
    let windowSeconds = Double(dedupeWindowMs) / 1000.0
    var hitFresh = false
    var capReached = false

    stateLock.lock()
    if finished {
      stateLock.unlock()
      return
    }
    for d in detections {
      let raw = d.rawValue
      if let last = lastSeenAt[raw], now - last < windowSeconds {
        duplicateCount += 1
        lastSeenAt[raw] = now
        continue
      }
      lastSeenAt[raw] = now
      if seen.contains(raw) {
        duplicateCount += 1
        continue
      }
      seen.insert(raw)
      items.append(["rawValue": raw, "format": d.format])
      hitFresh = true
      if maxBatchCount > 0 && items.count >= maxBatchCount {
        capReached = true
        break
      }
    }
    let shouldEmitSuccess = capReached
    let snapshotItems = items
    let snapshotDuplicates = duplicateCount
    if capReached { finished = true }
    stateLock.unlock()

    if hitFresh {
      refreshCounter()
      provideFeedback()
    }
    if shouldEmitSuccess {
      DispatchQueue.main.async { [weak self] in
        self?.onFinish?(
          .success(items: snapshotItems, duplicateCount: snapshotDuplicates))
      }
    }
  }

  private func provideFeedback() {
    if beep {
      // 1057 = "Tink" — short, distinct, available on every iOS device.
      AudioServicesPlaySystemSound(1057)
    }
    if vibrate {
      DispatchQueue.main.async { [weak self] in
        self?.impact.impactOccurred()
      }
    }
  }

  // MARK: - Buttons

  @objc private func onDoneTapped() {
    stateLock.lock()
    if finished {
      stateLock.unlock()
      return
    }
    finished = true
    let snapshotItems = items
    let snapshotDuplicates = duplicateCount
    stateLock.unlock()
    onFinish?(
      .success(items: snapshotItems, duplicateCount: snapshotDuplicates))
  }

  @objc private func onCancelTapped() {
    stateLock.lock()
    if finished {
      stateLock.unlock()
      return
    }
    finished = true
    stateLock.unlock()
    onFinish?(.cancelled)
  }

  private func finishFailed(code: String, message: String) {
    stateLock.lock()
    if finished {
      stateLock.unlock()
      return
    }
    finished = true
    stateLock.unlock()
    onFinish?(.failed(code: code, message: message))
  }
}
