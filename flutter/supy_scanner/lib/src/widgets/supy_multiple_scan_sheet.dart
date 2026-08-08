import 'package:flutter/material.dart';

import '../models/ui/supy_multiple_scan_use_case_configuration.dart';
import '../models/ui/supy_scanner_palette.dart';
import '../models/ui/supy_scanner_strings.dart';
import 'supy_multiple_scan_accumulator.dart';

/// Collapsible bottom sheet rendered by the multi-scan use case. The header
/// shows the running count and a chevron; the body (when expanded) shows
/// the scrollable list of items and the submit / clear actions.
class SupyMultipleScanSheet extends StatefulWidget {
  /// Creates a multi-scan sheet.
  const SupyMultipleScanSheet({
    required this.accumulator,
    required this.config,
    required this.onSubmit,
    required this.onClear,
    this.palette = const SupyScannerPalette.supyDark(),
    this.strings = const SupyScannerStrings.en(),
    super.key,
  });

  /// State source; the sheet listens for updates.
  final SupyMultipleScanAccumulator accumulator;

  /// Visibility / text / color knobs.
  final SupyMultipleScanUseCaseConfiguration config;

  /// Palette used to resolve any color the [config] leaves null.
  final SupyScannerPalette palette;

  /// String bundle used to resolve copy the [config] leaves null.
  final SupyScannerStrings strings;

  /// Invoked on submit-button tap. Receives the current items via the
  /// accumulator the caller already holds.
  final VoidCallback onSubmit;

  /// Invoked on clear-button tap. The sheet does NOT auto-clear — the
  /// caller decides (so a confirmation dialog can intercept).
  final VoidCallback onClear;

  @override
  State<SupyMultipleScanSheet> createState() => _SupyMultipleScanSheetState();
}

class _SupyMultipleScanSheetState extends State<SupyMultipleScanSheet> {
  late bool _expanded = !widget.config.initiallyCollapsed;

  Color get _titleColor => widget.config.titleColor ?? widget.palette.onSurface;
  Color get _bodyColor =>
      widget.config.bodyColor ?? widget.palette.onSurfaceVariant;

  @override
  Widget build(BuildContext context) {
    final cfg = widget.config;
    return Material(
      color: cfg.sheetBackgroundColor ?? widget.palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: AnimatedBuilder(
          animation: widget.accumulator,
          builder: (context, _) {
            final items = widget.accumulator.items;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [_header(items.length), if (_expanded) _body(items)],
            );
          },
        ),
      ),
    );
  }

  Widget _header(int rowCount) {
    final cfg = widget.config;
    final total = widget.accumulator.totalCount;
    return InkWell(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 16, 14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    cfg.sheetTitle ?? widget.strings.itemsScanned,
                    style: TextStyle(
                      color: _titleColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    cfg.mode == SupyMultipleScanMode.counting
                        ? widget.strings.scanCountSummary(total, rowCount)
                        : widget.strings.uniqueSummary(rowCount),
                    style: TextStyle(color: _bodyColor, fontSize: 12),
                  ),
                ],
              ),
            ),
            Icon(
              _expanded ? Icons.expand_more : Icons.expand_less,
              color: _titleColor,
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(List<SupyMultipleScanItem> items) {
    final cfg = widget.config;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 240),
          child:
              items.isEmpty
                  ? Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                    child: Text(
                      widget.strings.noItemsYet,
                      style: TextStyle(color: _bodyColor, fontSize: 13),
                    ),
                  )
                  : ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    itemCount: items.length,
                    separatorBuilder:
                        (_, _) => Divider(
                          height: 12,
                          color: _bodyColor.withValues(alpha: 0.1),
                        ),
                    itemBuilder: (_, i) => _row(items[i]),
                  ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: items.isEmpty ? null : widget.onClear,
                  style: TextButton.styleFrom(
                    foregroundColor:
                        cfg.clearButtonForegroundColor ??
                        widget.palette.onSurface,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: Text(cfg.clearButtonText ?? widget.strings.clear),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: items.isEmpty ? null : widget.onSubmit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        cfg.submitButtonBackgroundColor ??
                        widget.palette.primary,
                    foregroundColor:
                        cfg.submitButtonForegroundColor ??
                        widget.palette.onPrimary,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(cfg.submitButtonText ?? widget.strings.submit),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _row(SupyMultipleScanItem item) {
    final cfg = widget.config;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.barcode.rawValue,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: _titleColor, fontSize: 14),
              ),
              Text(
                item.barcode.format.name,
                style: TextStyle(color: _bodyColor, fontSize: 11),
              ),
            ],
          ),
        ),
        if (cfg.mode == SupyMultipleScanMode.counting)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _bodyColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              'x${item.count}',
              style: TextStyle(
                color: _titleColor,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }
}
