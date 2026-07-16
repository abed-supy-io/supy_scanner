# Contributing to supy_scanner

Thanks for working on the Supy scanner package. This guide is the human-facing complement to `CLAUDE.md` (which targets AI assistants).

## Before you start

1. Read `docs/PLAN.md` and `docs/ARCHITECTURE.md`. Most "should I do X?" questions are answered there.
2. Check `TODO.md` for the active sprint. If your work doesn't map to an open ticket, raise it with the mobile lead before coding.
3. The drop-in compatibility constraint is the most important rule: changes that force retailer to rename props or change return types need explicit sign-off.

## Local setup

```bash
# 1. Flutter SDK >= 3.22
flutter --version

# 2. Install deps
flutter pub get
cd example && flutter pub get && cd ..

# 3. Run the example app
cd example
flutter run                    # whichever device is connected
flutter run -d <android-id>
flutter run -d <ios-sim-id>
```

iOS: open `example/ios/Runner.xcworkspace` once in Xcode to let CocoaPods finish setup. Camera does not work in the simulator — you need a physical device for real scans.

Android: `minSdk 24` (CameraX requirement). The first document scan downloads the GMS model (~10 MB); allow network on first run.

## Code style

- Run before pushing:
  ```bash
  dart format .
  dart analyze
  dart test
  ```
- CI runs all three. PRs with analyzer warnings won't merge.
- Public Dart APIs get full dartdoc; internals get one-line comments only when the *why* is non-obvious.
- See `analysis_options.yaml` for the enforced lint rules.

## PR checklist

Copy this into the PR description:

```
## Scope
- [ ] Maps to TODO.md ticket: S?-??
- [ ] Does NOT change the public Dart API in a way that breaks drop-in compat with Scanbot
  (if it does, link the decision in TODO.md)

## Implementation
- [ ] Dart side: types in `lib/src/models/`, channel calls in `lib/src/channel/`
- [ ] Android side: under `android/src/main/kotlin/io/supy/scanner/`
- [ ] iOS side: under `ios/Classes/`
- [ ] No `print`/`debugPrint` left in non-test code

## Tests
- [ ] Unit tests added (or N/A — explain)
- [ ] Example app exercises the new code path
- [ ] Walked the relevant scenarios in `docs/QA.md` on Android + iOS

## Docs
- [ ] `docs/ARCHITECTURE.md` updated if channel surface changed
- [ ] `docs/SYMBOLOGIES.md` updated if format support changed
- [ ] `docs/MIGRATION.md` updated if public Dart API changed
- [ ] `TODO.md` ticket checked off
```

## Common how-tos

### Add a new barcode symbology

1. Add the enum value to `lib/src/models/supy_barcode_format.dart`.
2. Add the row to `docs/SYMBOLOGIES.md` (canonical name → iOS / Android mapping).
3. Add the Android mapping in `android/.../barcode/FormatMapper.kt`.
4. Add the iOS mapping in `ios/Classes/barcode/SymbologyMapper.swift`.
5. Add a fixture in the example app's symbology screen with a real printed barcode.
6. Test on at least one Android and one iPhone.

### Add a new MethodChannel method

1. Add the row to the contract table in `docs/ARCHITECTURE.md` (method name, args, returns, errors).
2. Add the Dart wrapper in `lib/src/channel/method_channel.dart`.
3. Implement in both `SupyScannerPlugin.kt` and `SupyScannerPlugin.swift`.
4. Add a mocked unit test using `setMockMethodCallHandler`.
5. Surface it in the example app if user-visible.

### Cut a release

1. Verify all tickets for the target version are checked in `TODO.md`.
2. Walk every scenario in `docs/QA.md` on both Android and iPhone. Record results.
3. Update `CHANGELOG.md` (Keep-a-Changelog format).
4. Bump `version:` in `pubspec.yaml`.
5. Tag: `git tag v1.0.0 && git push --tags`.
6. Publish to the internal pub server (or pin the commit SHA in retailer for now).

## Things we don't do

- We don't take a paid SDK dependency. The whole point of this package is to remove Scanbot's licensing cost.
- We don't make network calls on the scanning path. On-device only.
- We don't widen scope mid-sprint. New ideas go to `TODO.md` under a future phase.
- We don't commit license keys, API tokens, `.env` files, or any other secret. PRs with secrets get force-rejected.

## Getting help

- Architecture / channel design — `docs/ARCHITECTURE.md`, then ask in `#mobile-eng`.
- Symbology questions — `docs/SYMBOLOGIES.md`, then ask in `#mobile-eng`.
- Process / sprint scope — `docs/HISTORY.md` (archived v1.0 sprint plan), then ask the mobile lead.
