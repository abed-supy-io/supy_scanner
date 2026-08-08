import 'dart:ui';

import 'package:meta/meta.dart';

/// A single hit produced by [SupyTextPatternMatcher] for a [SupyTextPattern].
///
/// [value] is the whole match (regex group 0); [groups] holds the capture
/// groups `1..n` (a group that did not participate is `null`). [boundingBox]
/// is the normalized `[0..1]`, top-left-origin box of the line or block the
/// match came from — `null` when the pattern's scope was `fullText`, which has
/// no geometry. It matches the box convention of `SupyRecognizedText`.
@immutable
class SupyTextPatternMatch {
  /// Creates a pattern match.
  const SupyTextPatternMatch({
    required this.patternName,
    required this.value,
    this.groups = const <String?>[],
    this.boundingBox,
  });

  /// The [SupyTextPattern.name] that produced this match.
  final String patternName;

  /// The full matched substring (regex group 0).
  final String value;

  /// Capture groups `1..n`; a non-participating group is `null`.
  final List<String?> groups;

  /// Normalized `[0..1]` box of the source line/block, or `null` for
  /// `fullText` scope.
  final Rect? boundingBox;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SupyTextPatternMatch &&
          other.patternName == patternName &&
          other.value == value &&
          other.boundingBox == boundingBox &&
          _listEquals(other.groups, groups);

  @override
  int get hashCode =>
      Object.hash(patternName, value, boundingBox, Object.hashAll(groups));

  @override
  String toString() =>
      'SupyTextPatternMatch($patternName: "$value", '
      'groups: ${groups.length})';
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
