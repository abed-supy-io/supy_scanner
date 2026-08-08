// Property-based fuzz at the Dart channel decode boundary.
//
// H2-03 in `TODO.md`. Pumps 10,000 deterministically-generated payloads
// through every `fromMap` decoder and the `SupyScanErrorCode.fromWire`
// mapper. Two invariants under test:
//
//   1. Well-formed payloads decode without throwing and the result reads
//      back the values that were put in.
//   2. Malformed payloads either decode (graceful) or throw exactly one
//      of an allow-listed exception type — `TypeError` / `CastError` /
//      `ArgumentError` / `SupyScanError`. Anything else (StateError,
//      RangeError, NoSuchMethodError, hangs, isolate crashes) is a
//      regression: the boundary must fail loudly and predictably.
//
// Seed is fixed (`_kSeed`) so a CI failure reproduces locally.

import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supy_scanner/supy_scanner.dart';

import '../support/license_test_support.dart';

const int _kSeed = 0xDEC0DE;
const int _kHappyDocumentIterations = 3000;
const int _kHappyBarcodeIterations = 3000;
const int _kHappyBatchIterations = 1500;
const int _kMalformedIterations = 2000;
const int _kErrorCodeIterations = 500;
// Total: 10,000 frames.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(activateTestLicense);
  tearDown(clearTestLicense);

  group('fuzz — well-formed payloads round-trip', () {
    test('SupyDocumentPage.fromMap (${_kHappyDocumentIterations}x)', () {
      final rand = Random(_kSeed);
      for (var i = 0; i < _kHappyDocumentIterations; i++) {
        final spec = _PageSpec.random(rand);
        final page = SupyDocumentPage.fromMap(spec.toMap());
        expect(page.uri, spec.uri, reason: 'iter $i');
        expect(page.width, spec.width, reason: 'iter $i');
        expect(page.height, spec.height, reason: 'iter $i');
        expect(page.quality, spec.quality, reason: 'iter $i');
        expect(page.qualityScore, spec.qualityScore, reason: 'iter $i');
      }
    });

    test('SupyDocumentData.fromMap (1000x, nested pages)', () {
      final rand = Random(_kSeed ^ 0x1);
      for (var i = 0; i < 1000; i++) {
        final pageCount = rand.nextInt(5); // 0..4
        final pages = List.generate(pageCount, (_) => _PageSpec.random(rand));
        final ocrText = _randomString(rand, rand.nextInt(64));
        final pdfUri =
            rand.nextBool() ? 'file:///${_randomString(rand, 8)}.pdf' : null;
        final map = <Object?, Object?>{
          'pages': pages.map((p) => p.toMap()).toList(),
          'ocrText': ocrText,
          if (pdfUri != null) 'pdfUri': pdfUri,
        };
        final data = SupyDocumentData.fromMap(map);
        expect(data.pages, hasLength(pageCount), reason: 'iter $i');
        expect(data.ocrText, ocrText, reason: 'iter $i');
        expect(data.pdfUri, pdfUri, reason: 'iter $i');
      }
    });

    test('SupyBarcode.fromMap (${_kHappyBarcodeIterations}x)', () {
      final rand = Random(_kSeed ^ 0x2);
      for (var i = 0; i < _kHappyBarcodeIterations; i++) {
        final spec = _BarcodeSpec.random(rand);
        final barcode = SupyBarcode.fromMap(spec.toMap());
        expect(barcode.rawValue, spec.rawValue, reason: 'iter $i');
        expect(barcode.format, spec.format, reason: 'iter $i');
        if (spec.hasBox) {
          expect(barcode.boundingBox, isNotNull, reason: 'iter $i');
          expect(barcode.boundingBox!.left, closeTo(spec.boxLeft, 1e-9));
          expect(barcode.boundingBox!.top, closeTo(spec.boxTop, 1e-9));
          expect(barcode.boundingBox!.width, closeTo(spec.boxWidth, 1e-9));
          expect(barcode.boundingBox!.height, closeTo(spec.boxHeight, 1e-9));
        } else {
          expect(barcode.boundingBox, isNull, reason: 'iter $i');
        }
      }
    });

    test('SupyBatchBarcodeResult.fromMap (${_kHappyBatchIterations}x)', () {
      final rand = Random(_kSeed ^ 0x3);
      for (var i = 0; i < _kHappyBatchIterations; i++) {
        final itemCount = rand.nextInt(10); // 0..9
        final specs = List.generate(
          itemCount,
          (_) => _BarcodeSpec.random(rand),
        );
        final duplicates = rand.nextInt(1000);
        final map = <Object?, Object?>{
          'items': specs.map((s) => s.toMap()).toList(),
          'duplicateCount': duplicates,
        };
        final result = SupyBatchBarcodeResult.fromMap(map);
        expect(result.items, hasLength(itemCount), reason: 'iter $i');
        expect(result.duplicateCount, duplicates, reason: 'iter $i');
      }
    });
  });

  group('fuzz — malformed payloads fail predictably', () {
    test('SupyDocumentPage.fromMap ($_kMalformedIterations mutations)', () {
      final rand = Random(_kSeed ^ 0x10);
      for (var i = 0; i < _kMalformedIterations; i++) {
        final base = _PageSpec.random(rand).toMap();
        final mutated = _mutate(rand, base);
        _expectAllowedFailureOrSuccess(
          () => SupyDocumentPage.fromMap(mutated),
          context: 'page iter $i mutated=$mutated',
        );
      }
    });

    test('SupyBarcode.fromMap ($_kMalformedIterations mutations)', () {
      final rand = Random(_kSeed ^ 0x11);
      for (var i = 0; i < _kMalformedIterations; i++) {
        final base = _BarcodeSpec.random(rand).toMap();
        final mutated = _mutate(rand, base);
        _expectAllowedFailureOrSuccess(
          () => SupyBarcode.fromMap(mutated),
          context: 'barcode iter $i mutated=$mutated',
        );
      }
    });

    test('SupyBatchBarcodeResult.fromMap absorbs junk items', () {
      // The batch decoder is lenient (whereType<Map>) — junk in `items`
      // is filtered, not thrown. Pin that property explicitly so we don't
      // accidentally tighten it and break the live batch stream.
      final rand = Random(_kSeed ^ 0x12);
      for (var i = 0; i < 500; i++) {
        final junk = <Object?>[
          if (rand.nextBool()) 'not-a-map',
          if (rand.nextBool()) 42,
          if (rand.nextBool()) <Object?>[1, 2, 3],
          if (rand.nextBool()) null,
          if (rand.nextBool()) _BarcodeSpec.random(rand).toMap(),
        ];
        final map = <Object?, Object?>{
          'items': junk,
          'duplicateCount': rand.nextBool() ? rand.nextInt(100) : null,
        };
        final result = SupyBatchBarcodeResult.fromMap(map);
        // Should never throw; valid items pass through, junk drops.
        final validCount = junk.whereType<Map<Object?, Object?>>().length;
        expect(result.items, hasLength(validCount), reason: 'iter $i');
        expect(result.duplicateCount, isNonNegative, reason: 'iter $i');
      }
    });
  });

  group('fuzz — SupyScanErrorCode.fromWire never throws', () {
    test('$_kErrorCodeIterations random strings + nulls', () {
      final rand = Random(_kSeed ^ 0x20);
      const known = <String>{
        'cancelled',
        'permission_denied',
        'camera_unavailable',
        'model_unavailable',
        'format_unsupported',
      };
      for (var i = 0; i < _kErrorCodeIterations; i++) {
        final wire =
            rand.nextInt(10) == 0
                ? null
                : _randomString(rand, rand.nextInt(24));
        final code = SupyScanErrorCode.fromWire(wire);
        if (wire != null && known.contains(wire)) {
          expect(
            code,
            isNot(SupyScanErrorCode.unknown),
            reason: 'iter $i wire=$wire',
          );
        } else {
          expect(code, SupyScanErrorCode.unknown, reason: 'iter $i wire=$wire');
        }
      }
    });
  });

  group('fuzz — channel round-trip', () {
    const channel = MethodChannel('io.supy.scanner/v1');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final channelUnderTest = SupyScannerChannel.test(channel);

    tearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
    });

    test('scanDocument with 500 random well-formed payloads', () async {
      final rand = Random(_kSeed ^ 0x30);
      for (var i = 0; i < 500; i++) {
        final pageCount = rand.nextInt(4);
        final pages = List.generate(pageCount, (_) => _PageSpec.random(rand));
        final payload = <Object?, Object?>{
          'pages': pages.map((p) => p.toMap()).toList(),
          'ocrText': _randomString(rand, rand.nextInt(20)),
        };
        messenger.setMockMethodCallHandler(channel, (_) async => payload);
        final result = await channelUnderTest.scanDocument(
          const SupyDocumentScanOptions(),
        );
        expect(result, isNotNull, reason: 'iter $i');
        expect(result!.pages, hasLength(pageCount), reason: 'iter $i');
      }
    });

    test(
      'PlatformException with random codes always becomes SupyScanError',
      () async {
        final rand = Random(_kSeed ^ 0x31);
        for (var i = 0; i < 100; i++) {
          final code = _randomString(rand, rand.nextInt(16));
          messenger.setMockMethodCallHandler(channel, (_) async {
            throw PlatformException(code: code, message: 'fuzz');
          });
          await expectLater(
            channelUnderTest.scanDocument(const SupyDocumentScanOptions()),
            throwsA(isA<SupyScanError>()),
            reason: 'iter $i code=$code',
          );
        }
      },
    );
  });
}

