// Shared error type + subprocess-output parsing for the bench driver.
// Exit-code contract (see run_bench.dart): 0 clean, 1 gate regression,
// 2 harness/infra error. HarnessException is how every failure inside the
// run path (subprocess launch, malformed subprocess output, unreadable
// corpus frame) is surfaced to main() so it can be turned into a clean
// exit(2) instead of an uncaught-exception stack trace + exit 255.
import 'dart:convert';

/// A harness/infra failure that should map to exit code 2. Never let a raw
/// [ProcessException] or [FormatException] escape a run-path call site —
/// wrap it in this instead so main()'s top-level catch can report it
/// cleanly and the scratch-dir `finally` still runs.
class HarnessException implements Exception {
  HarnessException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Extracts and decodes the `$tag {...}` JSON payload line from harness
/// stdout [output]. Throws [HarnessException] — never a raw
/// [FormatException] — if the tag line is missing or its JSON is malformed.
Map<String, Object?> parseJsonLine(String output, String tag) {
  for (final line in const LineSplitter().convert(output)) {
    final idx = line.indexOf('$tag ');
    if (idx < 0) continue;
    final start = line.indexOf('{', idx);
    if (start < 0) continue;
    try {
      return jsonDecode(line.substring(start)) as Map<String, Object?>;
    } on FormatException catch (e) {
      throw HarnessException(
          '[bench] malformed $tag JSON in harness output: $e\nline: $line');
    }
  }
  throw HarnessException('[bench] no $tag line in harness output:\n$output');
}
