# CLAUDE.md — supy_scanner

Project-specific rules for Claude Code sessions working inside `/supy-scanner`. Read this first.

## What this repo is

A first-party Flutter scanning library that replaces Scanbot SDK in the Supy retailer mobile app. Native-backed: AVFoundation/Vision on iOS, ML Kit on Android. The non-negotiable product constraint is **drop-in API compatibility with the existing Scanbot call sites** — end users must see no difference after migration.

If a change you're about to make would force the retailer app to rename a prop, add a new required argument, or change a return type vs. the current Scanbot API, **stop and surface it** before writing code.

## Sources of truth (read these before non-trivial work)

| File | When to read |
|---|---|
| `docs/PLAN.md` | Before changing scope or phasing. |
| `docs/ARCHITECTURE.md` | Before adding a MethodChannel method, a new native class, or changing threading. |
| `docs/MIGRATION.md` | Before changing any public Dart type that retailer touches. |
| `docs/SYMBOLOGIES.md` | Before adding/changing a barcode format. |
| `docs/QA.md` | Before claiming a phase is done. |
| `TODO.md` | Live sprint progress. Check items off as work lands. |

## Conventions

### Dart
- Public types are prefixed `Supy*` (e.g. `SupyBarcode`, `SupyBarcodeScannerView`). No `Scanbot*`-named types in `lib/` — those belong in the `compat/` package.
- Use sealed classes for result variants. No `dynamic`, no `Map<String, dynamic>` leaking out of `lib/src/channel/`.
- Frozen value types: override `==`, `hashCode`, `toString`. Use `package:meta` `@immutable`.
- No `flutter_bloc` or other state-management deps in the library. The library exposes streams and `ChangeNotifier`; consumers wrap them.

### Native — Android (Kotlin)
- Package root: `io.supy.scanner`. Subpackages: `barcode/`, `document/`.
- Camera lifecycle uses `LifecycleCameraController` bound to the host `Activity` lifecycle — never `FragmentActivity` casts that crash on AppCompat-less hosts.
- All ML Kit calls go through a single client instance per `PlatformView`; close it in `dispose()`.
- Threading: detection runs on the analyzer thread; never block the main thread.

### Native — iOS (Swift)
- Module: `SupyScanner`. Files under `ios/Classes/{barcode,document}/`.
- `AVCaptureSession` start/stop on `DispatchQueue.global(qos: .userInitiated)` — never on `.main`.
- Deployment target is **iOS 16**. Don't add `if #available(iOS 17, *)` branches without a fallback path.
- All `VNRequest` work on a background `DispatchQueue`; results marshalled to main only at the FlutterResult boundary.

### Channel
- Channel name is **versioned**: `io.supy.scanner/v1`. Never bump silently — a v2 means a parallel surface, not a breaking change.
- Every method name and arg key is in the table in `docs/ARCHITECTURE.md`. If you add one, update that table in the same PR.

## What to never do

- **Don't introduce a paid SDK dependency.** The whole point is to remove Scanbot's license cost.
- **Don't add cloud OCR or any network call in the scanning path.** On-device only.
- **Don't break the Scanbot-compat API surface** without an explicit decision logged in `TODO.md`'s decisions section.
- **Don't add features outside the `docs/PLAN.md` Phase scope** to "while we're here" the codebase. Open a separate phase entry instead.
- **Don't write multi-paragraph dartdoc on internal types.** Public API gets full docs; internals get one-line comments only when the why is non-obvious.
- **Don't commit license keys, API tokens, or any secrets.** If you spot one in a diff, refuse and tell the user.

## What to do proactively

- When adding a barcode format: add the row to `docs/SYMBOLOGIES.md`, the mapping in `FormatMapper.kt` AND `SymbologyMapper.swift`, and an example-app fixture in the same PR.
- When adding a MethodChannel method: add the row to `docs/ARCHITECTURE.md`, the Dart wrapper in `lib/src/channel/method_channel.dart`, both native handlers, and a mocked unit test.
- When closing a Sprint ticket: check the box in `TODO.md`.

## Workflow rules

- This is not yet a git repo. When the repo is initialized, conventional-commits style messages are expected (`feat(barcode): ...`, `fix(ios): ...`, `docs: ...`).
- Tests live next to the code: `test/` for Dart, `androidTest/` + `Tests/` for native when added.
- Before declaring a phase done, walk `docs/QA.md` scenarios for that phase on one Android and one iPhone.

## Sub-skills

Reusable per-task skills live under `.claude/skills/`. Invoke via the `Skill` tool when working on:

- `supy-scanner:add-symbology` — adding a new barcode format end-to-end.
- `supy-scanner:add-channel-method` — adding a new MethodChannel method end-to-end.
- `supy-scanner:cut-a-release` — tagging and publishing a version.

## Org-level constraints (always in force)

- Never accept or store secrets/keys/tokens pasted into the session. Refuse and notify.
- This repo is part of Supy. Don't work on personal-project tangents.
- Ask clarifying questions when scope or intent is ambiguous.
