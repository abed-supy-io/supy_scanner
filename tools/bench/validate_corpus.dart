// Validates bench/corpus against the schema in bench/corpus/README.md.
//
// Usage: dart tools/bench/validate_corpus.dart [--corpus <dir>]
// Exit codes: 0 valid, 1 validation errors, 2 corpus dir missing/empty.
import 'dart:io';

import 'lib/corpus.dart';

void main(List<String> argv) {
  var corpusPath = 'bench/corpus';
  for (var i = 0; i < argv.length; i++) {
    if (argv[i] == '--corpus' && i + 1 < argv.length) corpusPath = argv[++i];
  }
  final root = Directory(corpusPath);
  if (!root.existsSync()) {
    stderr.writeln('[validate_corpus] no corpus at $corpusPath');
    exit(2);
  }
  final scenes = loadCorpus(root);
  if (scenes.isEmpty) {
    stderr.writeln('[validate_corpus] no scenes found in $corpusPath');
    exit(2);
  }
  final errors = validateCorpus(scenes);
  for (final e in errors) {
    stderr.writeln('[validate_corpus] $e');
  }
  final byLighting = <String, int>{};
  for (final s in scenes) {
    byLighting[s.lighting] = (byLighting[s.lighting] ?? 0) + 1;
  }
  stdout.writeln('[validate_corpus] ${scenes.length} scenes, '
      'by lighting: $byLighting, errors: ${errors.length}');
  exit(errors.isEmpty ? 0 : 1);
}
