---
name: add-channel-method
description: Use when adding a new MethodChannel method to the supy_scanner native bridge — ensures the contract doc, Dart wrapper, both native handlers, and a mocked test all land in the same PR.
---

# Add a MethodChannel method

The channel name is **versioned**: `io.supy.scanner/v1`. Adding a method does **not** bump the version. Renaming or changing semantics of an existing method does — that means a parallel `v2` channel, not a breaking change to `v1`.

## Checklist (create TodoWrite items for each)

1. **Contract doc** — add a row to the contract table in `docs/ARCHITECTURE.md` under the appropriate channel section (global `v1`, per-view, or EventChannel). Fields: method, args, returns, errors.

2. **Dart wrapper** — add the method to `lib/src/channel/supy_scanner_channel.dart` (the `SupyScannerChannel` class; per-view methods go on the matching controller in `lib/src/widgets/`). Type the args and return value strictly — no `dynamic` leaking past this file. Translate `PlatformException` to a `SupyScanError` with one of the codes from the error model table.

3. **Android handler** — `android/src/main/kotlin/io/supy/scanner/SupyScannerPlugin.kt` (or the per-view plugin if scoped). Handle the new method name in `onMethodCall`. Return on the main thread via `result.success(...)`.

4. **iOS handler** — `ios/Classes/SupyScannerPlugin.swift` (or per-view). Match the method name. Use `DispatchQueue.global(qos: .userInitiated)` for any work that touches the camera or Vision; hop to `.main` only at the `result(...)` callback.

5. **Mocked Dart test** — `test/channel/supy_scanner_channel_test.dart`. Use `TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler` to assert the exact arg shape and that the return value is parsed correctly.

6. **Example app exposure** — if the method is user-facing, add a button or option in the example app demonstrating it.

## Threading rules to enforce

- Detection / analyzer callbacks: background thread.
- Channel `result.success` callback: main thread (Flutter requirement).
- File I/O (JPEG writes): background.
- Camera session start/stop: background (especially on iOS).

## Don't

- Don't accept untyped `Map<String, dynamic>` args at the Dart boundary. Define a typed args class in `lib/src/channel/` if the method takes more than 2 args.
- Don't add a method that's not in `docs/ARCHITECTURE.md`. Spec first, code second.
- Don't introduce an error code outside the canonical set without adding it to the error model table.
