import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../channel/supy_scanner_channel.dart';
import '../models/supy_document_frame_state.dart';
import '../models/supy_document_page.dart';

/// Raw capture result returned by [SupyDocumentScannerController.captureAndRectify]
/// and [SupyDocumentScannerController.captureFullFrame].
///
/// Distinct from [SupyDocumentPage] (which is the persisted, scored,
/// review-ready page surfaced to retailers): this is the immediate output of
/// a single still capture. `quad` is empty for full-frame captures.
@immutable
class SupyDocumentCapture {
  /// Creates a capture result.
  const SupyDocumentCapture({
    required this.path,
    required this.widthPx,
    required this.heightPx,
    this.quad = const <Offset>[],
    this.quadSource,
  });

  /// Parses a capture result from a channel map. Accepts wide payloads with
  /// extra keys (the native side may emit `uri`/`width`/`height` legacy keys
  /// alongside the canonical `path`/`widthPx`/`heightPx` for compatibility
  /// with the older [SupyDocumentPage.fromMap] consumer).
  factory SupyDocumentCapture.fromMap(Map<Object?, Object?> map) {
    final rawQuad = map['quad'];
    final quad = <Offset>[];
    if (rawQuad is List) {
      for (final p in rawQuad) {
        if (p is Map) {
          final x = (p['x'] as num?)?.toDouble();
          final y = (p['y'] as num?)?.toDouble();
          if (x != null && y != null) {
            quad.add(Offset(x, y));
          }
        }
      }
    }
    return SupyDocumentCapture(
      path: map['path']! as String,
      widthPx: (map['widthPx']! as num).toInt(),
      heightPx: (map['heightPx']! as num).toInt(),
      quad: List<Offset>.unmodifiable(quad),
      quadSource: map['quadSource'] as String?,
    );
  }

  /// Filesystem path of the persisted JPEG.
  final String path;

  /// Pixel width of the persisted image.
  final int widthPx;

  /// Pixel height of the persisted image.
  final int heightPx;

  /// Normalized (top-left-origin) quad corners used to rectify the source
  /// frame. Empty for full-frame captures.
  final List<Offset> quad;

  /// How the rectification quad was obtained on iOS: `'refined'` when the
  /// on-still re-detection was accepted, `'preview'` when the mapped preview
  /// quad was used. `null` on platforms/paths that don't report it.
  final String? quadSource;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SupyDocumentCapture &&
          other.path == path &&
          other.widthPx == widthPx &&
          other.heightPx == heightPx &&
          other.quadSource == quadSource &&
          _quadsEqual(other.quad, quad);

  @override
  int get hashCode =>
      Object.hash(path, widthPx, heightPx, quadSource, Object.hashAll(quad));

  @override
  String toString() =>
      'SupyDocumentCapture(path: $path, ${widthPx}x$heightPx, quad: $quad, '
      'quadSource: $quadSource)';
}

