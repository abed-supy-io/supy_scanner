import 'package:flutter/material.dart';

import '../models/supy_barcode.dart';
import '../models/ui/supy_single_scan_use_case_configuration.dart';

/// Bottom sheet shown by the single-scan use case after a barcode is
/// detected. Matches the Scanbot single-scan confirmation surface: a title,
/// the decoded payload, a format chip, a primary submit button, and a
/// retry text button.
class SupySingleScanConfirmationSheet extends StatelessWidget {
  /// Creates a confirmation sheet.
  const SupySingleScanConfirmationSheet({
    required this.barcode,
    required this.config,
    required this.onConfirm,
    required this.onRetry,
    super.key,
  });

  /// The detected barcode the user is being asked to confirm.
  final SupyBarcode barcode;

  /// Visibility/text/color knobs.
  final SupySingleScanUseCaseConfiguration config;

  /// Invoked when the user taps the primary (submit) button.
  final VoidCallback onConfirm;

  /// Invoked when the user taps the retry text button.
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: config.sheetBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: config.bodyColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                config.title,
                style: TextStyle(
                  color: config.titleColor,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (config.showBarcodeFormat) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: _FormatChip(
                    label: barcode.format.name,
                    color: config.bodyColor,
                  ),
                ),
              ],
              if (config.showRawValue) ...[
                const SizedBox(height: 12),
                SelectableText(
                  barcode.rawValue,
                  style: TextStyle(color: config.bodyColor, fontSize: 14),
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: onConfirm,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: config.confirmButtonBackgroundColor,
                    foregroundColor: config.confirmButtonForegroundColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(config.confirmButtonText),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: onRetry,
                style: TextButton.styleFrom(
                  foregroundColor: config.retryButtonForegroundColor,
                ),
                child: Text(config.retryButtonText),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FormatChip extends StatelessWidget {
  const _FormatChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
