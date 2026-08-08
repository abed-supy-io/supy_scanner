import 'dart:ui';

import 'package:meta/meta.dart';

import 'supy_barcode_format.dart';

/// A single decoded barcode reported by the scanner.
@immutable
class SupyBarcode {
  /// Creates a barcode result.
  const SupyBarcode({
    required this.rawValue,
    required this.format,
    this.boundingBox,
  });

  /// Deserializes a [SupyBarcode] from a channel detection map.
  factory SupyBarcode.fromMap(Map<Object?, Object?> map) {
    final box = map['boundingBox'];
    return SupyBarcode(
      rawValue: map['rawValue']! as String,
      format: SupyBarcodeFormat.fromWireName(map['format']! as String),
      boundingBox: box is Map<Object?, Object?> ? _rectFromMap(box) : null,
    );
  }

  /// The raw decoded payload (string content of the barcode).
  final String rawValue;

  /// The detected symbology.
  final SupyBarcodeFormat format;

  /// Optional bounding box in normalized [0..1] coordinates relative to the
  /// preview frame, with origin at top-left.
  ///
  /// `null` if the native platform did not report a bounding box for this
  /// detection.
  final Rect? boundingBox;

  static Rect _rectFromMap(Map<Object?, Object?> map) {
    return Rect.fromLTWH(
      (map['left']! as num).toDouble(),
      (map['top']! as num).toDouble(),
      (map['width']! as num).toDouble(),
      (map['height']! as num).toDouble(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SupyBarcode &&
          other.rawValue == rawValue &&
          other.format == format &&
          other.boundingBox == boundingBox;

  @override
  int get hashCode => Object.hash(rawValue, format, boundingBox);

  @override
  String toString() =>
      'SupyBarcode(format: ${format.name}, rawValue: $rawValue, '
      'boundingBox: $boundingBox)';
}
