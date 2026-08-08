import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../models/ui/supy_scanner_palette.dart';
import '../models/ui/supy_scanner_strings.dart';
import '../models/ui/supy_top_bar_configuration.dart';

/// Internal top-bar widget — renders cancel control + optional gradient scrim
/// from [SupyTopBarConfiguration], and applies its [SupyStatusBarMode]. Not
/// exported.
class SupyTopBar extends StatefulWidget {
  /// Creates a top bar.
  const SupyTopBar({
    required this.config,
    required this.onCancel,
    this.palette = const SupyScannerPalette.supyDark(),
    this.strings = const SupyScannerStrings.en(),
    super.key,
  });

  /// Visual configuration.
  final SupyTopBarConfiguration config;

  /// Invoked when the cancel control is tapped.
  final VoidCallback onCancel;

  /// Palette used to resolve any color the [config] leaves null.
  final SupyScannerPalette palette;

  /// String bundle used to resolve copy the [config] leaves null.
  final SupyScannerStrings strings;

  @override
  State<SupyTopBar> createState() => _SupyTopBarState();
}

class _SupyTopBarState extends State<SupyTopBar> {
  @override
  void initState() {
    super.initState();
    _applyStatusBarMode(widget.config.statusBarMode);
  }

  @override
  void didUpdateWidget(SupyTopBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.config.statusBarMode != widget.config.statusBarMode) {
      _applyStatusBarMode(widget.config.statusBarMode);
    }
  }

  @override
  void dispose() {
    // Restore both system bars if we hid the status bar while on screen.
    if (widget.config.statusBarMode == SupyStatusBarMode.hidden) {
      unawaited(
        SystemChrome.setEnabledSystemUIMode(
          SystemUiMode.manual,
          overlays: SystemUiOverlay.values,
        ),
      );
    }
    super.dispose();
  }

  // `hidden` toggles overlay visibility imperatively; `light`/`dark` only set
  // the overlay foreground style (applied declaratively in [build]) and must
  // re-show the status bar in case a prior mode hid it.
  void _applyStatusBarMode(SupyStatusBarMode mode) {
    switch (mode) {
      case SupyStatusBarMode.hidden:
        unawaited(
          SystemChrome.setEnabledSystemUIMode(
            SystemUiMode.manual,
            overlays: const [SystemUiOverlay.bottom],
          ),
        );
      case SupyStatusBarMode.light:
      case SupyStatusBarMode.dark:
        unawaited(
          SystemChrome.setEnabledSystemUIMode(
            SystemUiMode.manual,
            overlays: SystemUiOverlay.values,
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = widget.config;
    final bg = config.backgroundColor ?? widget.palette.surfaceLow;
    final decoration = switch (config.mode) {
      SupyTopBarMode.solid => BoxDecoration(color: bg),
      SupyTopBarMode.gradient => BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [bg, bg.withAlpha(0)],
        ),
      ),
    };
    final cancel = config.cancelButton;
    final cancelLabel = cancel.text ?? widget.strings.cancel;
    final bar = Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      decoration: decoration,
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            if (cancelLabel.isNotEmpty)
              _CancelButton(
                spec: cancel,
                label: cancelLabel,
                color: cancel.color ?? widget.palette.onSurface,
                onPressed: widget.onCancel,
              )
            else
              const SizedBox.shrink(),
            const Spacer(),
          ],
        ),
      ),
    );
    return switch (config.statusBarMode) {
      SupyStatusBarMode.hidden => bar,
      SupyStatusBarMode.light => AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: bar,
      ),
      SupyStatusBarMode.dark => AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark,
        child: bar,
      ),
    };
  }
}

class _CancelButton extends StatelessWidget {
  const _CancelButton({
    required this.spec,
    required this.label,
    required this.color,
    required this.onPressed,
  });

  final SupyTextStyleSpec spec;
  final String label;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: spec.fontSize,
              fontWeight: spec.fontWeight,
            ),
          ),
        ),
      ),
    );
  }
}
