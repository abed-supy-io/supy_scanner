import 'package:flutter/widgets.dart';

import '../models/ui/supy_scanner_palette.dart';
import '../models/ui/supy_scanner_strings.dart';
import '../models/ui/supy_user_guidance_configuration.dart';

/// Internal guidance-card widget — renders the hint text from
/// [SupyUserGuidanceConfiguration] as a pill near the bottom of the camera
/// preview. Not exported.
class SupyUserGuidanceCard extends StatelessWidget {
  /// Creates a guidance card.
  const SupyUserGuidanceCard({
    required this.config,
    this.palette = const SupyScannerPalette.supyDark(),
    this.strings = const SupyScannerStrings.en(),
    super.key,
  });

  /// Visibility / text / color configuration.
  final SupyUserGuidanceConfiguration config;

  /// Palette used to resolve any color the [config] leaves null.
  final SupyScannerPalette palette;

  /// String bundle used to resolve copy the [config] leaves null.
  final SupyScannerStrings strings;

  @override
  Widget build(BuildContext context) {
    final title = config.titleText ?? strings.barcodeGuidanceTitle;
    if (!config.visible || title.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: config.backgroundFillColor ?? palette.modalOverlay,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Text(
        title,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: config.titleColor ?? palette.onSurface,
          fontSize: config.fontSize,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
