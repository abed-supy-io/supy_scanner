import 'dart:ui';

import 'package:meta/meta.dart';

/// Result of a standalone OCR pass over a single image.
///
/// Mirrors the block → line → element tree that both native OCR engines
/// (iOS Vision, Android ML Kit) expose. All bounding boxes are normalized
/// `[0..1]` coordinates relative to the source image, with origin at the
/// top-left — the same convention as [SupyBarcode.boundingBox].
@immutable
class SupyRecognizedText {
  /// Creates a recognized-text tree.
  const SupyRecognizedText({required this.fullText, required this.blocks});

  /// Decodes the wire map produced by the native `recognizeText` handler.
  factory SupyRecognizedText.fromMap(Map<Object?, Object?> map) {
    final blocks = map['blocks'];
    return SupyRecognizedText(
      fullText: (map['fullText'] as String?) ?? '',
      blocks:
          blocks is List
              ? List<SupyTextBlock>.unmodifiable(
                blocks.whereType<Map<Object?, Object?>>().map(
                  SupyTextBlock.fromMap,
                ),
              )
              : const <SupyTextBlock>[],
    );
  }

  /// The full recognized text, blocks joined by newlines. Convenience for
  /// callers that don't need geometry.
  final String fullText;

  /// Top-level text blocks (paragraph-like regions) in reading order.
  final List<SupyTextBlock> blocks;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SupyRecognizedText &&
          other.fullText == fullText &&
          _listEquals(other.blocks, blocks);

  @override
  int get hashCode => Object.hash(fullText, Object.hashAll(blocks));

  @override
  String toString() =>
      'SupyRecognizedText(blocks: ${blocks.length}, '
      'chars: ${fullText.length})';
}

/// A paragraph-like region of recognized text.
@immutable
class SupyTextBlock {
  /// Creates a text block.
  const SupyTextBlock({
    required this.text,
    required this.boundingBox,
    required this.lines,
  });

  /// Decodes a block wire map.
  factory SupyTextBlock.fromMap(Map<Object?, Object?> map) {
    final lines = map['lines'];
    return SupyTextBlock(
      text: (map['text'] as String?) ?? '',
      boundingBox: _rectFromMap(map['boundingBox']),
      lines:
          lines is List
              ? List<SupyTextLine>.unmodifiable(
                lines.whereType<Map<Object?, Object?>>().map(
                  SupyTextLine.fromMap,
                ),
              )
              : const <SupyTextLine>[],
    );
  }

  /// The block's recognized text.
  final String text;

  /// Normalized `[0..1]` bounding box, top-left origin.
  final Rect boundingBox;

  /// Lines within this block, in reading order.
  final List<SupyTextLine> lines;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SupyTextBlock &&
          other.text == text &&
          other.boundingBox == boundingBox &&
          _listEquals(other.lines, lines);

  @override
  int get hashCode => Object.hash(text, boundingBox, Object.hashAll(lines));

  @override
  String toString() => 'SupyTextBlock("$text", lines: ${lines.length})';
}

/// A single line of recognized text.
@immutable
class SupyTextLine {
  /// Creates a text line.
  const SupyTextLine({
    required this.text,
    required this.boundingBox,
    required this.elements,
  });

  /// Decodes a line wire map.
  factory SupyTextLine.fromMap(Map<Object?, Object?> map) {
    final elements = map['elements'];
    return SupyTextLine(
      text: (map['text'] as String?) ?? '',
      boundingBox: _rectFromMap(map['boundingBox']),
      elements:
          elements is List
              ? List<SupyTextElement>.unmodifiable(
                elements.whereType<Map<Object?, Object?>>().map(
                  SupyTextElement.fromMap,
                ),
              )
              : const <SupyTextElement>[],
    );
  }

  /// The line's recognized text.
  final String text;

  /// Normalized `[0..1]` bounding box, top-left origin.
  final Rect boundingBox;

  /// Words / symbols within this line. Empty when `includeElements` was
  /// `false` on the request (or when the engine cannot segment the line —
  /// iOS Vision does not always return per-word boxes).
  final List<SupyTextElement> elements;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SupyTextLine &&
          other.text == text &&
          other.boundingBox == boundingBox &&
          _listEquals(other.elements, elements);

  @override
  int get hashCode => Object.hash(text, boundingBox, Object.hashAll(elements));

  @override
  String toString() => 'SupyTextLine("$text", elements: ${elements.length})';
}

/// A single word or symbol within a line.
@immutable
class SupyTextElement {
  /// Creates a text element.
  const SupyTextElement({required this.text, required this.boundingBox});

  /// Decodes an element wire map.
  factory SupyTextElement.fromMap(Map<Object?, Object?> map) => SupyTextElement(
    text: (map['text'] as String?) ?? '',
    boundingBox: _rectFromMap(map['boundingBox']),
  );

  /// The element's recognized text.
  final String text;

  /// Normalized `[0..1]` bounding box, top-left origin.
  final Rect boundingBox;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SupyTextElement &&
          other.text == text &&
          other.boundingBox == boundingBox;

  @override
  int get hashCode => Object.hash(text, boundingBox);

  @override
  String toString() => 'SupyTextElement("$text")';
}

/// Shared box decoder: `{left, top, width, height}` → [Rect]. A missing or
/// malformed box decodes to [Rect.zero] so a partial native payload never
/// throws mid-parse.
Rect _rectFromMap(Object? raw) {
  if (raw is! Map) return Rect.zero;
  final left = raw['left'];
  final top = raw['top'];
  final width = raw['width'];
  final height = raw['height'];
  if (left is! num || top is! num || width is! num || height is! num) {
    return Rect.zero;
  }
  return Rect.fromLTWH(
    left.toDouble(),
    top.toDouble(),
    width.toDouble(),
    height.toDouble(),
  );
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
