import 'package:meta/meta.dart';

import 'supy_barcode.dart';

/// Outcome of a completed batch barcode session.
@immutable
class SupyBatchBarcodeResult {
  /// Creates a batch barcode result.
  const SupyBatchBarcodeResult({
    required this.items,
    required this.duplicateCount,
  });

  /// Deserializes from a channel result map.
  factory SupyBatchBarcodeResult.fromMap(Map<Object?, Object?> map) {
    final rawItems = (map['items'] as List<Object?>?) ?? const <Object?>[];
    final parsed = rawItems
        .whereType<Map<Object?, Object?>>()
        .map(SupyBarcode.fromMap)
        .toList(growable: false);
    return SupyBatchBarcodeResult(
      items: parsed,
      duplicateCount: (map['duplicateCount'] as num?)?.toInt() ?? 0,
    );
  }

  /// Unique barcodes accumulated during the session, in scan order.
  final List<SupyBarcode> items;

  /// Number of repeated detections that were suppressed by the dedupe rule.
  /// Exposed so consumers can show a "X duplicates ignored" hint if they wish.
  final int duplicateCount;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SupyBatchBarcodeResult &&
          other.duplicateCount == duplicateCount &&
          _listEquals(other.items, items);

  @override
  int get hashCode => Object.hash(Object.hashAll(items), duplicateCount);

  @override
  String toString() =>
      'SupyBatchBarcodeResult(items: ${items.length}, '
      'duplicateCount: $duplicateCount)';

  static bool _listEquals(List<SupyBarcode> a, List<SupyBarcode> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
