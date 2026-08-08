import 'package:flutter/widgets.dart';

import '../models/supy_barcode.dart';
import '../models/ui/supy_ar_overlay_configuration.dart';
import '../models/ui/supy_scanner_palette.dart';

/// Paints AR-style bounding boxes (and optional label chips) over the
/// camera preview for each detected barcode.
///
/// Place inside a `Stack` directly above `SupyBarcodeScannerView` with
/// `Positioned.fill`. Detections whose [SupyBarcode.boundingBox] is null
/// are skipped silently.
class SupyArOverlay extends StatelessWidget {
  /// Creates an AR overlay.
  const SupyArOverlay({
    required this.barcodes,
    super.key,
    this.config = const SupyArOverlayConfiguration(),
    this.palette = const SupyScannerPalette.supyDark(),
  });

  /// The barcodes to highlight. Boxes are in normalized `[0..1]`
  /// coordinates relative to the preview frame.
  final List<SupyBarcode> barcodes;

  /// Visual style.
  final SupyArOverlayConfiguration config;

  /// Palette used to resolve any color the [config] leaves null.
  final SupyScannerPalette palette;

  @override
  Widget build(BuildContext context) {
    if (!config.enabled || barcodes.isEmpty) {
      return const SizedBox.shrink();
    }
    return IgnorePointer(
      child: CustomPaint(
        painter: _ArOverlayPainter(
          barcodes: barcodes,
          config: config,
          palette: palette,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _ArOverlayPainter extends CustomPainter {
  _ArOverlayPainter({
    required this.barcodes,
    required this.config,
    required this.palette,
  });

  final List<SupyBarcode> barcodes;
  final SupyArOverlayConfiguration config;
  final SupyScannerPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke =
        Paint()
          ..color = config.strokeColor ?? palette.positive
          ..style = PaintingStyle.stroke
          ..strokeWidth = config.strokeWidth;
    final fill =
        Paint()
          ..color = config.fillColor ?? palette.positive.withValues(alpha: 0.2)
          ..style = PaintingStyle.fill;

    for (final b in barcodes) {
      final n = b.boundingBox;
      if (n == null) continue;
      final rect = Rect.fromLTWH(
        n.left * size.width,
        n.top * size.height,
        n.width * size.width,
        n.height * size.height,
      );
      final rrect = RRect.fromRectAndRadius(
        rect,
        Radius.circular(config.cornerRadius),
      );
      canvas.drawRRect(rrect, fill);
      canvas.drawRRect(rrect, stroke);

      if (config.showLabel) {
        _paintLabel(canvas, rect, b.rawValue, size);
      }
    }
  }

  void _paintLabel(Canvas canvas, Rect box, String text, Size canvasSize) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: config.labelTextColor ?? palette.onSurface,
          fontSize: config.labelTextSize,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: box.width.clamp(40.0, canvasSize.width));

    const hPad = 6.0;
    const vPad = 3.0;
    final chipW = tp.width + hPad * 2;
    final chipH = tp.height + vPad * 2;

    // Prefer above-box; if there's no room, place inside-top.
    var top = box.top - chipH - 4;
    if (top < 0) top = box.top + 4;
    var left = box.left;
    if (left + chipW > canvasSize.width) {
      left = canvasSize.width - chipW;
    }
    if (left < 0) left = 0;

    final chipRect = Rect.fromLTWH(left, top, chipW, chipH);
    final chipRRect = RRect.fromRectAndRadius(
      chipRect,
      const Radius.circular(4),
    );
    canvas.drawRRect(
      chipRRect,
      Paint()..color = config.labelBackgroundColor ?? palette.surfaceLow,
    );
    tp.paint(canvas, Offset(left + hPad, top + vPad));
  }

  @override
  bool shouldRepaint(covariant _ArOverlayPainter old) {
    return old.config != config ||
        old.palette != palette ||
        !_listEquals(old.barcodes, barcodes);
  }

  static bool _listEquals(List<SupyBarcode> a, List<SupyBarcode> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
