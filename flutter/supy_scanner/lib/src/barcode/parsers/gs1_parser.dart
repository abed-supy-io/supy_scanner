import '../../models/barcode/supy_barcode_document.dart';

/// Parses a GS1 element-string payload into a [SupyGs1Barcode].
///
/// Handles the FNC1 / AIM symbology-identifier prefix, fixed-length AIs from
/// [SupyGs1ApplicationIdentifier], and variable-length AIs terminated by the
/// GS group separator (ASCII 29). Unknown AIs are captured positionally into
/// [SupyGs1Barcode.rawUnknownAis] rather than dropped.
abstract final class Gs1Parser {
  // GS1 group separator (ASCII 29 / GS).
  static const String _gs = '\u001d';

  /// Known AI codes, longest-first so greedy matching prefers 3–4 digit AIs.
  static final List<SupyGs1ApplicationIdentifier> _knownByLengthDesc =
      SupyGs1ApplicationIdentifier.values.toList()
        ..sort((a, b) => b.code.length.compareTo(a.code.length));

  /// Returns a [SupyGs1Barcode] if [raw] looks like a GS1 element string, else
  /// `null`. A payload is considered GS1 when it begins with a GS1 AIM
  /// identifier (`]C1`, `]d2`, `]Q3`, `]e0`) or with a recognized AI code.
  static SupyGs1Barcode? tryParse(String raw) {
    final input = _stripAimIdentifier(raw);
    if (input.isEmpty) return null;

    final elements = <SupyGs1ApplicationIdentifier, String>{};
    final unknown = <String, String>{};
    var cursor = 0;
    var matchedAny = false;

    while (cursor < input.length) {
      // Skip stray separators.
      if (input[cursor] == _gs) {
        cursor++;
        continue;
      }

      final known = _matchKnownAi(input, cursor);
      if (known != null) {
        cursor += known.code.length;
        final value = _readValue(input, cursor, known.fixedLength);
        elements[known] = value.text;
        cursor = value.next;
        matchedAny = true;
        continue;
      }

      // Unknown AI: assume a 2-digit code and read to the next separator.
      if (!_isDigit(input, cursor) || cursor + 2 > input.length) {
        break;
      }
      final aiCode = input.substring(cursor, cursor + 2);
      cursor += 2;
      final value = _readValue(input, cursor, null);
      unknown[aiCode] = value.text;
      cursor = value.next;
    }

    if (!matchedAny && unknown.isEmpty) return null;
    return SupyGs1Barcode(elements: elements, rawUnknownAis: unknown);
  }

  static String _stripAimIdentifier(String raw) {
    // AIM identifiers: `]` + code letter + modifier digit. GS1 uses ]C1, ]e0,
    // ]d2, ]Q3, ]e0 depending on symbology.
    if (raw.length >= 3 && raw[0] == ']') {
      return raw.substring(3);
    }
    return raw;
  }

  static SupyGs1ApplicationIdentifier? _matchKnownAi(String input, int at) {
    for (final ai in _knownByLengthDesc) {
      if (at + ai.code.length <= input.length &&
          input.startsWith(ai.code, at)) {
        return ai;
      }
    }
    return null;
  }

  static ({String text, int next}) _readValue(
    String input,
    int start,
    int? fixedLength,
  ) {
    if (fixedLength != null) {
      final end = (start + fixedLength).clamp(0, input.length);
      var next = end;
      // Consume a trailing separator if the encoder emitted one.
      if (next < input.length && input[next] == _gs) next++;
      return (text: input.substring(start, end), next: next);
    }
    final end = input.indexOf(_gs, start);
    if (end < 0) {
      return (text: input.substring(start), next: input.length);
    }
    return (text: input.substring(start, end), next: end + 1);
  }

  static bool _isDigit(String s, int at) {
    final c = s.codeUnitAt(at);
    return c >= 0x30 && c <= 0x39;
  }
}
