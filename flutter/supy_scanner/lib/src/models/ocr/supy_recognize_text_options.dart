import 'package:meta/meta.dart';

/// Options for a standalone [SupyScannerChannel.recognizeText] pass.
@immutable
class SupyRecognizeTextOptions {
  /// Creates OCR options for the image at [imagePath].
  const SupyRecognizeTextOptions({
    required this.imagePath,
    this.languages = const <String>[],
    this.includeElements = true,
  });

  /// Absolute path to the image file to recognize.
  final String imagePath;

  /// Preferred recognition languages as BCP-47 tags (e.g. `['en', 'ar']`).
  ///
  /// A hint only: iOS Vision honors it directly; Android ML Kit's Latin
  /// recognizer ignores it (Latin scripts only — see `docs/MIGRATION.md`).
  /// Empty means "let the engine decide".
  final List<String> languages;

  /// Whether to populate per-word [SupyTextElement]s. `false` skips element
  /// segmentation for a faster pass when only line/block geometry is needed.
  final bool includeElements;

  /// Encodes to the channel argument map.
  Map<String, Object?> toWire() => <String, Object?>{
    'imagePath': imagePath,
    'languages': languages,
    'includeElements': includeElements,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SupyRecognizeTextOptions &&
          other.imagePath == imagePath &&
          other.includeElements == includeElements &&
          _listEquals(other.languages, languages);

  @override
  int get hashCode =>
      Object.hash(imagePath, includeElements, Object.hashAll(languages));

  @override
  String toString() =>
      'SupyRecognizeTextOptions(imagePath: $imagePath, '
      'languages: $languages, includeElements: $includeElements)';
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
