import '../../models/barcode/supy_barcode_document.dart';

/// Parses an IATA BCBP ("M1") boarding-pass payload into a
/// [SupyBoardingPassBarcode].
///
/// Reads the mandatory header (format code, leg count, passenger name) and the
/// first flight leg's mandatory fixed-width fields. Later legs and the
/// conditional/airline variable sections are intentionally not surfaced.
abstract final class BcbpParser {
  /// Returns a [SupyBoardingPassBarcode] if [raw] is a BCBP payload, else
  /// `null`. Requires the `M` format code and at least the header plus one
  /// full mandatory leg.
  static SupyBoardingPassBarcode? tryParse(String raw) {
    // Header is 23 chars; leg-1 mandatory block runs to index 60.
    if (raw.length < 60 || raw[0] != 'M') return null;

    final legCount = int.tryParse(raw[1]);
    if (legCount == null || legCount < 1) return null;

    final name = raw.substring(2, 22).trim();
    if (name.isEmpty) return null;

    String? field(int start, int end) {
      if (end > raw.length) return null;
      final v = raw.substring(start, end).trim();
      return v.isEmpty ? null : v;
    }

    final julian = field(44, 47);
    return SupyBoardingPassBarcode(
      passengerName: name,
      legCount: legCount,
      pnr: field(23, 30),
      from: field(30, 33),
      to: field(33, 36),
      operatingCarrier: field(36, 39),
      flightNumber: field(39, 44),
      julianFlightDate: julian == null ? null : int.tryParse(julian),
      cabin: field(47, 48),
      seat: field(48, 52),
      sequenceNumber: field(52, 57),
    );
  }
}
