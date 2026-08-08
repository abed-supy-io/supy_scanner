import '../../models/ocr/supy_mrz_document.dart';
import '../../models/ocr/supy_recognized_text.dart';

/// Parses ICAO 9303 Machine Readable Zones out of recognized text.
///
/// The MRZ character set is `A–Z`, `0–9`, and the filler `<`. This is a
/// pure-Dart, on-device pass over the [SupyRecognizedText] produced by the
/// `recognizeText` channel method (or over any raw text via [parse]); it does
/// no I/O and never mutates its input. MRZ uses the OCR-B font, which is Latin
/// script, so it works on both iOS Vision and Android ML Kit.
abstract final class SupyMrzParser {
  /// Number of characters an OCR-read line may be off from the exact format
  /// width before we stop trying to fit it (padded with filler / trimmed).
  static const int _lengthTolerance = 2;

  /// Attempts to parse an MRZ from [text]. Lines are normalized to the MRZ
  /// alphabet, then matched against the TD3 (2×44), TD2 (2×36), and TD1 (3×30)
  /// layouts, most-specific width first. Returns `null` when no run of lines
  /// forms a recognizable zone.
  static SupyMrzDocument? parse(String text) {
    final candidates = _candidateLines(text);
    if (candidates.isEmpty) return null;

    // TD3 / TD2 need two adjacent equal-width lines; TD1 needs three.
    for (var i = 0; i + 1 < candidates.length; i++) {
      final a = candidates[i];
      final b = candidates[i + 1];
      final td3 = _fit(a, 44) != null && _fit(b, 44) != null;
      if (td3) {
        final doc = _parseTd3(_fit(a, 44)!, _fit(b, 44)!);
        if (doc != null) return doc;
      }
      final td2 = _fit(a, 36) != null && _fit(b, 36) != null;
      if (td2) {
        final doc = _parseTd2(_fit(a, 36)!, _fit(b, 36)!);
        if (doc != null) return doc;
      }
    }
    for (var i = 0; i + 2 < candidates.length; i++) {
      final a = _fit(candidates[i], 30);
      final b = _fit(candidates[i + 1], 30);
      final c = _fit(candidates[i + 2], 30);
      if (a != null && b != null && c != null) {
        final doc = _parseTd1(a, b, c);
        if (doc != null) return doc;
      }
    }
    return null;
  }

  /// Normalizes each source line to the MRZ alphabet and keeps only those that
  /// plausibly belong to a machine-readable zone (right length band, contains
  /// filler). Order is preserved so adjacency checks stay meaningful.
  static List<String> _candidateLines(String text) {
    final out = <String>[];
    for (final raw in text.split(RegExp(r'[\r\n]+'))) {
      final normalized = raw.toUpperCase().replaceAll(RegExp('[^A-Z0-9<]'), '');
      if (normalized.length < 28) continue;
      if (!normalized.contains('<')) continue;
      out.add(normalized);
    }
    return out;
  }

  /// Returns [line] fitted to [target] length — unchanged when exact, padded
  /// with filler when short, or trimmed when long, but only within
  /// [_lengthTolerance]. Returns `null` when the line is too far off to be
  /// that format.
  static String? _fit(String line, int target) {
    final diff = line.length - target;
    if (diff == 0) return line;
    if (diff.abs() > _lengthTolerance) return null;
    if (diff < 0) return line.padRight(target, '<');
    return line.substring(0, target);
  }

  static SupyMrzDocument? _parseTd3(String l1, String l2) {
    final (surname, given) = _parseName(l1.substring(5, 44));
    final docNumber = l2.substring(0, 9);
    final composite =
        l2.substring(0, 10) + l2.substring(13, 20) + l2.substring(21, 43);
    final personalNumber = l2.substring(28, 42);
    return SupyMrzDocument(
      format: SupyMrzFormat.td3,
      documentType: _clean(l1.substring(0, 2)),
      issuingCountry: _clean(l1.substring(2, 5)),
      surname: surname,
      givenNames: given,
      documentNumber: _clean(docNumber),
      nationality: _clean(l2.substring(10, 13)),
      dateOfBirth: l2.substring(13, 19),
      sex: _parseSex(l2[20]),
      expiryDate: l2.substring(21, 27),
      optionalData: _optional(personalNumber),
      documentNumberValid: _verify(docNumber, l2[9]),
      dateOfBirthValid: _verify(l2.substring(13, 19), l2[19]),
      expiryDateValid: _verify(l2.substring(21, 27), l2[27]),
      optionalDataValid: _verify(personalNumber, l2[42]),
      compositeValid: _verify(composite, l2[43]),
      lines: [l1, l2],
    );
  }

