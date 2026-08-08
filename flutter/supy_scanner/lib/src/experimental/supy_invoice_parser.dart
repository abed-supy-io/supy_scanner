/// Phase IXP — Invoice eXtraction Prototype.
///
/// EXPERIMENTAL: this API is unstable and intentionally NOT exported from
/// `package:supy_scanner/supy_scanner.dart`. Consumers must import via the
/// internal path. Promotion to the public surface is gated on a labeled
/// invoice corpus (see `docs/PLAN.md` § Phase IXP).
library;

import 'package:flutter/services.dart';
import 'package:meta/meta.dart';

/// Channel name is shared with the rest of the plugin — `parseInvoice` is an
/// additive v1 method, not a v2 surface.
const MethodChannel _kChannel = MethodChannel('io.supy.scanner/v1');

/// Result of a single invoice parse. Fields are nullable because the parser
/// is heuristic — any field can be absent. `rawText` is always populated for
/// lab verification.
@experimental
@immutable
class SupyInvoiceData {
  /// Creates an invoice data value.
  const SupyInvoiceData({
    this.vendor,
    this.date,
    this.invoiceNumber,
    this.currency,
    this.total,
    this.tax,
    this.lineItems = const <SupyInvoiceLineItem>[],
    this.rawText = '',
  });

  /// Vendor / merchant name guess.
  final String? vendor;

  /// Invoice date as printed (not normalized).
  final String? date;

  /// Invoice number / reference.
  final String? invoiceNumber;

  /// ISO 4217 currency code (`USD`, `EUR`, ...). May be derived from a symbol.
  final String? currency;

  /// Total amount due.
  final double? total;

  /// Tax / VAT amount.
  final double? tax;

  /// Detected line items in printed order.
  final List<SupyInvoiceLineItem> lineItems;

  /// Full OCR text concatenated top-to-bottom for verification.
  final String rawText;

  /// Builds a [SupyInvoiceData] from a native-side wire map. Returns an
  /// empty value if [map] is null.
  static SupyInvoiceData fromWire(Map<Object?, Object?>? map) {
    if (map == null) return const SupyInvoiceData();
    final items = (map['lineItems'] as List<Object?>?) ?? const <Object?>[];
    return SupyInvoiceData(
      vendor: map['vendor'] as String?,
      date: map['date'] as String?,
      invoiceNumber: map['invoiceNumber'] as String?,
      currency: map['currency'] as String?,
      total: (map['total'] as num?)?.toDouble(),
      tax: (map['tax'] as num?)?.toDouble(),
      lineItems: items
          .whereType<Map<Object?, Object?>>()
          .map(SupyInvoiceLineItem.fromWire)
          .toList(growable: false),
      rawText: (map['rawText'] as String?) ?? '',
    );
  }
}

/// A single parsed invoice line.
@experimental
@immutable
class SupyInvoiceLineItem {
  /// Creates a line item.
  const SupyInvoiceLineItem({
    required this.description,
    required this.amount,
    this.quantity,
  });

  /// Printed description (item name, SKU, free-text).
  final String description;

  /// Line amount (typically total for the line, not unit price).
  final double amount;

  /// Quantity, if a small integer column was detected to the left of the
  /// amount.
  final int? quantity;

  /// Builds a line item from a wire map.
  static SupyInvoiceLineItem fromWire(Map<Object?, Object?> map) =>
      SupyInvoiceLineItem(
        description: (map['description'] as String?) ?? '',
        amount: (map['amount'] as num?)?.toDouble() ?? 0,
        quantity: (map['quantity'] as num?)?.toInt(),
      );
}

/// Indicates the current platform does not support invoice parsing. v1.2
/// only ships iOS — Android throws this so the lab UI can surface a friendly
/// message instead of an opaque platform error.
@experimental
class SupyInvoiceParserUnsupportedError implements Exception {
  /// Creates an unsupported-platform error.
  const SupyInvoiceParserUnsupportedError(this.message);

  /// Human-readable reason.
  final String message;

  @override
  String toString() => 'SupyInvoiceParserUnsupportedError: $message';
}

/// Experimental entry point. Pass the file path of an already-captured page
/// (e.g. one of the URIs returned by `scanDocument`).
@experimental
class SupyInvoiceParser {
  /// Creates a parser bound to the shared scanner MethodChannel. Tests can
  /// inject a mock channel.
  SupyInvoiceParser({MethodChannel? channel}) : _channel = channel ?? _kChannel;

  final MethodChannel _channel;

  /// Parses the invoice page at [imagePath]. Throws
  /// [SupyInvoiceParserUnsupportedError] when the platform handler returns
  /// `unimplemented` (currently Android in v1.2).
  Future<SupyInvoiceData> parse(String imagePath) async {
    try {
      final raw = await _channel.invokeMapMethod<Object?, Object?>(
        'parseInvoice',
        <String, Object?>{'imagePath': imagePath},
      );
      return SupyInvoiceData.fromWire(raw);
    } on PlatformException catch (e) {
      if (e.code == 'unimplemented') {
        throw SupyInvoiceParserUnsupportedError(
          e.message ?? 'parseInvoice is not implemented on this platform',
        );
      }
      rethrow;
    }
  }
}
