import 'package:flutter/widgets.dart';

import '../models/ui/supy_top_bar_configuration.dart';

/// Internal top-bar widget — renders cancel control + optional gradient scrim
/// from [SupyTopBarConfiguration]. Not exported.
class SupyTopBar extends StatelessWidget {
  /// Creates a top bar.
  const SupyTopBar({required this.config, required this.onCancel, super.key});

  /// Visual configuration.
  final SupyTopBarConfiguration config;

  /// Invoked when the cancel control is tapped.
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final decoration = switch (config.mode) {
      SupyTopBarMode.solid => BoxDecoration(color: config.backgroundColor),
      SupyTopBarMode.gradient => BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [config.backgroundColor, config.backgroundColor.withAlpha(0)],
        ),
      ),
    };
    final cancel = config.cancelButton;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      decoration: decoration,
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            if (cancel.text.isNotEmpty)
              _CancelButton(spec: cancel, onPressed: onCancel)
            else
              const SizedBox.shrink(),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}

class _CancelButton extends StatelessWidget {
  const _CancelButton({required this.spec, required this.onPressed});

  final SupyTextStyleSpec spec;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onPressed,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Text(
          spec.text,
          style: TextStyle(
            color: spec.color,
            fontSize: spec.fontSize,
            fontWeight: spec.fontWeight,
          ),
        ),
      ),
    );
  }
}