  static SupyMrzDocument? _parseTd2(String l1, String l2) {
    final (surname, given) = _parseName(l1.substring(5, 36));
    final docNumber = l2.substring(0, 9);
    final composite =
        l2.substring(0, 10) + l2.substring(13, 20) + l2.substring(21, 35);
    return SupyMrzDocument(
      format: SupyMrzFormat.td2,
      documentType: _clean(l1.substring(0, 2)),
      issuingCountry: _clean(l1.substring(2, 5)),
      surname: surname,
      givenNames: given,
      documentNumber: _clean(docNumber),
      nationality: _clean(l2.substring(10, 13)),
      dateOfBirth: l2.substring(13, 19),
      sex: _parseSex(l2[20]),
      expiryDate: l2.substring(21, 27),
      optionalData: _optional(l2.substring(28, 35)),
      documentNumberValid: _verify(docNumber, l2[9]),
      dateOfBirthValid: _verify(l2.substring(13, 19), l2[19]),
      expiryDateValid: _verify(l2.substring(21, 27), l2[27]),
      compositeValid: _verify(composite, l2[35]),
      lines: [l1, l2],
    );
  }

  static SupyMrzDocument? _parseTd1(String l1, String l2, String l3) {
    final (surname, given) = _parseName(l3);
    final docNumber = l1.substring(5, 14);
    final optional1 = l1.substring(15, 30);
    final optional2 = l2.substring(18, 29);
    final composite =
        l1.substring(5, 30) +
        l2.substring(0, 7) +
        l2.substring(8, 15) +
        l2.substring(18, 29);
    return SupyMrzDocument(
      format: SupyMrzFormat.td1,
      documentType: _clean(l1.substring(0, 2)),
      issuingCountry: _clean(l1.substring(2, 5)),
      surname: surname,
      givenNames: given,
      documentNumber: _clean(docNumber),
      nationality: _clean(l2.substring(15, 18)),
      dateOfBirth: l2.substring(0, 6),
      sex: _parseSex(l2[7]),
      expiryDate: l2.substring(8, 14),
      optionalData: _optional(optional1),
      optionalData2: _optional(optional2),
      documentNumberValid: _verify(docNumber, l1[14]),
      dateOfBirthValid: _verify(l2.substring(0, 6), l2[6]),
      expiryDateValid: _verify(l2.substring(8, 14), l2[14]),
      compositeValid: _verify(composite, l2[29]),
      lines: [l1, l2, l3],
    );
  }

  // --- ICAO 9303 check-digit machinery -------------------------------------

  /// Numeric value of an MRZ character: `0–9` → 0–9, `A–Z` → 10–35, filler
  /// `<` → 0. Returns `-1` for anything else so a stray character fails the
  /// check rather than silently scoring zero.
  static int _charValue(String c) {
    final code = c.codeUnitAt(0);
    if (c == '<') return 0;
    if (code >= 0x30 && code <= 0x39) return code - 0x30;
    if (code >= 0x41 && code <= 0x5A) return code - 0x41 + 10;
    return -1;
  }

  /// Computes the ICAO check digit over [field] using the 7-3-1 weight cycle.
  /// Returns `-1` if the field contains a character outside the MRZ alphabet.
  static int _checkDigit(String field) {
    const weights = [7, 3, 1];
    var sum = 0;
    for (var i = 0; i < field.length; i++) {
      final v = _charValue(field[i]);
      if (v < 0) return -1;
      sum += v * weights[i % 3];
    }
    return sum % 10;
  }

  /// Verifies that [check] is the correct check digit for [field]. A filler
  /// `<` in the check position is treated as `0` (ICAO's convention for an
  /// all-filler field).
  static bool _verify(String field, String check) {
    final expected = _checkDigit(field);
    if (expected < 0) return false;
    final actual = check == '<' ? 0 : int.tryParse(check);
    if (actual == null) return false;
    return expected == actual;
  }

  // --- field decoding ------------------------------------------------------

  static SupyMrzSex _parseSex(String c) {
    switch (c.toUpperCase()) {
      case 'M':
        return SupyMrzSex.male;
      case 'F':
        return SupyMrzSex.female;
      default:
        return SupyMrzSex.unspecified;
    }
  }

  /// Splits an MRZ name field into (surname, given names). Primary and
  /// secondary identifiers are separated by `<<`; single `<` acts as a space.
  static (String, String) _parseName(String field) {
    final parts = field.split('<<');
    final surname = _cleanName(parts.isNotEmpty ? parts.first : '');
    final given = _cleanName(
      parts.length > 1 ? parts.sublist(1).join(' ') : '',
    );
    return (surname, given);
  }

  static String _cleanName(String s) =>
      s.replaceAll('<', ' ').trim().replaceAll(RegExp(r'\s+'), ' ');

  /// Strips filler from a code field (country, nationality, document number).
  static String _clean(String s) => s.replaceAll('<', '').trim();

  /// Returns the decoded optional field, or `null` when it is pure filler.
  static String? _optional(String s) {
    final v = _clean(s);
    return v.isEmpty ? null : v;
  }
}

/// Adds opt-in MRZ parsing to a [SupyRecognizedText] result.
extension SupyRecognizeMrz on SupyRecognizedText {
  /// Interprets the recognized text as an ICAO 9303 MRZ, or returns `null` if
  /// no machine-readable zone is present. Pure-Dart, on-device, non-mutating.
  SupyMrzDocument? parseMrz() => SupyMrzParser.parse(fullText);
}
