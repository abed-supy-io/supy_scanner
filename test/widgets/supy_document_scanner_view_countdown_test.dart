// test/widgets/supy_document_scanner_view_countdown_test.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supy_scanner/src/widgets/supy_document_scanner_view.dart';

void main() {
  // The countdown widget should be addressable in isolation. Plan: extract the
  // countdown ring into a `SupyDocumentCountdownRing` widget exported from
  // supy_document_scanner_view.dart so it's testable without a platform view.
  testWidgets('countdown ring sweeps over autoCaptureDelay', (tester) async {
    final completer = Completer<void>();
    await tester.pumpWidget(MaterialApp(
      home: SupyDocumentCountdownRing(
        duration: const Duration(milliseconds: 300),
        color: const Color(0xFF1AC0E5),
        onComplete: completer.complete,
      ),
    ),);
    await tester.pump(const Duration(milliseconds: 150));
    // Mid-sweep — visible.
    expect(find.byType(SupyDocumentCountdownRing), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 160));
    expect(completer.isCompleted, isTrue);
  });
}
