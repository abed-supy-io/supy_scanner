import 'package:flutter/material.dart';

import '../models/supy_barcode.dart';
import '../models/ui/supy_scanner_palette.dart';
import '../models/ui/supy_scanner_strings.dart';
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
    this.palette = const SupyScannerPalette.supyDark(),
    this.strings = const SupyScannerStrings.en(),
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

  /// Palette used to resolve any color the [config] leaves null.
  final SupyScannerPalette palette;

  /// String bundle used to resolve copy the [config] leaves null.
  final SupyScannerStrings strings;

  @override
  Widget build(BuildContext context) {
    final titleColor = config.titleColor ?? palette.onSurface;
    final bodyColor = config.bodyColor ?? palette.onSurfaceVariant;
    return Material(
      color: config.sheetBackgroundColor ?? palette.surface,
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
                    color: bodyColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                config.title ?? strings.barcodeDetected,
                style: TextStyle(
                  color: titleColor,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (config.showBarcodeFormat) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: _FormatChip(
                    label: barcode.format.name,
                    color: bodyColor,
                  ),
                ),
              ],
              if (config.showRawValue) ...[
                const SizedBox(height: 12),
                SelectableText(
                  barcode.rawValue,
                  style: TextStyle(color: bodyColor, fontSize: 14),
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: onConfirm,
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        config.confirmButtonBackgroundColor ?? palette.primary,
                    foregroundColor:
                        config.confirmButtonForegroundColor ??
                        palette.onPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(config.confirmButtonText ?? strings.submit),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: onRetry,
                style: TextButton.styleFrom(
                  foregroundColor:
                      config.retryButtonForegroundColor ?? palette.onSurface,
                ),
                child: Text(config.retryButtonText ?? strings.retry),
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
