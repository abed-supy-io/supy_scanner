import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:supy_scanner/supy_scanner.dart';

// A small recognized-text tree: one block, two lines.
SupyRecognizedText _sample() => const SupyRecognizedText(
  fullText: 'Order SO-12345\nContact jane.doe@example.com',
  blocks: <SupyTextBlock>[
    SupyTextBlock(
      text: 'Order SO-12345\nContact jane.doe@example.com',
      boundingBox: Rect.fromLTWH(0.1, 0.1, 0.8, 0.4),
      lines: <SupyTextLine>[
        SupyTextLine(
          text: 'Order SO-12345',
          boundingBox: Rect.fromLTWH(0.1, 0.1, 0.8, 0.1),
          elements: <SupyTextElement>[],
        ),
        SupyTextLine(
          text: 'Contact jane.doe@example.com',
          boundingBox: Rect.fromLTWH(0.1, 0.3, 0.8, 0.1),
          elements: <SupyTextElement>[],
        ),
      ],
    ),
  ],
);

void main() {
  group('scope', () {
    test('line scope matches per line and carries the line box', () {
      final matches = SupyTextPatternMatcher.match(_sample(), [
        const SupyTextPattern(name: 'order', pattern: r'SO-\d+'),
      ]);
      expect(matches, hasLength(1));
      expect(matches.single.patternName, 'order');
      expect(matches.single.value, 'SO-12345');
      expect(
        matches.single.boundingBox,
        const Rect.fromLTWH(0.1, 0.1, 0.8, 0.1),
      );
    });

    test('fullText scope matches the joined text with no box', () {
      final matches = SupyTextPatternMatcher.match(_sample(), [
        const SupyTextPattern(
          name: 'order',
          pattern: r'SO-\d+',
          scope: SupyTextPatternScope.fullText,
        ),
      ]);
      expect(matches, hasLength(1));
      expect(matches.single.value, 'SO-12345');
      expect(matches.single.boundingBox, isNull);
    });

    test('block scope matches the block text and carries the block box', () {
      final matches = SupyTextPatternMatcher.match(_sample(), [
        const SupyTextPattern(
          name: 'order',
          pattern: r'SO-\d+',
          scope: SupyTextPatternScope.block,
        ),
      ]);
      expect(matches, hasLength(1));
      expect(
        matches.single.boundingBox,
        const Rect.fromLTWH(0.1, 0.1, 0.8, 0.4),
      );
    });
  });

  group('matching', () {
    test('captures groups 1..n', () {
      final matches = SupyTextPatternMatcher.match(_sample(), [
        const SupyTextPattern(name: 'order', pattern: r'([A-Z]+)-(\d+)'),
      ]);
      expect(matches.single.groups, <String?>['SO', '12345']);
    });

    test('the built-in email pattern matches case-insensitively', () {
      const text = SupyRecognizedText(
        fullText: 'JANE.DOE@EXAMPLE.COM',
        blocks: <SupyTextBlock>[
          SupyTextBlock(
            text: 'JANE.DOE@EXAMPLE.COM',
            boundingBox: Rect.fromLTWH(0, 0, 1, 1),
            lines: <SupyTextLine>[
              SupyTextLine(
                text: 'JANE.DOE@EXAMPLE.COM',
                boundingBox: Rect.fromLTWH(0, 0, 1, 1),
                elements: <SupyTextElement>[],
              ),
            ],
          ),
        ],
      );
      final matches = SupyTextPatternMatcher.match(text, [
        SupyTextPattern.email(),
      ]);
      expect(matches.single.value, 'JANE.DOE@EXAMPLE.COM');
      expect(matches.single.patternName, 'email');
    });

    test('multiple patterns produce results in pattern order', () {
      final matches = SupyTextPatternMatcher.match(_sample(), [
        SupyTextPattern.email(),
        const SupyTextPattern(name: 'order', pattern: r'SO-\d+'),
      ]);
      expect(matches.map((m) => m.patternName), ['email', 'order']);
    });

    test('a line with multiple hits yields multiple matches', () {
      const text = SupyRecognizedText(
        fullText: 'A1 B2 C3',
        blocks: <SupyTextBlock>[
          SupyTextBlock(
            text: 'A1 B2 C3',
            boundingBox: Rect.fromLTWH(0, 0, 1, 1),
            lines: <SupyTextLine>[
              SupyTextLine(
                text: 'A1 B2 C3',
                boundingBox: Rect.fromLTWH(0, 0, 1, 1),
                elements: <SupyTextElement>[],
              ),
            ],
          ),
        ],
      );
      final matches = SupyTextPatternMatcher.match(text, [
        const SupyTextPattern(name: 'code', pattern: r'[A-Z]\d'),
      ]);
      expect(matches.map((m) => m.value), ['A1', 'B2', 'C3']);
    });

    test('no patterns yields no matches', () {
      expect(SupyTextPatternMatcher.match(_sample(), const []), isEmpty);
    });

    test('the result list is unmodifiable', () {
      final matches = SupyTextPatternMatcher.match(_sample(), [
        const SupyTextPattern(name: 'order', pattern: r'SO-\d+'),
      ]);
      expect(
        () => matches.add(
          const SupyTextPatternMatch(patternName: 'x', value: 'y'),
        ),
        throwsUnsupportedError,
      );
    });
  });

  group('value semantics', () {
    test('equal patterns compare equal', () {
      expect(
        const SupyTextPattern(name: 'a', pattern: 'x'),
        const SupyTextPattern(name: 'a', pattern: 'x'),
      );
      expect(
        const SupyTextPattern(name: 'a', pattern: 'x').hashCode,
        const SupyTextPattern(name: 'a', pattern: 'x').hashCode,
      );
    });

    test('equal matches compare equal', () {
      const a = SupyTextPatternMatch(
        patternName: 'order',
        value: 'SO-1',
        groups: <String?>['SO', '1'],
      );
      const b = SupyTextPatternMatch(
        patternName: 'order',
        value: 'SO-1',
        groups: <String?>['SO', '1'],
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });
  });
}