bool _quadsEqual(List<Offset> a, List<Offset> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Capture-lifecycle phase exposed by [SupyDocumentScannerController].
///
/// Driven by `controller.capture()` (V1-S6-03) and observed by the view to
/// overlay [SupyDocumentFrameState.capturing] / `.captured` on top of the
/// FSM output for the duration of the capture.
enum SupyDocumentCapturePhase {
  /// No capture in flight — FSM output drives the overlay.
  idle,

  /// Capture is in flight; native side is rectifying. Overlay forces
  /// [SupyDocumentFrameState.capturing].
  capturing,

  /// Capture finished. Overlay forces [SupyDocumentFrameState.captured] for
  /// a brief moment, then the controller resets to [idle].
  captured,
}

/// Controls a mounted `SupyDocumentScannerView` via its per-view MethodChannel.
///
/// Channel name follows `docs/ARCHITECTURE.md`:
/// `io.supy.scanner/v1/document/<viewId>`.
class SupyDocumentScannerController extends ChangeNotifier {
  /// Creates a controller. It becomes usable once the widget mounts.
  SupyDocumentScannerController();

  MethodChannel? _channel;
  bool _torchOn = false;
  bool _paused = false;
  SupyDocumentCapturePhase _capturePhase = SupyDocumentCapturePhase.idle;

  /// Whether the torch is currently on (last requested value).
  bool get torchOn => _torchOn;

  /// Whether the preview is currently paused (last requested value).
  bool get paused => _paused;

  /// `true` once the widget has bound this controller to a live PlatformView.
  bool get isAttached => _channel != null;

  /// Current capture-lifecycle phase. Defaults to
  /// [SupyDocumentCapturePhase.idle]; transitions to `capturing` while a
  /// capture is in flight and `captured` for a brief flash on completion.
  SupyDocumentCapturePhase get capturePhase => _capturePhase;

  /// Internal — sets the capture phase and notifies the view so it can overlay
  /// the matching [SupyDocumentFrameState] on top of FSM output.
  @internal
  void setCapturePhase(SupyDocumentCapturePhase phase) {
    if (_capturePhase == phase) return;
    _capturePhase = phase;
    notifyListeners();
  }

  /// Maps the current [capturePhase] onto the UI-only frame states. Returns
  /// `null` while idle so the view falls back to the FSM-emitted state.
  SupyDocumentFrameState? get capturePhaseAsFrameState {
    switch (_capturePhase) {
      case SupyDocumentCapturePhase.idle:
        return null;
      case SupyDocumentCapturePhase.capturing:
        return SupyDocumentFrameState.capturing;
      case SupyDocumentCapturePhase.captured:
        return SupyDocumentFrameState.captured;
    }
  }

  /// Internal — invoked by `SupyDocumentScannerView` on platform-view creation.
  @internal
  void attach(MethodChannel channel) {
    _channel = channel;
    notifyListeners();
  }

  /// Internal — invoked by `SupyDocumentScannerView` on detach.
  @internal
  void detach() {
    _channel = null;
  }

  /// Pauses the camera preview + detector.
  Future<void> pause() async {
    final channel = _channel;
    if (channel == null) return;
    await channel.invokeMethod<void>('pause');
    _paused = true;
    notifyListeners();
  }

  /// Resumes the camera preview + detector.
  Future<void> resume() async {
    final channel = _channel;
    if (channel == null) return;
    await channel.invokeMethod<void>('resume');
    _paused = false;
    notifyListeners();
  }

  /// Triggers a one-shot capture: grabs the next preview frame, rectifies it
  /// to a top-down rectangle (warpPerspective, ≥300 DPI when [SupyDocumentScanOptions.useNativeCore]
  /// is on), and returns the resulting page.
  ///
  /// Drives [capturePhase] through `capturing → captured → idle` so the view's
  /// guidance overlay reflects the lifecycle. Idempotent on a not-yet-attached
  /// controller (no-op) and on a re-entrant call (the second call is ignored
  /// while the first is in flight).
  ///
  /// Returns `null` if the controller isn't attached. Throws on native error;
  /// the phase resets to `idle` before the throw.
  Future<SupyDocumentPage?> capture() async {
    final channel = _channel;
    if (channel == null) return null;
    if (_capturePhase != SupyDocumentCapturePhase.idle) return null;
    setCapturePhase(SupyDocumentCapturePhase.capturing);
    try {
      final result = await channel.invokeMapMethod<Object?, Object?>(
        'captureAndRectify',
      );
      if (result == null) {
        setCapturePhase(SupyDocumentCapturePhase.idle);
        return null;
      }
      setCapturePhase(SupyDocumentCapturePhase.captured);
      return SupyDocumentPage.fromMap(result);
    } catch (_) {
      setCapturePhase(SupyDocumentCapturePhase.idle);
      rethrow;
    }
  }

  /// Captures a still and runs perspective rectification against the most
  /// recent smoothed quad from the native detector. Returns the rectified
  /// JPEG on disk.
  ///
  /// Throws a `StateError` with `captureUnsupported: …` when the native side
  /// reports `PlatformException(code: 'UNIMPLEMENTED')` — i.e. the device
  /// can't satisfy the request (no quad available, missing platform support).
  /// Other `PlatformException`s rethrow unchanged.
  Future<SupyDocumentCapture> captureAndRectify() async {
    final channel = _channel;
    if (channel == null) {
      throw StateError('captureUnsupported: controller not attached');
    }
    try {
      final result = await channel
          .invokeMapMethod<Object?, Object?>('captureAndRectify');
      if (result == null) {
        throw StateError('captureUnsupported: native returned null');
      }
      return SupyDocumentCapture.fromMap(result);
    } on PlatformException catch (e) {
      if (e.code == 'UNIMPLEMENTED' || e.code == 'captureUnsupported') {
        throw StateError(
          'captureUnsupported: ${e.message ?? e.code}',
        );
      }
      rethrow;
    }
  }

  /// Captures a single full-frame still without rectification. Used as the
  /// fallback path when no quad is locked in.
  ///
  /// Throws a `StateError` with `captureUnsupported: …` when the native side
  /// reports `PlatformException(code: 'UNIMPLEMENTED')` — mirrors
  /// [captureAndRectify] so retailers can catch one error type for both.
  /// Other `PlatformException`s rethrow unchanged.
  Future<SupyDocumentCapture> captureFullFrame() async {
    final channel = _channel;
    if (channel == null) {
      throw StateError('captureUnsupported: controller not attached');
    }
    try {
      final result =
          await channel.invokeMapMethod<Object?, Object?>('captureFullFrame');
      if (result == null) {
        throw StateError('captureUnsupported: native returned null');
      }
      return SupyDocumentCapture.fromMap(result);
    } on PlatformException catch (e) {
      if (e.code == 'UNIMPLEMENTED' || e.code == 'captureUnsupported') {
        throw StateError(
          'captureUnsupported: ${e.message ?? e.code}',
        );
      }
      rethrow;
    }
  }

  /// Resets [capturePhase] to [SupyDocumentCapturePhase.idle]. Call after the
  /// host UI has acknowledged a `captured` state (e.g. once the page has been
  /// pushed onto the multi-page review stack).
  void clearCapturePhase() {
    setCapturePhase(SupyDocumentCapturePhase.idle);
  }

  /// Toggles the torch on the active camera.
  Future<void> setTorch({required bool on}) async {
    final channel = _channel;
    if (channel == null) return;
    await channel.invokeMethod<void>('setTorch', <String, Object?>{'on': on});
    _torchOn = on;
    notifyListeners();
  }

  @override
  void dispose() {
    _channel = null;
    super.dispose();
  }
}

/// Builds the per-view MethodChannel name for the document scanner.
String supyDocumentMethodChannelName(int viewId) =>
    'io.supy.scanner/$kSupyScannerChannelVersion/document/$viewId';
