import 'package:flutter_test/flutter_test.dart';
import 'package:supy_scanner/src/models/supy_document_frame_metrics.dart';

void main() {
  group('SupyDocumentFrameMetrics', () {
    test('defaults: quadStability = 0.0, interiorVariance = 0.0', () {
      const m = SupyDocumentFrameMetrics();
      expect(m.quadStability, 0.0);
      expect(m.interiorVariance, 0.0);
    });

    test('fromMap reads new optional fields', () {
      final m = SupyDocumentFrameMetrics.fromMap(const <Object?, Object?>{
        'quad': <Object?>[],
        'coverageRatio': 0.5,
        'tiltDegrees': 1.0,
        'meanLuma': 120.0,
        'blurScore': 90.0,
        'clipsEdge': false,
        'quadStability': 0.8,
        'interiorVariance': 42.5,
      });
      expect(m.quadStability, 0.8);
      expect(m.interiorVariance, 42.5);
    });

    test('fromMap tolerates missing new fields (back-compat)', () {
      final m = SupyDocumentFrameMetrics.fromMap(const <Object?, Object?>{
        'coverageRatio': 0.5,
      });
      expect(m.quadStability, 0.0);
      expect(m.interiorVariance, 0.0);
    });

    test('equality includes new fields', () {
      const a = SupyDocumentFrameMetrics(quadStability: 0.5);
      const b = SupyDocumentFrameMetrics(quadStability: 0.6);
      expect(a == b, isFalse);
    });
  });
}
