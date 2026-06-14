import 'package:flutter_test/flutter_test.dart';
import 'package:supy_scanner/supy_scanner.dart';

void main() {
  group('SupyDocumentPage.fromMap', () {
    test('parses minimal v1.0 payload with no quality fields', () {
      final page = SupyDocumentPage.fromMap(<Object?, Object?>{
        'uri': 'file:///tmp/p.jpg',
        'width': 1000,
        'height': 1500,
      });
      expect(page.uri, 'file:///tmp/p.jpg');
      expect(page.width, 1000);
      expect(page.height, 1500);
      expect(page.quality, isNull);
      expect(page.qualityScore, isNull);
    });

    test('parses v1.1 payload with quality + qualityScore', () {
      final page = SupyDocumentPage.fromMap(<Object?, Object?>{
        'uri': 'file:///tmp/p.jpg',
        'width': 1,
        'height': 1,
        'quality': 'good',
        'qualityScore': 0.82,
      });
      expect(page.quality, SupyDocumentPageQuality.good);
      expect(page.qualityScore, 0.82);
    });

    test('maps every bucket name', () {
      const wires = {
        'veryPoor': SupyDocumentPageQuality.veryPoor,
        'poor': SupyDocumentPageQuality.poor,
        'ok': SupyDocumentPageQuality.ok,
        'good': SupyDocumentPageQuality.good,
        'excellent': SupyDocumentPageQuality.excellent,
      };
      for (final entry in wires.entries) {
        final page = SupyDocumentPage.fromMap(<Object?, Object?>{
          'uri': 'x',
          'width': 1,
          'height': 1,
          'quality': entry.key,
        });
        expect(page.quality, entry.value, reason: entry.key);
      }
    });

    test('unknown quality string parses as null (forward-compat)', () {
      final page = SupyDocumentPage.fromMap(<Object?, Object?>{
        'uri': 'x',
        'width': 1,
        'height': 1,
        'quality': 'archival_plus',
      });
      expect(page.quality, isNull);
    });

    test('qualityScore tolerates int and double inputs', () {
      final intScore = SupyDocumentPage.fromMap(<Object?, Object?>{
        'uri': 'x',
        'width': 1,
        'height': 1,
        'qualityScore': 1,
      });
      expect(intScore.qualityScore, 1.0);
    });

    test('equality includes quality + qualityScore', () {
      const a = SupyDocumentPage(
        uri: 'x',
        width: 1,
        height: 1,
        quality: SupyDocumentPageQuality.good,
        qualityScore: 0.7,
      );
      const b = SupyDocumentPage(
        uri: 'x',
        width: 1,
        height: 1,
        quality: SupyDocumentPageQuality.good,
        qualityScore: 0.7,
      );
      const differentQuality = SupyDocumentPage(
        uri: 'x',
        width: 1,
        height: 1,
        quality: SupyDocumentPageQuality.ok,
        qualityScore: 0.7,
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == differentQuality, isFalse);
    });
  });
}
