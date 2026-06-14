import 'package:meta/meta.dart';

import 'supy_find_and_pick_use_case_configuration.dart';
import 'supy_multiple_scan_use_case_configuration.dart';
import 'supy_single_scan_use_case_configuration.dart';

/// The active scanning use case for a [SupyBarcodeScannerScreen].
///
/// Mirrors Scanbot's RTU-UI `useCase` discriminated union — choose one of
/// the three variants to bind the corresponding bottom sheet and result
/// shape on the composite screen.
@immutable
sealed class SupyScanUseCase {
  const SupyScanUseCase();
}

/// Single-scan: pause on first detection, optionally show confirmation
/// sheet, return one [SupyBarcode] via the screen's `onSubmit`.
@immutable
final class SupySingleScanUseCase extends SupyScanUseCase {
  /// Creates a single-scan use case wrapping its configuration.
  const SupySingleScanUseCase({
    this.config = const SupySingleScanUseCaseConfiguration(),
  });

  /// The single-scan configuration (sheet text/colors, confirmation toggle).
  final SupySingleScanUseCaseConfiguration config;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SupySingleScanUseCase && other.config == config;

  @override
  int get hashCode => config.hashCode;

  @override
  String toString() => 'SupySingleScanUseCase($config)';
}

/// Multi-scan: keep scanning until the user submits — counting or unique
/// mode, with a collapsible accumulator sheet.
@immutable
final class SupyMultipleScanUseCase extends SupyScanUseCase {
  /// Creates a multi-scan use case wrapping its configuration.
  const SupyMultipleScanUseCase({
    this.config = const SupyMultipleScanUseCaseConfiguration(),
  });

  /// The multi-scan configuration (mode, debounce, sheet knobs).
  final SupyMultipleScanUseCaseConfiguration config;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SupyMultipleScanUseCase && other.config == config;

  @override
  int get hashCode => config.hashCode;

  @override
  String toString() => 'SupyMultipleScanUseCase($config)';
}

/// Find-and-pick: scan against a known pick-list, submit when every
/// expected row is satisfied.
@immutable
final class SupyFindAndPickUseCase extends SupyScanUseCase {
  /// Creates a find-and-pick use case wrapping its configuration.
  const SupyFindAndPickUseCase({required this.config});

  /// The find-and-pick configuration (pick-list, sheet text/colors).
  final SupyFindAndPickUseCaseConfiguration config;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SupyFindAndPickUseCase && other.config == config;

  @override
  int get hashCode => config.hashCode;

  @override
  String toString() => 'SupyFindAndPickUseCase($config)';
}
