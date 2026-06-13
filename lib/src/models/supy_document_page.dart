import 'package:meta/meta.dart';

/// One captured page of a scanned document.
@immutable
class SupyDocumentPage {
  /// Creates a document page result.
  const SupyDocumentPage({
    required this.uri,
    required this.width,
    required this.height,
  });

  /// Deserializes a page from a channel map.
  factory SupyDocumentPage.fromMap(Map<Object?, Object?> map) {
    return SupyDocumentPage(
      uri: map['uri']! as String,
      width: (map['width']! as num).toInt(),
      height: (map['height']! as num).toInt(),
    );
  }

  /// File URI of the persisted page image (JPEG). Format: `file:///...`.
  final String uri;

  /// Pixel width of the persisted image.
  final int width;

  /// Pixel height of the persisted image.
  final int height;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SupyDocumentPage &&
          other.uri == uri &&
          other.width == width &&
          other.height == height;

  @override
  int get hashCode => Object.hash(uri, width, height);

  @override
  String toString() =>
      'SupyDocumentPage(uri: $uri, ${width}x$height)';
}
