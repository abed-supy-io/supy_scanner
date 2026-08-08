import '../../models/barcode/supy_barcode_document.dart';

/// Parses an AAMVA driver's-license / ID PDF417 payload into a
/// [SupyDriverLicenseBarcode].
///
/// AAMVA data elements are 3-letter codes followed by their value and
/// terminated by a line feed (`\n`); the whole subfile is terminated by a
/// carriage return. This reads every `^[A-Z]{3}` element regardless of
/// subfile, which is robust across the DL/ID subfile layouts.
abstract final class AamvaParser {
  static const String _lf = '\n';

  /// Returns a [SupyDriverLicenseBarcode] if [raw] is an AAMVA payload, else
  /// `null`. Requires the `@` compliance indicator and the `ANSI ` header.
  static SupyDriverLicenseBarcode? tryParse(String raw) {
    if (raw.isEmpty || raw[0] != '@') return null;
    final ansi = raw.indexOf('ANSI ');
    if (ansi < 0) return null;

    // Header after 'ANSI ': 6-digit IIN, then 2-digit AAMVA version.
    int? version;
    final versionStart = ansi + 'ANSI '.length + 6;
    if (versionStart + 2 <= raw.length) {
      version = int.tryParse(raw.substring(versionStart, versionStart + 2));
    }

    final fields = <String, String>{};
    for (final segment in raw.split(_lf)) {
      final line = segment.replaceAll('\r', '').trimRight();
      if (line.length < 3) continue;
      final id = line.substring(0, 3);
      if (!_isElementId(id)) continue;
      fields[id] = line.substring(3).trim();
    }

    if (fields.isEmpty) return null;
    return SupyDriverLicenseBarcode(fields: fields, aamvaVersion: version);
  }

  static bool _isElementId(String id) {
    for (var i = 0; i < 3; i++) {
      final c = id.codeUnitAt(i);
      if (c < 0x41 || c > 0x5A) return false; // A–Z
    }
    return true;
  }
}
