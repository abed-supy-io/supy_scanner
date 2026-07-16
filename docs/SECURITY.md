# SECURITY.md — supy_scanner

Security review of the Dart ↔ native boundary for the v1.0.x line. Tracks H3-06.

Last reviewed: **2026-06-14** (commit on `main`).

## 1. Scope

In scope:

- The Dart ↔ native MethodChannel and EventChannel surface (`io.supy.scanner/v1`).
- Argument validation on both sides of the boundary.
- Error propagation (no native exception leaks, no PII in `message`).
- Permissions declared by the library AndroidManifest / podspec.
- On-device file writes performed by the scanning paths.
- Supply-chain (transitive deps pulled by Gradle / CocoaPods).

Out of scope (handled elsewhere):

- Host app authentication, transport security, server-side handling of scanned payloads — the library never sees those.
- Native OS-level mitigations (sandboxing, Keychain, KeyStore) — relied on as part of the platform.
- The retailer app's compat-shim layer (covered separately by H2-06).

## 2. Threat model

Assumed attacker capabilities:

- **A1 — Malicious host app code in-process.** A consumer of this library can call any Dart API. We treat them as semi-trusted: invalid payloads must not crash the library or the native plugin, but we don't try to defend against a hostile host (they could simply read `/proc/self` themselves).
- **A2 — Malicious payload on the scan target.** A printed barcode / Data Matrix or a piece of paper waved at the camera may contain crafted bytes (URLs, payloads, very long strings, control characters). The library must surface them as strings without parsing or following them.
- **A3 — Malicious image input via the platform scanner.** GMS Document Scanner / VisionKit hand back JPEGs we re-encode. A corrupted or oversized image must not OOM the process or write outside our cache dir.
- **A4 — Side-channel observation.** Other apps on the device should not be able to read intermediate scan files.

Out of model:

- Physical device compromise, root/jailbreak, debugger attach, screen recording — all out of scope.
- Network MITM — the scanning path is offline (see §5).

## 3. Channel surface — `io.supy.scanner/v1`

### MethodChannel — `io.supy.scanner/v1`

| Method | Args | Returns | Notes |
|---|---|---|---|
| `requestCameraPermission` | — | `{status: granted\|denied\|permanentlyDenied\|unknown}` | Async on Android (requires Activity), sync on iOS once status is known. |
| `scanDocument` | `Map<String, Any?>` (see `SupyDocumentScanOptions.toWire`) | `Map` or null | Returns null if user cancels. |
| `scanBarcodesBatch` | `Map<String, Any?>` (see `SupyBatchBarcodeScanOptions.toWire`) | `Map` or null | Same. |
| `prewarm` | — | null | Idempotent; safe to spam. |
| `nativeCoreProbe` | — | `{version: String, abiVersion: Int}` | Returns `unknown` PlatformException if native core is absent. |

Anything else → `notImplemented` / `FlutterMethodNotImplemented`.

### EventChannel — per-PlatformView

`io.supy.scanner/v1/barcode/<viewId>/events` is opened lazily by each `SupyBarcodeScannerView`. Payloads are tagged `Map<String, Any?>` with a `type` discriminator (`detection` / `preview_started` / `error`). Unknown types collapse to `SupyErrorEvent` on the Dart side (see `lib/src/channel/supy_event_channel.dart:35`).

## 4. Argument validation

### Outgoing (Dart → native)

All channel calls go through `SupyScannerChannel` (`lib/src/channel/supy_scanner_channel.dart`). Outgoing args are typed at compile time — every option type has a frozen `toWire()` that emits a `Map<String, Object?>` from a sealed Dart model. `dynamic` / arbitrary maps never reach the channel from `lib/` because all model fields are typed and validated by the model constructor.

### Incoming arguments (native side)

Both plugins reject malformed top-level args before dispatch:

- Kotlin: `SupyScannerPlugin.expectMapArgs` (`android/src/main/kotlin/io/supy/scanner/SupyScannerPlugin.kt:96`) — non-null, non-Map argument fails with the canonical `unknown` error and a descriptive message that names the actual type. No `as Map<String, Any?>` cast without check.
- Swift: `SupyScannerPlugin.expectMapArgs` (`ios/Classes/SupyScannerPlugin.swift:79`) — same shape, same canonical error code.

Per-method arg parsing then happens inside the launcher/presenter; missing-key paths default sensibly rather than throwing (e.g. `jpegQuality` clamps to 0..100).

### Incoming results (native → Dart)

Dart-side parsers (`SupyDocumentData.fromMap`, `SupyBarcode.fromMap`, etc.) are property-fuzzed against malformed payloads (10k frames, seed `0xDEC0DE`, H2-03). Invariant: malformed input throws **only** `TypeError`, `ArgumentError`, or `SupyScanError` — anything else fails the fuzz test. Channel callers wrap thrown `PlatformException` via `SupyScannerChannel._wrap`, so consumers see a single `SupyScanError` type.

### EventChannel payloads

Each event is `cast<Object?, Object?>` and dispatched on `type`. Unknown types fold to `SupyErrorEvent` rather than throwing — the stream stays live for legitimate events even if an unknown variant appears.

## 5. Network posture

The library has **zero network calls in the scanning path**, by policy (`CLAUDE.md` and `docs/MIGRATION.md`):

