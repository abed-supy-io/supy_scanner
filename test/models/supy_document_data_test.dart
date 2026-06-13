import 'package:flutter_test/flutter_test.dart';
import 'package:supy_scanner/supy_scanner.dart';

void main() {
  group('SupyDocumentPage', () {
    test('equality', () {
      const a = SupyDocumentPage(uri: 'file:///a.jpg', width: 100, height: 200);
      const b = SupyDocumentPage(uri: 'file:///a.jpg', width: 100, height: 200);
      const c = SupyDocumentPage(uri: 'file:///b.jpg', width: 100, height: 200);
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });

    test('fromMap', () {
      final p = SupyDocumentPage.fromMap(<Object?, Object?>{
        'uri': 'file:///page.jpg',
        'width': 1280,
        'height': 1920,
      });
      expect(p.uri, 'file:///page.jpg');
      expect(p.width, 1280);
      expect(p.height, 1920);
    });
  });

  group('SupyDocumentData', () {
    test('fromMap with pages and ocr', () {
      final data = SupyDocumentData.fromMap(<Object?, Object?>{
        'pages': <Object?>[
          <Object?, Object?>{
            'uri': 'file:///p1.jpg',
            'width': 800,
            'height': 1200,
          },
          <Object?, Object?>{
            'uri': 'file:///p2.jpg',
            'width': 800,
            'height': 1200,
          },
        ],
        'ocrText': 'hello world',
      });
      expect(data.pages, hasLength(2));
      expect(data.ocrText, 'hello world');
    });

    test('fromMap without ocrText defaults to empty', () {
      final data = SupyDocumentData.fromMap(<Object?, Object?>{
        'pages': <Object?>[],
      });
      expect(data.ocrText, isEmpty);
      expect(data.pages, isEmpty);
    });

    test('equality across page lists', () {
      const page = SupyDocumentPage(
        uri: 'file:///p.jpg',
        width: 100,
        height: 100,
      );
      final a = SupyDocumentData(pages: const [page], ocrText: 'x');
      final b = SupyDocumentData(pages: const [page], ocrText: 'x');
      final c = SupyDocumentData(pages: const [page], ocrText: 'y');
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });
}
