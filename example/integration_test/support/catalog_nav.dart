// Shared navigation helper for the integration_test/ harness.
//
// The catalog home (`CatalogHome`) is a single scrolling list of feature
// cards. A card for a feature lower in the list may be off-screen, so tapping
// it requires scrolling it into view first. `openCatalogEntry` does that by
// title — the same title string that appears in `kCatalogEntries`.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supy_scanner_example/main.dart';

/// Boots the app and taps the catalog card whose title is [title], scrolling
/// it into view first. Leaves the pushed detail page settled and ready to
/// assert on.
Future<void> openCatalogEntry(WidgetTester tester, String title) async {
  await tester.pumpWidget(const SupyScannerExampleApp());
  await tester.pumpAndSettle();

  final card = find.text(title);
  await tester.scrollUntilVisible(
    card,
    240,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(card);
  await tester.pumpAndSettle();
}
