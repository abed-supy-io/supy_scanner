import 'dart:ui';

import '../models/datacapture/supy_text_pattern.dart';
import '../models/datacapture/supy_text_pattern_match.dart';
import '../models/ocr/supy_recognized_text.dart';

/// Runs [SupyTextPattern]s over an OCR result, on-device and pure-Dart.
///
/// This is the matcher half of the live text-pattern scanner: the native side
/// ships a `SupyRecognizedText` tree per frame and this class applies the
/// caller's patterns to it, emitting a [SupyTextPatternMatch] per hit. Each
/// pattern is compiled once per [match] call.
abstract final class SupyTextPatternMatcher {
  /// Matches every pattern in [patterns] against [text] according to each
  /// pattern's [SupyTextPattern.scope]. Results are returned in
  /// pattern-then-reading order and the list is unmodifiable.
  static List<SupyTextPatternMatch> match(
    SupyRecognizedText text,
    List<SupyTextPattern> patterns,
  ) {
    final results = <SupyTextPatternMatch>[];
    for (final pattern in patterns) {
      final regExp = pattern.regExp;
      switch (pattern.scope) {
        case SupyTextPatternScope.fullText:
          _collect(regExp, pattern.name, text.fullText, null, results);
        case SupyTextPatternScope.block:
          for (final block in text.blocks) {
            _collect(
              regExp,
              pattern.name,
              block.text,
              block.boundingBox,
              results,
            );
          }
        case SupyTextPatternScope.line:
          for (final block in text.blocks) {
            for (final line in block.lines) {
              _collect(
                regExp,
                pattern.name,
                line.text,
                line.boundingBox,
                results,
              );
            }
          }
      }
    }
    return List<SupyTextPatternMatch>.unmodifiable(results);
  }

  static void _collect(
    RegExp regExp,
    String name,
    String source,
    Rect? box,
    List<SupyTextPatternMatch> out,
  ) {
    for (final m in regExp.allMatches(source)) {
      out.add(
        SupyTextPatternMatch(
          patternName: name,
          value: m.group(0) ?? '',
          groups: List<String?>.unmodifiable(
            List<String?>.generate(m.groupCount, (i) => m.group(i + 1)),
          ),
          boundingBox: box,
        ),
      );
    }
  }
}
