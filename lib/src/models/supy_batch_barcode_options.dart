import 'package:meta/meta.dart';

import 'supy_barcode_format.dart';

/// Options for the batch (continuous) barcode scanner.
///
/// Matches the Scanbot `BatchBarcodeScannerConfiguration` surface that the
/// retailer app already consumes — see `docs/MIGRATION.md`.
@immutable
class SupyBatchBarcodeScanOptions {
  /// Creates batch barcode scan options.
  const SupyBatchBarcodeScanOptions({
    this.formats = const [SupyBarcodeFormat.all],
    this.maxBatchCount = 0,
    this.dedupeWindowMs = 800,
    this.beep = true,
    this.vibrate = true,
  });

  /// Active symbologies. Defaults to [SupyBarcodeFormat.all].
  final List<SupyBarcodeFormat> formats;

  /// Maximum unique items the session will accumulate before auto-finishing.
  /// `0` means no cap — the session ends only when the user taps Done.
  final int maxBatchCount;

  /// Cooldown window during which a repeated payload is considered a
  /// duplicate of the previous identical scan rather than a new acquisition.
  final int dedupeWindowMs;

  /// Whether to play a short confirmation beep on each unique acquisition.
  final bool beep;

  /// Whether to fire a haptic on each unique acquisition.
  final bool vibrate;

  /// Serializes to the channel argument shape.
  Map<String, Object?> toWire() => {
    'formats': formats.map((f) => f.wireName).toList(),
    'maxBatchCount': maxBatchCount,
    'dedupeWindowMs': dedupeWindowMs,
    'beep': beep,
    'vibrate': vibrate,
  };
}
