import 'package:flutter/widgets.dart';

import '../models/ui/supy_user_guidance_configuration.dart';

/// Internal guidance-card widget — renders the hint text from
/// [SupyUserGuidanceConfiguration] as a pill near the bottom of the camera
/// preview. Not exported.
class SupyUserGuidanceCard extends StatelessWidget {
  /// Creates a guidance card.
  const SupyUserGuidanceCard({required this.config, super.key});

  /// Visibility / text / color configuration.
  final SupyUserGuidanceConfiguration config;

  @override
  Widget build(BuildContext context) {
    if (!config.visible || config.titleText.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: config.backgroundFillColor,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Text(
        config.titleText,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: config.titleColor,
          fontSize: config.fontSize,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