// -----------------------------------------------------------------------------
// Generators
// -----------------------------------------------------------------------------

class _PageSpec {
  _PageSpec({
    required this.uri,
    required this.width,
    required this.height,
    required this.quality,
    required this.qualityScore,
  });

  factory _PageSpec.random(Random rand) {
    final qualityIndex = rand.nextInt(
      SupyDocumentPageQuality.values.length + 1,
    );
    final quality =
        qualityIndex == SupyDocumentPageQuality.values.length
            ? null
            : SupyDocumentPageQuality.values[qualityIndex];
    return _PageSpec(
      uri: 'file:///${_randomString(rand, 1 + rand.nextInt(12))}.jpg',
      width: 1 + rand.nextInt(8192),
      height: 1 + rand.nextInt(8192),
      quality: quality,
      qualityScore: rand.nextBool() ? rand.nextDouble() : null,
    );
  }

  final String uri;
  final int width;
  final int height;
  final SupyDocumentPageQuality? quality;
  final double? qualityScore;

  Map<Object?, Object?> toMap() => <Object?, Object?>{
    'uri': uri,
    'width': width,
    'height': height,
    if (quality != null) 'quality': quality!.name,
    if (qualityScore != null) 'qualityScore': qualityScore,
  };
}

class _BarcodeSpec {
  _BarcodeSpec({
    required this.rawValue,
    required this.format,
    required this.hasBox,
    required this.boxLeft,
    required this.boxTop,
    required this.boxWidth,
    required this.boxHeight,
  });

