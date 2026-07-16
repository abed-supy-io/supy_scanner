import 'package:flutter/widgets.dart';

import '../models/ui/supy_view_finder_configuration.dart';

/// Renders a Scanbot-style cornered finder: four corner brackets fitted to
/// the largest rectangle of [SupyViewFinderConfiguration.aspectRatio] that
/// fits inside the available size, centered.
class SupyFinderPainter extends CustomPainter {
  /// Creates a finder painter bound to [config].
  SupyFinderPainter({required this.config});

  /// View-finder visual configuration.
  final SupyViewFinderConfiguration config;

  @override
  void paint(Canvas canvas, Size size) {
    if (!config.visible) return;
    final style = config.style;
    if (style is! SupyFinderCorneredStyle) return;

    final rect = _fitRect(size, config.aspectRatio.value);
    final paint =
        Paint()
          ..color = style.strokeColor
          ..strokeWidth = style.strokeWidth
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;

    final arm = style.cornerLength;
    final r = style.cornerRadius.clamp(0.0, arm / 2);

    _drawCorner(canvas, paint, rect.topLeft, arm, r, _Corner.topLeft);
    _drawCorner(canvas, paint, rect.topRight, arm, r, _Corner.topRight);
    _drawCorner(canvas, paint, rect.bottomLeft, arm, r, _Corner.bottomLeft);
    _drawCorner(canvas, paint, rect.bottomRight, arm, r, _Corner.bottomRight);
  }

  Rect _fitRect(Size size, double ratio) {
    const margin = 0.85;
    final maxW = size.width * margin;
    final maxH = size.height * margin;
    var w = maxW;
    var h = w / ratio;
    if (h > maxH) {
      h = maxH;
      w = h * ratio;
    }
    final left = (size.width - w) / 2;
    final top = (size.height - h) / 2;
    return Rect.fromLTWH(left, top, w, h);
  }

  void _drawCorner(
    Canvas canvas,
    Paint paint,
    Offset corner,
    double arm,
    double radius,
    _Corner which,
  ) {
    final path = Path();
    switch (which) {
      case _Corner.topLeft:
        path.moveTo(corner.dx, corner.dy + arm);
        path.lineTo(corner.dx, corner.dy + radius);
        path.quadraticBezierTo(
          corner.dx,
          corner.dy,
          corner.dx + radius,
          corner.dy,
        );
        path.lineTo(corner.dx + arm, corner.dy);
      case _Corner.topRight:
        path.moveTo(corner.dx - arm, corner.dy);
        path.lineTo(corner.dx - radius, corner.dy);
        path.quadraticBezierTo(
          corner.dx,
          corner.dy,
          corner.dx,
          corner.dy + radius,
        );
        path.lineTo(corner.dx, corner.dy + arm);
      case _Corner.bottomLeft:
        path.moveTo(corner.dx, corner.dy - arm);
        path.lineTo(corner.dx, corner.dy - radius);
        path.quadraticBezierTo(
          corner.dx,
          corner.dy,
          corner.dx + radius,
          corner.dy,
        );
        path.lineTo(corner.dx + arm, corner.dy);
      case _Corner.bottomRight:
        path.moveTo(corner.dx - arm, corner.dy);
        path.lineTo(corner.dx - radius, corner.dy);
        path.quadraticBezierTo(
          corner.dx,
          corner.dy,
          corner.dx,
          corner.dy - radius,
        );
        path.lineTo(corner.dx, corner.dy - arm);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant SupyFinderPainter old) => old.config != config;
}

enum _Corner { topLeft, topRight, bottomLeft, bottomRight }
