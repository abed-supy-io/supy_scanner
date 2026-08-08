/// Visual filter applied to each captured document page on iOS.
///
/// Separate concept from [SupyDocumentEnhanceMode] (which controls the native
/// C++ enhance pipeline). The filter runs after the platform scanner returns
/// its capture and produces the Scanbot-shaped output style users expect:
///
/// - [color] — default; re-processes the page to preserve paper tone, flatten
///   illumination, and lift text contrast. The visible win vs the platform's
///   raw output (VisionKit bleaches paper to pure white; we hold it at ~96%).
/// - [grayscale] — same chain as [color] followed by desaturation.
/// - [blackAndWhite] — adaptive threshold for a crisp black-on-white scan.
/// - [original] — bypass the filter entirely (raw platform output).
///
/// iOS-only in v1; Android currently ignores this arg and produces the
/// existing native-core enhancement output. See `docs/ARCHITECTURE.md`.
enum SupyDocumentFilter {
  /// Paper-preserving color filter — the new default.
  color,

  /// Color chain followed by desaturation.
  grayscale,

  /// Adaptive-threshold binarization.
  blackAndWhite,

  /// Bypass the filter entirely.
  original;

  /// Wire-format value sent on the method channel.
  String get wireName => switch (this) {
    SupyDocumentFilter.color => 'color',
    SupyDocumentFilter.grayscale => 'grayscale',
    SupyDocumentFilter.blackAndWhite => 'blackAndWhite',
    SupyDocumentFilter.original => 'original',
  };
}