  factory _BarcodeSpec.random(Random rand) {
    final format =
        SupyBarcodeFormat.values[rand.nextInt(SupyBarcodeFormat.values.length)];
    final hasBox = rand.nextBool();
    return _BarcodeSpec(
      rawValue: _randomString(rand, 1 + rand.nextInt(40)),
      format: format,
      hasBox: hasBox,
      boxLeft: hasBox ? rand.nextDouble() : 0,
      boxTop: hasBox ? rand.nextDouble() : 0,
      boxWidth: hasBox ? rand.nextDouble() : 0,
      boxHeight: hasBox ? rand.nextDouble() : 0,
    );
  }

  final String rawValue;
  final SupyBarcodeFormat format;
  final bool hasBox;
  final double boxLeft;
  final double boxTop;
  final double boxWidth;
  final double boxHeight;

  Map<Object?, Object?> toMap() => <Object?, Object?>{
    'rawValue': rawValue,
    'format': format.wireName,
    if (hasBox)
      'boundingBox': <Object?, Object?>{
        'left': boxLeft,
        'top': boxTop,
        'width': boxWidth,
        'height': boxHeight,
      },
  };
}

// -----------------------------------------------------------------------------
// Mutation + assertion helpers
// -----------------------------------------------------------------------------

/// Returns a copy of [source] with one mutation applied (drop a key, swap a
/// value's type, replace with garbage). Drives malformed-payload fuzz.
Map<Object?, Object?> _mutate(Random rand, Map<Object?, Object?> source) {
  if (source.isEmpty) return source;
  final clone = Map<Object?, Object?>.from(source);
  final keys = clone.keys.toList();
  final pick = keys[rand.nextInt(keys.length)];
  switch (rand.nextInt(4)) {
    case 0:
      clone.remove(pick);
      break;
    case 1:
      clone[pick] = null;
      break;
    case 2:
      clone[pick] = _garbageValue(rand);
      break;
    case 3:
      // Add an extra junk key (decoders should ignore unknown keys).
      clone['__junk_${rand.nextInt(1 << 16)}'] = _garbageValue(rand);
      break;
  }
  return clone;
}

Object? _garbageValue(Random rand) {
  switch (rand.nextInt(6)) {
    case 0:
      return rand.nextInt(1 << 30);
    case 1:
      return rand.nextDouble();
    case 2:
      return _randomString(rand, rand.nextInt(8));
    case 3:
      return <Object?>[1, 'two', null];
    case 4:
      return <Object?, Object?>{'nested': true};
    case 5:
    default:
      return null;
  }
}

/// Asserts that `fn` either succeeds OR throws one of the allow-listed
/// failure modes. Anything outside the allow-list is a regression.
void _expectAllowedFailureOrSuccess(
  void Function() fn, {
  required String context,
}) {
  try {
    fn();
  } on TypeError {
    // Expected: `!` on a missing/null/wrong-type field, OR `as String` etc.
    // on the wrong runtime type (Dart folds CastError into TypeError as of
    // 2.12).
  } on ArgumentError {
    // Expected: `SupyBarcodeFormat.fromWireName` on an unknown enum name.
  } on SupyScanError {
    // Expected if a decoder ever escalates to a typed error.
  } catch (e, st) {
    fail('Unexpected exception ($context): ${e.runtimeType}: $e\n$st');
  }
}

String _randomString(Random rand, int length) {
  if (length == 0) return '';
  const alphabet =
      'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._/';
  final sb = StringBuffer();
  for (var i = 0; i < length; i++) {
    sb.write(alphabet[rand.nextInt(alphabet.length)]);
  }
  return sb.toString();
}
