import 'package:flutter/material.dart';

import '../models/ui/supy_action_bar_configuration.dart';
import '../models/ui/supy_scanner_palette.dart';
import '../models/ui/supy_scanner_strings.dart';
import 'supy_barcode_scanner_controller.dart';

/// Internal action-bar widget — renders the row of circular controls
/// (flash, zoom, flip-camera, close-focus) above the bottom edge of the
/// camera preview. Not exported.
class SupyActionBar extends StatelessWidget {
  /// Creates an action bar.
  const SupyActionBar({
    required this.config,
    required this.controller,
    this.maxZoom = 8.0,
    this.palette = const SupyScannerPalette.supyDark(),
    this.strings = const SupyScannerStrings.en(),
    super.key,
  });

  /// Visual + visibility configuration.
  final SupyActionBarConfiguration config;

  /// Scanner controller the buttons delegate to.
  final SupyBarcodeScannerController controller;

  /// Palette used to resolve any color the [config] leaves null.
  final SupyScannerPalette palette;

  /// String bundle supplying the buttons' accessibility labels.
  final SupyScannerStrings strings;

  /// Soft ceiling for the on-screen zoom step. The native layer clamps to the
  /// actual device range; this caps the UI loop so a tap at the max wraps to
  /// 1.0 instead of growing unbounded.
  final double maxZoom;

  @override
  Widget build(BuildContext context) {
    if (!config.visible) return const SizedBox.shrink();

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final buttons = <Widget>[
          if (config.flashButton.visible)
            _ActionButton(
              spec: config.flashButton,
              palette: palette,
              active: controller.torchOn,
              icon: controller.torchOn ? Icons.flash_on : Icons.flash_off,
              semanticLabel: strings.flash,
              onTap: () => controller.setTorch(on: !controller.torchOn),
            ),
          if (config.zoomButton.visible)
            _ActionButton(
              spec: config.zoomButton,
              palette: palette,
              active: controller.zoom > 1.0,
              icon: Icons.zoom_in,
              label: _zoomLabel(controller.zoom),
              semanticLabel: strings.zoomLabel(_zoomLabel(controller.zoom)),
              onTap: () => controller.setZoom(_nextZoom(controller.zoom)),
            ),
          if (config.flipCameraButton.visible)
            _ActionButton(
              spec: config.flipCameraButton,
              palette: palette,
              active: controller.cameraPosition == SupyCameraPosition.front,
              icon: Icons.flip_camera_ios,
              semanticLabel: strings.flipCamera,
              onTap: controller.flipCamera,
            ),
          if (config.closeFocusButton.visible)
            _ActionButton(
              spec: config.closeFocusButton,
              palette: palette,
              active: controller.minFocusDistanceLock,
              icon: Icons.center_focus_strong,
              semanticLabel: strings.closeFocus,
              onTap:
                  () => controller.setMinFocusDistanceLock(
                    on: !controller.minFocusDistanceLock,
                  ),
            ),
        ];

        if (buttons.isEmpty) return const SizedBox.shrink();

        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: buttons,
            ),
          ),
        );
      },
    );
  }

  double _nextZoom(double current) {
    final next = current * config.zoomFactor;
    return next > maxZoom ? 1.0 : next;
  }

  String? _zoomLabel(double zoom) {
    if (zoom <= 1.0) return null;
    final rounded = zoom.toStringAsFixed(zoom % 1 == 0 ? 0 : 1);
    return '${rounded}x';
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.spec,
    required this.palette,
    required this.active,
    required this.icon,
    required this.onTap,
    required this.semanticLabel,
    this.label,
  });

  final SupyActionButtonSpec spec;
  final SupyScannerPalette palette;
  final bool active;
  final IconData icon;
  final VoidCallback onTap;
  final String semanticLabel;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final bg =
        active
            ? spec.activeBackgroundColor ?? palette.onPrimary
            : spec.backgroundColor ?? palette.surfaceLow.withValues(alpha: 0.4);
    final fg =
        active
            ? spec.activeForegroundColor ?? palette.onSecondary
            : spec.foregroundColor ?? palette.onSurface;
    return Semantics(
      button: true,
      toggled: active,
      label: semanticLabel,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
          alignment: Alignment.center,
          child:
              label != null
                  ? Text(
                    label!,
                    style: TextStyle(
                      color: fg,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                  : Icon(icon, color: fg, size: 26),
        ),
      ),
    );
  }
}
