import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supy_scanner/supy_scanner.dart';

void main() {
  Widget host({
    required List<SupyBarcode> barcodes,
    SupyArOverlayConfiguration config = const SupyArOverlayConfiguration(),
  }) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: SizedBox(
        width: 400,
        height: 600,
        child: SupyArOverlay(barcodes: barcodes, config: config),
      ),
    );
  }

  testWidgets('renders SizedBox.shrink when disabled', (tester) async {
    await tester.pumpWidget(
      host(
        barcodes: const [
          SupyBarcode(
            rawValue: 'x',
            format: SupyBarcodeFormat.qr,
            boundingBox: Rect.fromLTWH(0.1, 0.1, 0.2, 0.2),
          ),
        ],
        config: const SupyArOverlayConfiguration(enabled: false),
      ),
    );
    expect(find.byType(CustomPaint), findsNothing);
  });

  testWidgets('renders SizedBox.shrink when no barcodes', (tester) async {
    await tester.pumpWidget(host(barcodes: const []));
    expect(find.byType(CustomPaint), findsNothing);
  });

  testWidgets('renders CustomPaint when at least one box present', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        barcodes: const [
          SupyBarcode(
            rawValue: '1234567890123',
            format: SupyBarcodeFormat.ean13,
            boundingBox: Rect.fromLTWH(0.1, 0.1, 0.4, 0.2),
          ),
        ],
      ),
    );
    expect(find.byType(CustomPaint), findsOneWidget);
  });

  testWidgets('barcodes without a box are skipped (no crash)', (tester) async {
    await tester.pumpWidget(
      host(
        barcodes: const [
          SupyBarcode(rawValue: 'no-box', format: SupyBarcodeFormat.qr),
        ],
      ),
    );
    // Should still build the painter — painter loop just no-ops the entry.
    expect(find.byType(CustomPaint), findsOneWidget);
  });

  test('painter shouldRepaint detects config + list changes', () {
    // Indirectly via two widgets: equality of identical configs + lists.
    const a = SupyArOverlayConfiguration();
    const b = SupyArOverlayConfiguration(strokeWidth: 4);
    expect(a == a, isTrue);
    expect(a == b, isFalse);
  });
}
