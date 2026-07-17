import 'package:flutter/material.dart';

import '../models/ui/supy_multiple_scan_use_case_configuration.dart';
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
    super.key,
  });

  /// State source; the sheet listens for updates.
  final SupyMultipleScanAccumulator accumulator;

  /// Visibility / text / color knobs.
  final SupyMultipleScanUseCaseConfiguration config;

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

  @override
  Widget build(BuildContext context) {
    final cfg = widget.config;
    return Material(
      color: cfg.sheetBackgroundColor,
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
                    cfg.sheetTitle,
                    style: TextStyle(
                      color: cfg.titleColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    cfg.mode == SupyMultipleScanMode.counting
                        ? '$total scans · $rowCount unique'
                        : '$rowCount unique',
                    style: TextStyle(color: cfg.bodyColor, fontSize: 12),
                  ),
                ],
              ),
            ),
            Icon(
              _expanded ? Icons.expand_more : Icons.expand_less,
              color: cfg.titleColor,
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
                      'No items yet',
                      style: TextStyle(color: cfg.bodyColor, fontSize: 13),
                    ),
                  )
                  : ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    itemCount: items.length,
                    separatorBuilder:
                        (_, __) => Divider(
                          height: 12,
                          color: cfg.bodyColor.withValues(alpha: 0.1),
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
                    foregroundColor: cfg.clearButtonForegroundColor,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: Text(cfg.clearButtonText),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: items.isEmpty ? null : widget.onSubmit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: cfg.submitButtonBackgroundColor,
                    foregroundColor: cfg.submitButtonForegroundColor,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(cfg.submitButtonText),
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
                style: TextStyle(color: cfg.titleColor, fontSize: 14),
              ),
              Text(
                item.barcode.format.name,
                style: TextStyle(color: cfg.bodyColor, fontSize: 11),
              ),
            ],
          ),
        ),
        if (cfg.mode == SupyMultipleScanMode.counting)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: cfg.bodyColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              'x${item.count}',
              style: TextStyle(
                color: cfg.titleColor,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }
}
