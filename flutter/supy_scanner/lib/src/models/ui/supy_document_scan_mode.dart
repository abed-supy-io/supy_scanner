/// Capture modes offered by the branded document scanner viewfinder, shown as
/// the Single / Multi / Receipt segmented tabs.
///
/// The mode governs only capture-flow behavior and detection tuning; it does
/// not change what the scanner returns. Every mode yields the same
/// `List<SupyDocumentPage>` of captured page images, preserving drop-in
/// Scanbot compatibility.
enum SupyDocumentScanMode {
  /// Capture a single page, then go straight to review.
  single,

  /// Accumulate many pages, staying in the viewfinder between captures until
  /// the user finishes.
  multi,

  /// Receipt-tuned single capture: a tall viewfinder frame optimized for
  /// receipts. Otherwise behaves like [single].
  receipt;

  /// Whether this mode finishes after one page (Single / Receipt) rather than
  /// accumulating pages (Multi).
  bool get isSinglePage =>
      this == SupyDocumentScanMode.single ||
      this == SupyDocumentScanMode.receipt;

  /// Whether this mode uses the tall, receipt-optimized viewfinder frame.
  bool get isReceipt => this == SupyDocumentScanMode.receipt;
}
