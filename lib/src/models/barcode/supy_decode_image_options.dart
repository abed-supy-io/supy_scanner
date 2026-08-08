import 'package:meta/meta.dart';

import '../supy_barcode_format.dart';

/// Options for a one-shot still-image barcode decode
/// ([SupyScannerChannel.decodeImage]).
///
/// Unlike the live [SupyBarcodeScannerView], this runs the detector over a
/// single image file already on disk and returns every barcode found — no
/// camera, no preview. It is the deterministic entry point used by the
/// benchmark harness so a fixed set of fixture images can be decoded
/// identically across runs.
@immutable
class SupyDecodeImageOptions {
  /// Creates decode options for the image at [imagePath].
  const SupyDecodeImageOptions({
    required this.imagePath,
    this.formats = const [SupyBarcodeFormat.all],
    this.useNativeCore = false,
  });

  /// Absolute path (or `file://` / `content://` URI) to the image to decode.
  final String imagePath;

  /// Symbologies to look for. Defaults to [SupyBarcodeFormat.all].
  ///
  /// The five native-core-only formats (`dataBar`, `dataBarExpanded`,
  /// `microQr`, `rMQR`, `maxiCode`) decode only when [useNativeCore] is `true`
  /// — see `docs/MIGRATION.md`.
  final List<SupyBarcodeFormat> formats;

  /// When `true`, decode with the bundled zxing-cpp core instead of the
  /// platform default (ML Kit on Android, Vision on iOS). The native core
  /// covers the full 18-format set and applies `tryHarder`; the platform
  /// decoders cover only the 13 core formats. Falls back to the platform
  /// decoder if the native core is not linked into the build.
  final bool useNativeCore;

  /// Encodes to the channel argument map.
  Map<String, Object?> toWire() => <String, Object?>{
    'imagePath': imagePath,
    'formats': formats.map((f) => f.wireName).toList(),
    'useNativeCore': useNativeCore,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SupyDecodeImageOptions &&
          other.imagePath == imagePath &&
          other.useNativeCore == useNativeCore &&
          _listEquals(other.formats, formats);

  @override
  int get hashCode =>
      Object.hash(imagePath, useNativeCore, Object.hashAll(formats));

  @override
  String toString() =>
      'SupyDecodeImageOptions(imagePath: $imagePath, '
      'formats: $formats, useNativeCore: $useNativeCore)';
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