- **Android library manifest** (`android/src/main/AndroidManifest.xml`) declares only `CAMERA` and `VIBRATE`. No `INTERNET`. The example app's debug/profile manifests add `INTERNET` for Flutter hot reload — those are tooling-only, not consumed by the library, and are absent from release builds.
- **iOS podspec** declares no `NSAppTransportSecurity` exceptions and no network frameworks.
- **ML Kit Barcode Scanning** runs entirely on-device (bundled model).
- **ML Kit Text Recognition v2 Latin** likewise on-device.
- **GMS Document Scanner** downloads its model lazily through Google Play Services on first use — this is a GMS-mediated download, not a network call from our process, and only happens at most once per device install. The fallback CameraX path (`CameraXDocumentScannerActivity`) bypasses GMS entirely (see `docs/CAMERAX_FALLBACK.md`).
- **iOS VisionKit / Vision** is fully on-device by Apple guarantee.

No telemetry, no analytics, no crash reporter is wired in from this library. Host apps add their own.

## 6. Permissions

| Platform | Permission | Why |
|---|---|---|
| Android | `android.permission.CAMERA` | Camera preview + analysis. |
| Android | `android.permission.VIBRATE` | Haptic on successful scan (user-controllable in options). |
| iOS | `NSCameraUsageDescription` | OS-required prompt copy; supplied by the host app's Info.plist. |

Notably **not** declared:

- `INTERNET` / `ACCESS_NETWORK_STATE` (and never will — policy).
- `READ_EXTERNAL_STORAGE` / `WRITE_EXTERNAL_STORAGE` / `READ_MEDIA_IMAGES`. We only write to the app-private cache directory (see §7).
- `ACCESS_FINE_LOCATION` / `ACCESS_COARSE_LOCATION`. We don't tag results with location.
- `RECORD_AUDIO`. Camera-only.

## 7. File system surface

Both platforms write captured pages to app-private storage only — no shared external storage, no media-store insertion.

- **Android**: `context.cacheDir/supy_scanner/` (re-encode path, `PageReencoder.kt:57`) and `context.cacheDir/supy_camx/` (CameraX fallback, `CameraXDocumentScannerActivity.kt:257`). Both are inside the app sandbox; nothing else has read access without root.
- **iOS**: `NSTemporaryDirectory()` per-page writes (`DocumentScannerPresenter.swift:201`, `:234`) with `.atomic` writes to avoid half-written files.

File names are derived from page index + a per-session random component; we don't include user-supplied data in paths, so a malicious payload cannot escape via filename injection.

Lifetime: files persist for the OS-managed lifetime of the cache directory. The host app is expected to consume + delete them; the library doesn't promise to clean up on its own. **Follow-up:** consider an explicit `SupyDocumentData.dispose()` that deletes the page files. Tracked as informal item, raise as `H3-06-FU1` if a host needs it.

## 8. Sensitive data handling

- **OCR text.** Latin-only on Android (ML Kit), Latin + Arabic on iOS (Vision). Text never leaves the process via this library — the host receives it as a `String` field on `SupyDocumentPage` and decides where it goes.
- **Barcode payloads.** Returned as raw `String`; never parsed, never followed, never URL-decoded. If a barcode contains a URL or shell-injection-looking text, that's the host's problem to validate. We do not mark any field as "trusted".
- **Image bytes.** Returned by URI, not by base64. The host reads from the file URI on demand and can choose to keep them in memory only, or to copy to a more durable location.
- **Logs.** No `print` / `Log.d` / `os_log` call in `lib/src/channel/` or the plugin entry points prints scan content. (Verified by inspection 2026-06-14; a regression here would be caught by H4-01's `SupyLogSink` audit once that ships.)

## 9. Secrets

Per project policy: no license keys, no API tokens, no service accounts ship with this library. The original Scanbot license key was the reason we wrote `supy_scanner` in the first place — replacing a paid SDK with first-party code removes a class of credential-leakage risk. CI is configured to refuse pasted secrets (org-level rule, see CLAUDE.md).

## 10. Supply chain

Versions are pinned by exact string in `android/build.gradle`:

- CameraX `1.3.4` (preview, lifecycle, view, core)
- `androidx.lifecycle:lifecycle-common:2.7.0`
- ML Kit Barcode `17.3.0`
- GMS Document Scanner `16.0.0-beta1`
- ML Kit Text Recognition `16.0.1`

iOS pulls only Apple frameworks (AVFoundation, Vision, VisionKit, UIKit). No third-party CocoaPods.

GitHub Actions in `.github/workflows/` are pinned to commit SHAs with a tag comment (no mutable `@v*` refs). Dependabot (`.github/dependabot.yml`) bumps Actions, pub, and gradle dependencies weekly so the SHAs and language deps stay current.

A full dependency audit with CVE cross-reference is tracked separately as **H3-07** (`docs/DEPENDENCIES.md`).

## 11. Known gaps + follow-ups

| Gap | Tracked as | Notes |
|---|---|---|
| GMS Document Scanner is `beta1` — bump to GA when published. | follow-up | Check at each release cut. |
| No automatic cache cleanup after `SupyDocumentData` consumed. | informal | Host responsibility today; revisit if a host repeatedly fills cache. |
| Native plugin doesn't authenticate the calling Activity. | accepted | A1 is semi-trusted; an in-process attacker has many easier paths. |
| Embedded EventChannel emits to whoever opens the per-view path. | accepted | The viewId is engine-scoped; cross-engine reads are blocked by Flutter's own messenger isolation. |
| Argument-key collisions across method versions (`v1` → `v2`). | policy | `kSupyScannerChannelVersion` enforces parallel surfaces; never mutate an existing key. |

## 12. Review process

This document is reviewed when:

- A new MethodChannel method lands (see `.claude/skills/supy-scanner/add-channel-method`).
- A native dependency is bumped past a minor version.
- A new permission is added to either platform.
- An ML/processing component changes from on-device to cloud (policy: never, but the review must capture the explicit re-affirmation if a deviation is even considered).

Authors of changes that touch any of the above must update the relevant section in the same PR.
