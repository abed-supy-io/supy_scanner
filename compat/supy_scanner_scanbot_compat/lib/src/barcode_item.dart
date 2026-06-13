import 'package:meta/meta.dart';
import 'package:supy_scanner/supy_scanner.dart';

/// Mirrors the Scanbot `BarcodeItem` shape used by the retailer.
///
/// Retailer call sites only read `.text`; the rest of the original Scanbot
/// `BarcodeItem` (raw bytes, format metadata, polygon) is not used and is
/// intentionally not surfaced here.
@immutable
class BarcodeItem {
  /// Direct constructor. Prefer [BarcodeItem.fromSupy] when wrapping a Supy
  /// detection — it keeps [source] consistent with [text].
  const BarcodeItem({required this.text, required this.source});

  /// Wraps a [SupyBarcode] detection in the Scanbot-shaped [BarcodeItem].
  factory BarcodeItem.fromSupy(SupyBarcode b) =>
      BarcodeItem(text: b.rawValue, source: b);

  /// Decoded payload (e.g. an EAN-13 or QR string).
  final String text;

  /// Underlying Supy barcode, kept for callers that want format/box access
  /// during the migration window.
  final SupyBarcode source;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BarcodeItem && other.text == text && other.source == source;

  @override
  int get hashCode => Object.hash(text, source);

  @override
  String toString() => 'BarcodeItem(text: $text)';
}
