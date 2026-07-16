// Regenerates `test/api_snapshot.txt` — a deterministic listing of the
// compat shim's public API surface. Run from the package root:
//
//   dart tool/regen_api_snapshot.dart
//
// Intentionally analyzer-free: parses `lib/src/*.dart` with regex so the
// snapshot script is dependency-light and runs the same on any Dart SDK
// the package supports. Captured surface:
//
//   - Each top-level public class declared in lib/src/*.dart
//   - Each public constructor of those classes (named + positional params,
//     with `required` markers and default-value presence flags)
//   - Each public instance member (field/getter/method) — signatures
//     normalized to `<name>(<params>) -> <return>` for fields/getters or
//     `<name>(<params>) -> <return>` for methods.
//
// The retailer-app pin contract: if any signature in this snapshot moves,
// the PR author must regenerate the snapshot, justify the move in the PR
// description, and re-verify retailer/compile against the new shape.

import 'dart:io';

Future<void> main(List<String> argv) async {
  final root = _pkgRoot();
  final srcDir = Directory('${root.path}/lib/src');
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
    final rel = f.path.substring(root.path.length + 1);
    out.writeln('## $rel');
    final symbols = _extractSymbols(f.readAsStringSync());
    for (final s in symbols) {
      out.writeln(s);
    }
    out.writeln();
  }

  final snapshotPath = '${root.path}/test/api_snapshot.txt';
  await File(snapshotPath).writeAsString(out.toString());
  stdout.writeln('wrote $snapshotPath');
}

List<String> _extractSymbols(String src) {
  // Strip line comments and block comments first so doc text doesn't show
  // up as fake declarations.
  final stripped = src
      .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
      .replaceAll(RegExp(r'//.*'), '');

  final out = <String>[];

  // Walk top-level: capture each `class Name { ... }` block by matching
  // braces, then scan only the first level inside each class body. This
  // avoids picking up expression-level identifiers (e.g. `Scaffold(...)`
  // inside `build()`) which a naive multiline regex would otherwise grab.
  var i = 0;
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
      out.addAll(_scanClassBody(
        className,
        stripped.substring(bodyStart, bodyEnd),
      ));
    }
    i = bodyEnd + 1;
  }

  out.sort();
  return _dedupe(out);
}

List<String> _scanClassBody(String className, String body) {
  // Walk the immediate body only — skip nested braces (method bodies,
  // function expressions, collection literals).
  final out = <String>[];
  final buf = StringBuffer();
  var depth = 0;
  var parens = 0;
  for (var k = 0; k < body.length; k++) {
    final c = body[k];
    // Braces are only block scope when not inside a parameter list — `{` inside
    // `(...)` marks named parameters, not a method body.
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
      if (c == '(') {
        parens++;
      } else if (c == ')') {
        parens--;
      }
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
  if (line.startsWith('@')) return; // bare annotation

  // Strip leading annotations and modifiers we don't care about.
  var s = line;
  s = s.replaceAll(RegExp(r'@\w+(?:\([^)]*\))?\s*'), '');
  s = s.replaceFirst(RegExp(r'^(?:static\s+|external\s+|covariant\s+)+'), '');

  // Skip operator overloads (deterministic but noisy).
  if (s.contains(' operator ')) return;

  // Constructor: starts with the class name (possibly with `const`/factory).
  final ctorRe = RegExp(
    r'^(?:const\s+|factory\s+)?' + RegExp.escape(className) +
    r'(?:\.(\w+))?\s*\(([^)]*)\)',
  );
  final ctorMatch = ctorRe.firstMatch(s);
  if (ctorMatch != null) {
    final name = ctorMatch.group(1);
    final params = ctorMatch.group(2)!.trim();
    final label =
        name == null ? className : '$className.$name';
    if (name == null || !name.startsWith('_')) {
      out.add('ctor $label($params)');
    }
    return;
  }

  // Getter: `<Type> get <name>`.
  final getterRe = RegExp(r'^([\w<>?,\s]+?)\s+get\s+(\w+)\b');
  final getterMatch = getterRe.firstMatch(s);
  if (getterMatch != null) {
    final name = getterMatch.group(2)!;
    final ret = getterMatch.group(1)!.trim();
    if (!name.startsWith('_')) out.add('getter $name -> $ret');
    return;
  }

  // Method: `<Return> <name>(<params>)`. Match nested parens for named-param
  // groups like `bind({required ValueNotifier<bool> pausedNotifier, ...})`.
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

  // Field: `final <Type> <name>` or `<Type> <name>`.
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
    if (c == '{') {
      depth++;
    } else if (c == '}') {
      depth--;
      if (depth == 0) return k;
    }
  }
  return -1;
}

List<String> _dedupe(List<String> xs) {
  final seen = <String>{};
  return [for (final x in xs) if (seen.add(x)) x];
}

Directory _pkgRoot() {
  var d = Directory.current;
  for (var i = 0; i < 5; i++) {
    if (File('${d.path}/pubspec.yaml').existsSync() &&
        File('${d.path}/pubspec.yaml')
            .readAsStringSync()
            .contains('name: supy_scanner_scanbot_compat\n')) {
      return d;
    }
    final parent = d.parent;
    if (parent.path == d.path) break;
    d = parent;
  }
  throw StateError(
      'run from compat/supy_scanner_scanbot_compat/ or descendants');
}
