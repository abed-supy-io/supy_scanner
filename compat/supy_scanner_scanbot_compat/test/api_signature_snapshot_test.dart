// Snapshot-pins the public API surface of the compat shim. If the parsed
// signature listing of `lib/src/*.dart` ever differs from the checked-in
// `api_snapshot.txt`, this test fails — forcing the PR author to either
// revert the change or regenerate the snapshot deliberately:
//
//   dart tool/regen_api_snapshot.dart
//
// `dart:mirrors` is unavailable in the Flutter test runtime, so the test
// reproduces the same regex-based extraction that the regen tool uses.
//
// Note: the extractor is intentionally simple, not a Dart parser. It will
// surface a few stable-but-mildly-noisy entries (e.g. function-typed
// fields rendered as `method Function(...) -> final ...`). That noise is
// deterministic — drift is what the test catches.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('compat shim public API matches checked-in snapshot', () {
    final pkgRoot = _findPkgRoot();
    final result = _renderSnapshot(pkgRoot);
    final expected =
        File('$pkgRoot/test/api_snapshot.txt').readAsStringSync();
    if (result != expected) {
      fail(
        'compat shim API drifted from test/api_snapshot.txt.\n'
        'If the change is intentional:\n'
        '  cd compat/supy_scanner_scanbot_compat && '
        'dart tool/regen_api_snapshot.dart\n'
        'and include the regenerated snapshot + a justification in the PR.\n\n'
        '--- expected ---\n$expected\n'
        '--- actual ---\n$result',
      );
    }
  });
}

String _renderSnapshot(String pkgRoot) {
  final srcDir = Directory('$pkgRoot/lib/src');
  final files = srcDir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  final out = StringBuffer();
  out.writeln('# supy_scanner_scanbot_compat API snapshot');
  out.writeln('# Regenerate with: dart tool/regen_api_snapshot.dart');
  out.writeln('# Format: one symbol per line, sorted within file.');
  out.writeln();
  for (final f in files) {
    final rel = f.path.substring(pkgRoot.length + 1);
    out.writeln('## $rel');
    for (final s in _extractSymbols(f.readAsStringSync())) {
      out.writeln(s);
    }
    out.writeln();
  }
  return out.toString();
}

// Below this point: identical to tool/regen_api_snapshot.dart's extractor.
// Keep them in sync — see CLAUDE.md "channel name versioned" discipline; this
// is the same idea applied to the compat surface.

List<String> _extractSymbols(String src) {
  final stripped = src
      .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
      .replaceAll(RegExp(r'//.*'), '');
  final out = <String>[];
  int i = 0;
  while (i < stripped.length) {
    final classMatch =
        RegExp(r'(?:abstract\s+)?class\s+(\w+)[^{]*\{').matchAsPrefix(
      stripped,
      i,
    );
    if (classMatch == null) {
      final next = stripped.indexOf('class ', i + 1);
      if (next < 0) break;
      i = next;
      continue;
    }
    final className = classMatch.group(1)!;
    final bodyStart = classMatch.end;
    final bodyEnd = _matchingBrace(stripped, bodyStart - 1);
    if (bodyEnd < 0) break;
    if (!className.startsWith('_')) {
      out.add('class $className');
      out.addAll(
          _scanClassBody(className, stripped.substring(bodyStart, bodyEnd)));
    }
    i = bodyEnd + 1;
  }
  out.sort();
  final seen = <String>{};
  return [for (final x in out) if (seen.add(x)) x];
}

List<String> _scanClassBody(String className, String body) {
  final out = <String>[];
  final buf = StringBuffer();
  int depth = 0;
  int parens = 0;
  for (var k = 0; k < body.length; k++) {
    final c = body[k];
    if (c == '{' && parens == 0) {
      depth++;
      if (depth == 1) {
        _emitMember(className, buf.toString(), out);
        buf.clear();
      }
      continue;
    }
    if (c == '}' && parens == 0) {
      if (depth > 0) depth--;
      continue;
    }
    if (depth == 0) {
      if (c == '(') parens++;
      else if (c == ')') parens--;
      if (c == ';' && parens == 0) {
        buf.write(c);
        _emitMember(className, buf.toString(), out);
        buf.clear();
        continue;
      }
      buf.write(c);
    }
  }
  if (buf.toString().trim().isNotEmpty) {
    _emitMember(className, buf.toString(), out);
  }
  return out;
}

void _emitMember(String className, String raw, List<String> out) {
  final line = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (line.isEmpty) return;
  if (line.startsWith('@')) return;
  var s = line;
  s = s.replaceAll(RegExp(r'@\w+(?:\([^)]*\))?\s*'), '');
  s = s.replaceFirst(RegExp(r'^(?:static\s+|external\s+|covariant\s+)+'), '');
  if (s.contains(' operator ')) return;
  final ctorRe = RegExp(
    r'^(?:const\s+|factory\s+)?' +
        RegExp.escape(className) +
        r'(?:\.(\w+))?\s*\(([^)]*)\)',
  );
  final ctorMatch = ctorRe.firstMatch(s);
  if (ctorMatch != null) {
    final name = ctorMatch.group(1);
    final params = ctorMatch.group(2)!.trim();
    final label = name == null ? className : '$className.$name';
    if (name == null || !name.startsWith('_')) {
      out.add('ctor $label($params)');
    }
    return;
  }
  final getterRe = RegExp(r'^([\w<>?,\s]+?)\s+get\s+(\w+)\b');
  final getterMatch = getterRe.firstMatch(s);
  if (getterMatch != null) {
    final name = getterMatch.group(2)!;
    final ret = getterMatch.group(1)!.trim();
    if (!name.startsWith('_')) out.add('getter $name -> $ret');
    return;
  }
  final methodRe = RegExp(r'^([\w<>?,\s]+?)\s+(\w+)\s*\((.*)\)');
  final methodMatch = methodRe.firstMatch(s);
  if (methodMatch != null) {
    final name = methodMatch.group(2)!;
    if (!name.startsWith('_') &&
        !const {'if', 'for', 'while', 'switch', 'return'}.contains(name)) {
      final ret = methodMatch.group(1)!.trim();
      final params = methodMatch.group(3)!.trim();
      out.add('method $name($params) -> $ret');
    }
    return;
  }
  final fieldRe = RegExp(
    r'^(?:(final|late\s+final|late|const)\s+)?([\w<>?,\s]+?)\s+(\w+)\s*[=;]',
  );
  final fieldMatch = fieldRe.firstMatch(s);
  if (fieldMatch != null) {
    final name = fieldMatch.group(3)!;
    if (!name.startsWith('_')) {
      final type = fieldMatch.group(2)!.trim();
      out.add('field $name : $type');
    }
  }
}

int _matchingBrace(String s, int openIdx) {
  var depth = 0;
  for (var k = openIdx; k < s.length; k++) {
    final c = s[k];
    if (c == '{') depth++;
    else if (c == '}') {
      depth--;
      if (depth == 0) return k;
    }
  }
  return -1;
}

String _findPkgRoot() {
  Directory d = Directory.current;
  for (var i = 0; i < 5; i++) {
    final pubspec = File('${d.path}/pubspec.yaml');
    if (pubspec.existsSync() &&
        pubspec
            .readAsStringSync()
            .contains('name: supy_scanner_scanbot_compat\n')) {
      return d.path;
    }
    final parent = d.parent;
    if (parent.path == d.path) break;
    d = parent;
  }
  throw StateError('package root not found from ${Directory.current.path}');
}
