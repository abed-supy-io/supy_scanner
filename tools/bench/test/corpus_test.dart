import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'package:supy_bench/corpus.dart';

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('corpus_test'));
  tearDown(() => tmp.deleteSync(recursive: true));

  Directory writeScene(
    String id,
    Map<String, Object?> json, {
    bool withFrame = true,
  }) {
    final dir = Directory('${tmp.path}/$id')..createSync(recursive: true);
    File('${dir.path}/scene.json').writeAsStringSync(jsonEncode(json));
    if (withFrame) {
      // Content irrelevant for the loader; existence is what's validated.
      File('${dir.path}/frame.png').writeAsBytesSync([0x89, 0x50, 0x4E, 0x47]);
    }
    return dir;
  }

  Map<String, Object?> goodJson(String id) => {
        'id': id,
        'docType': 'receipt',
        'background': 'plain',
        'lighting': 'good',
        'quad': [0.2, 0.2, 0.8, 0.2, 0.8, 0.8, 0.2, 0.8],
        'physicalWidthMm': 80.0,
        'physicalHeightMm': 60.0,
      };

  test('loadCorpus loads scenes sorted by id', () {
    writeScene('b-002', goodJson('b-002'));
    writeScene('a-001', goodJson('a-001'));
    final scenes = loadCorpus(tmp);
    expect(scenes.map((s) => s.id).toList(), ['a-001', 'b-002']);
    expect(scenes.first.quad, hasLength(8));
    expect(scenes.first.category, 'receipt/plain/good');
    expect(scenes.first.physicalWidthMm, 80.0);
  });

  test('a valid scene has no validation errors', () {
    writeScene('a-001', goodJson('a-001'));
    final errors = validateCorpus(loadCorpus(tmp));
    expect(errors, isEmpty);
  });

  test('quad may be null (negative scene: no document in frame)', () {
    final j = goodJson('a-001')..['quad'] = null;
    writeScene('a-001', j);
    expect(validateCorpus(loadCorpus(tmp)), isEmpty);
  });

  test('rejects id/dir mismatch, bad category, bad quad, missing frame', () {
    writeScene('a-001', goodJson('WRONG'));
    writeScene('a-002', goodJson('a-002')..['docType'] = 'poster');
    writeScene('a-003', goodJson('a-003')..['quad'] = [0.2, 0.2, 1.5, 0.2]);
    writeScene('a-004', goodJson('a-004'), withFrame: false);
    final j5 = goodJson('a-005')..remove('physicalHeightMm');
    writeScene('a-005', j5);

    final errors = validateCorpus(loadCorpus(tmp));
    expect(errors, hasLength(5));
    expect(errors.join('\n'), contains('a-001'));
    expect(errors.join('\n'), contains('docType'));
    expect(errors.join('\n'), contains('quad'));
    expect(errors.join('\n'), contains('frame.png'));
    expect(errors.join('\n'), contains('physical'));
  });
}
