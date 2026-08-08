import 'package:meta/meta.dart';

/// Which OCR granularity a [SupyTextPattern] is matched against.
///
/// [line] is the default: matching per recognized line yields a tight bounding
/// box per match and is the natural granularity for a live scanner. [block]
/// matches whole paragraph-like regions; [fullText] matches the concatenated
/// document text and therefore carries no bounding box.
enum SupyTextPatternScope {
  /// Match each recognized line independently (default). Yields a per-line box.
  line,

  /// Match each paragraph-like block. Yields a per-block box.
  block,

  /// Match the concatenated document text. Carries no bounding box.
  fullText,
}

/// A named regular-expression pattern to detect in a live OCR stream.
///
/// This is Scanbot's "generic document / text-pattern" concept as a pure-Dart
/// value type: the native side ships recognized-text geometry per frame and
/// [SupyTextPatternMatcher] runs these patterns over it on-device. The regex
/// [pattern] is a source string (not a `RegExp`) so the type stays a frozen,
/// comparable value; [regExp] compiles it on demand.
@immutable
class SupyTextPattern {
  /// Creates a text pattern. [name] labels every [SupyTextPatternMatch] this
  /// pattern produces; [pattern] is a Dart regular-expression source string.
  const SupyTextPattern({
    required this.name,
    required this.pattern,
    this.caseSensitive = true,
    this.scope = SupyTextPatternScope.line,
  });

  /// A basic email-address pattern.
  factory SupyTextPattern.email({
    String name = 'email',
    SupyTextPatternScope scope = SupyTextPatternScope.line,
  }) => SupyTextPattern(
    name: name,
    pattern: r'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}',
    caseSensitive: false,
    scope: scope,
  );

  /// An http/https URL pattern.
  factory SupyTextPattern.url({
    String name = 'url',
    SupyTextPatternScope scope = SupyTextPatternScope.line,
  }) => SupyTextPattern(
    name: name,
    pattern: r'https?://[^\s]+',
    caseSensitive: false,
    scope: scope,
  );

  /// A caller-supplied identifier that tags produced matches.
  final String name;

  /// The regular-expression source string.
  final String pattern;

  /// Whether matching is case-sensitive. Defaults to `true` (RegExp default).
  final bool caseSensitive;

  /// Which OCR granularity to match against. Defaults to [SupyTextPatternScope.line].
  final SupyTextPatternScope scope;

  /// Compiles [pattern] into a [RegExp]. Throws [FormatException] if the source
  /// is not a valid pattern — a programming error surfaced at match time.
  RegExp get regExp => RegExp(pattern, caseSensitive: caseSensitive);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SupyTextPattern &&
          other.name == name &&
          other.pattern == pattern &&
          other.caseSensitive == caseSensitive &&
          other.scope == scope;

  @override
  int get hashCode => Object.hash(name, pattern, caseSensitive, scope);

  @override
  String toString() =>
      'SupyTextPattern($name, /$pattern/${caseSensitive ? '' : 'i'}, '
      '${scope.name})';
}
