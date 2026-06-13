import 'package:flutter/services.dart';

import '../models/supy_barcode.dart';
import '../models/supy_scan_error.dart';
import 'supy_scanner_channel.dart';

/// Events streamed from a per-view EventChannel during embedded barcode
/// scanning.
sealed class SupyScannerEvent {
  /// Const constructor for subclasses.
  const SupyScannerEvent();

  /// Parses a raw event map from the platform channel.
  factory SupyScannerEvent.fromMap(Map<Object?, Object?> map) {
    final type = map['type'] as String?;
    switch (type) {
      case 'detection':
        final raw = (map['items'] as List<Object?>?) ?? const [];
        final items = raw
            .cast<Map<Object?, Object?>>()
            .map(SupyBarcode.fromMap)
            .toList(growable: false);
        return SupyDetectionEvent(items: List.unmodifiable(items));
      case 'preview_started':
        return SupyPreviewStartedEvent(
          flashAvailable: (map['flashAvailable'] as bool?) ?? false,
        );
      case 'error':
        return SupyErrorEvent(
          error: SupyScanError(
            code: SupyScanErrorCode.fromWire(map['code'] as String?),
            message: (map['message'] as String?) ?? 'Unknown scanner error',
          ),
        );
      default:
        return SupyErrorEvent(
          error: SupyScanError(
            code: SupyScanErrorCode.unknown,
            message: 'Unrecognized event type: $type',
          ),
        );
    }
  }
}

/// One pass of detected barcodes.
class SupyDetectionEvent extends SupyScannerEvent {
  /// Creates a detection event.
  const SupyDetectionEvent({required this.items});

  /// Barcodes detected in this pass.
  final List<SupyBarcode> items;
}

/// Emitted once the native camera preview has actually started rendering.
class SupyPreviewStartedEvent extends SupyScannerEvent {
  /// Creates a preview-started event.
  const SupyPreviewStartedEvent({required this.flashAvailable});

  /// `true` when the active camera has a torch / flash unit.
  final bool flashAvailable;
}

/// A native error reported via the EventChannel.
class SupyErrorEvent extends SupyScannerEvent {
  /// Creates an error event.
  const SupyErrorEvent({required this.error});

  /// The wrapped scanner error.
  final SupyScanError error;
}

/// Builds a per-view [EventChannel] for the embedded barcode scanner.
///
/// The native side opens `io.supy.scanner/v1/barcode/<viewId>/events` as the
/// EventChannel for each `SupyBarcodeScannerView` PlatformView.
EventChannel supyBarcodeEventChannel(int viewId) {
  return EventChannel(
    'io.supy.scanner/$kSupyScannerChannelVersion/barcode/$viewId/events',
  );
}

/// Convenience: maps raw EventChannel payloads to typed [SupyScannerEvent]s.
Stream<SupyScannerEvent> supyBarcodeEventStream(int viewId) {
  return supyBarcodeEventChannel(viewId).receiveBroadcastStream().map((event) {
    if (event is Map) {
      return SupyScannerEvent.fromMap(event.cast<Object?, Object?>());
    }
    return const SupyErrorEvent(
      error: SupyScanError(
        code: SupyScanErrorCode.unknown,
        message: 'Unexpected non-map event payload from native channel',
      ),
    );
  });
}
