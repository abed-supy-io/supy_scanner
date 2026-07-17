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
      final p = SupyDocumentPage.fromMap(const <Object?, Object?>{
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
      final data = SupyDocumentData.fromMap(const <Object?, Object?>{
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
      final data = SupyDocumentData.fromMap(const <Object?, Object?>{
        'pages': <Object?>[],
      });
      expect(data.ocrText, isEmpty);
      expect(data.pages, isEmpty);
    });

    test('pdfUri is null when omitted (v1.0 payload)', () {
      final data = SupyDocumentData.fromMap(const <Object?, Object?>{
        'pages': <Object?>[],
        'ocrText': '',
      });
      expect(data.pdfUri, isNull);
    });

    test('pdfUri round-trips from the channel map (v1.1 pdf output)', () {
      final data = SupyDocumentData.fromMap(const <Object?, Object?>{
        'pages': <Object?>[
          <Object?, Object?>{
            'uri': 'file:///p1.jpg',
            'width': 800,
            'height': 1200,
          },
        ],
        'ocrText': '',
        'pdfUri': 'file:///tmp/scan.pdf',
      });
      expect(data.pdfUri, 'file:///tmp/scan.pdf');
    });

    test('equality includes pdfUri', () {
      const page = SupyDocumentPage(uri: 'file:///p.jpg', width: 1, height: 1);
      const a = SupyDocumentData(
        pages: [page],
        ocrText: '',
        pdfUri: 'file:///a.pdf',
      );
      const b = SupyDocumentData(
        pages: [page],
        ocrText: '',
        pdfUri: 'file:///a.pdf',
      );
      const c = SupyDocumentData(
        pages: [page],
        ocrText: '',
        pdfUri: 'file:///b.pdf',
      );
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });

    test('resolvedBackend defaults to unknown when payload omits it', () {
      final data = SupyDocumentData.fromMap(const <Object?, Object?>{
        'pages': <Object?>[],
        'ocrText': '',
      });
      expect(data.resolvedBackend, SupyDocumentScannerBackend.unknown);
    });

    test('resolvedBackend round-trips gms and cameraX (v1.2 payload)', () {
      final gms = SupyDocumentData.fromMap(const <Object?, Object?>{
        'pages': <Object?>[],
        'ocrText': '',
        'resolvedBackend': 'gms',
      });
      final cameraX = SupyDocumentData.fromMap(const <Object?, Object?>{
        'pages': <Object?>[],
        'ocrText': '',
        'resolvedBackend': 'cameraX',
      });
      expect(gms.resolvedBackend, SupyDocumentScannerBackend.gms);
      expect(cameraX.resolvedBackend, SupyDocumentScannerBackend.cameraX);
    });

    test('equality across page lists', () {
      const page = SupyDocumentPage(
        uri: 'file:///p.jpg',
        width: 100,
        height: 100,
      );
      const a = SupyDocumentData(pages: [page], ocrText: 'x');
      const b = SupyDocumentData(pages: [page], ocrText: 'x');
      const c = SupyDocumentData(pages: [page], ocrText: 'y');
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });
}
