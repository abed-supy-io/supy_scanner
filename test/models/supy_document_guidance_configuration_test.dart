import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supy_scanner/supy_scanner.dart';

void main() {
  group('SupyDocumentGuidanceConfiguration defaults', () {
    test('threshold defaults match documented values', () {
      const cfg = SupyDocumentGuidanceConfiguration();
      expect(cfg.minCoverageRatio, 0.30);
      expect(cfg.maxCoverageRatio, 0.90);
      expect(cfg.maxTiltDegrees, 20.0);
      expect(cfg.minMeanLuma, 60.0);
      expect(cfg.minBlurScore, 80.0);
      expect(cfg.readyStableFrames, 5);
      expect(cfg.lostDocumentGraceFrames, 3);
      expect(cfg.exitMargin, 0.10);
      expect(cfg.minDwellFrames, 4);
      expect(cfg.smoothingAlpha, 0.35);
    });

    test('palette defaults: red for not-ready, green for ready', () {
      const cfg = SupyDocumentGuidanceConfiguration();
      expect(cfg.notReadyColor, const Color(0xFFE5484D));
      expect(cfg.readyColor, const Color(0xFF30A46C));
      expect(cfg.scrimColor.a, lessThan(1.0));
    });
  });

  group('SupyDocumentGuidanceConfiguration.colorFor', () {
    const cfg = SupyDocumentGuidanceConfiguration();

    const readyStates = <SupyDocumentFrameState>{
      SupyDocumentFrameState.ready,
      SupyDocumentFrameState.capturing,
      SupyDocumentFrameState.captured,
    };

    test('returns readyColor across the whole capture lifecycle', () {
      for (final s in readyStates) {
        expect(
          cfg.colorFor(s),
          equals(cfg.readyColor),
          reason: 'state $s should map to readyColor',
        );
      }
    });

    test('returns notReadyColor for every guidance-failure state', () {
      for (final s in SupyDocumentFrameState.values) {
        if (readyStates.contains(s)) continue;
        expect(
          cfg.colorFor(s),
          equals(cfg.notReadyColor),
          reason: 'state $s should map to notReadyColor',
        );
      }
    });
  });

  group('SupyDocumentGuidanceConfiguration.hintFor', () {
    const cfg = SupyDocumentGuidanceConfiguration();

    test('default hint text matches each state', () {
      expect(
        cfg.hintFor(SupyDocumentFrameState.noDocument),
        'Point the camera at a document',
      );
      expect(cfg.hintFor(SupyDocumentFrameState.tooDark), 'More light needed');
      expect(cfg.hintFor(SupyDocumentFrameState.tooClose), 'Move back');
      expect(cfg.hintFor(SupyDocumentFrameState.tooFar), 'Move closer');
      expect(
        cfg.hintFor(SupyDocumentFrameState.tooSkewed),
        'Hold the camera straight',
      );
      expect(cfg.hintFor(SupyDocumentFrameState.blurry), 'Hold steady');
      expect(cfg.hintFor(SupyDocumentFrameState.ready), 'Hold still…');
      expect(cfg.hintFor(SupyDocumentFrameState.capturing), 'Capturing…');
      expect(cfg.hintFor(SupyDocumentFrameState.captured), 'Captured!');
    });

    test('every state maps to a non-empty hint', () {
      for (final s in SupyDocumentFrameState.values) {
        expect(cfg.hintFor(s), isNotEmpty, reason: 'state $s has no hint');
      }
    });

    test('custom hints bundle is honored', () {
      const cfg = SupyDocumentGuidanceConfiguration(
        hints: SupyDocumentGuidanceHints(
          ready: 'Captura!',
          noDocument: 'Apunta a un documento',
        ),
      );
      expect(cfg.hintFor(SupyDocumentFrameState.ready), 'Captura!');
      expect(
        cfg.hintFor(SupyDocumentFrameState.noDocument),
        'Apunta a un documento',
      );
      // Untouched fields still default.
      expect(cfg.hintFor(SupyDocumentFrameState.blurry), 'Hold steady');
    });
  });

  group('SupyDocumentGuidanceConfiguration equality', () {
    test('two default configs are equal and share a hashCode', () {
      expect(
        const SupyDocumentGuidanceConfiguration(),
        equals(const SupyDocumentGuidanceConfiguration()),
      );
      expect(
        const SupyDocumentGuidanceConfiguration().hashCode,
        const SupyDocumentGuidanceConfiguration().hashCode,
      );
    });

    test('changing a threshold breaks equality', () {
      const a = SupyDocumentGuidanceConfiguration();
      const b = SupyDocumentGuidanceConfiguration(minCoverageRatio: 0.5);
      expect(a, isNot(equals(b)));
    });

    test('changing a color breaks equality', () {
      const a = SupyDocumentGuidanceConfiguration();
      const b = SupyDocumentGuidanceConfiguration(
        readyColor: Color(0xFF000000),
      );
      expect(a, isNot(equals(b)));
    });

    test('changing a hint bundle breaks equality', () {
      const a = SupyDocumentGuidanceConfiguration();
      const b = SupyDocumentGuidanceConfiguration(
        hints: SupyDocumentGuidanceHints(ready: 'Go!'),
      );
      expect(a, isNot(equals(b)));
    });

    test('toString contains the active threshold band', () {
      expect(
        const SupyDocumentGuidanceConfiguration().toString(),
        contains('0.3..0.9'),
      );
    });
  });

  group('SupyDocumentGuidanceHints equality', () {
    test('default hints are equal', () {
      expect(
        const SupyDocumentGuidanceHints(),
        equals(const SupyDocumentGuidanceHints()),
      );
    });

    test('overriding one field breaks equality', () {
      const a = SupyDocumentGuidanceHints();
      const b = SupyDocumentGuidanceHints(ready: 'now');
      expect(a, isNot(equals(b)));
      expect(a.hashCode, isNot(equals(b.hashCode)));
    });

    test('textFor switches across every state', () {
      const h = SupyDocumentGuidanceHints();
      final seen = <String>{};
      for (final s in SupyDocumentFrameState.values) {
        seen.add(h.textFor(s));
      }
      // All default hints are distinct strings.
      expect(seen, hasLength(SupyDocumentFrameState.values.length));
    });
  });
}
