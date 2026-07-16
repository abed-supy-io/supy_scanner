# CameraX Document Fallback (v1.2 Phase CXD)

Android-only. Replaces the `model_unavailable` failure on non-GMS devices (Huawei, AOSP, locked-down enterprise images) with a first-party CameraX capture path.

**Public API:** unchanged. Auto-detected at call time. Retailer code is the same on GMS and non-GMS devices.

## When the fallback fires

`DocumentScannerLauncher.launch` consults `GmsAvailability.isUsable(context)` before touching the GMS client. The helper wraps:

```kotlin
GoogleApiAvailability.getInstance()
    .isGooglePlayServicesAvailable(context) == ConnectionResult.SUCCESS
```

- `true` → existing GMS path, byte-for-byte identical to v1.1. No new code in the hot path.
- `false` → `CameraXDocumentScannerActivity` is launched.

iOS is untouched — VisionKit is in every supported iOS 16+ device. The fallback exists only on Android.

## Capture UX (v1.2)

Manual capture by default. Auto-snap activates when `SupyDocumentScanOptions.autoCaptureDelayMs > 0` (CXD-AS1, v1.2.x): the activity attaches `DocumentFrameAnalyzer` on a dedicated executor and drives the C++ guidance state machine (`native/document/document_guidance_classifier.{h,cpp}`) through the `SupyNativeCore.guidance*` JNI facade. Once the classifier sits at `Ready` for `autoCaptureDelayMs` milliseconds it fires `ImageCapture.takePicture(...)` on the main thread. Dwell is tier-aware (LOW=18 / MID=12 / HIGH=9 ready stable frames) and an in-preview hint label renders bilingual (en/ar) guidance copy for the eight `GuidanceFrameState` values. `autoCaptureDelayMs == 0` disables auto-snap and hides the hint — manual FAB capture remains the only path.

```
┌─────────────────────────────────────────┐
│  [ ←  Cancel ]                  [ ⚡ ]   │   ← top bar: cancel + torch
│                                         │
│                                         │
│         CameraX Preview                 │
│         (full-bleed)                    │
│                                         │
│                                         │
│                                         │
│  ┌─┐ ┌─┐ ┌─┐                            │   ← page thumbnails (tap → retake/delete)
│  │1│ │2│ │3│                            │
│  └─┘ └─┘ └─┘                            │
│                                         │
│              ╭──────╮      [  Done  ]   │   ← capture FAB + done CTA
│              │  ⬤   │                   │
│              ╰──────╯                   │
└─────────────────────────────────────────┘
```

- Capture FAB: tap → `ImageCapture.takePicture(...)` → JPEG written to app cache → thumbnail appended.
- Thumbnail tap: small sheet with Retake (re-shoot at the same index) and Delete.
- Done CTA: only enabled when `pages.isNotEmpty()`. Returns ordered list of JPEG URIs.
- Hardware back / cancel: returns `Activity.RESULT_CANCELED` → `DocumentScannerLauncher` resolves `scanDocument` with `[]`. Matches D4.
- `maxPages` cap honored — capture FAB disables when count reached. `0` = unlimited.

## Module layout

New files under `android/src/main/kotlin/io/supy/scanner/document/`:

| File | Responsibility |
|---|---|
| `GmsAvailability.kt` | Single-method helper. `fun isUsable(context: Context): Boolean`. |
| `CameraXDocumentScannerActivity.kt` | The capture Activity. Uses CameraX `Preview` + `ImageCapture`. Writes JPEGs to `cacheDir/supy_camx/` and returns URIs in `EXTRA_RESULT_URIS` (ArrayList<String>). Exposes custom result codes `RESULT_PERMISSION_DENIED` and `RESULT_CAMERA_UNAVAILABLE` for the launcher to map to error codes. |

Modified files:

| File | Change |
|---|---|
| `DocumentScannerLauncher.kt` | `launch()` branches on `GmsAvailability.isUsable(activity)`. Adds a `pendingCameraXLauncher: ActivityResultLauncher<...>` for the new contract. Both branches funnel through the existing `jpegReencode + ocrRunner.run` block, so the wire result is identical. |
| `AndroidManifest.xml` (library) | Declares `CameraXDocumentScannerActivity` with `screenOrientation=portrait` and `configChanges` to survive rotation. |

## Reused infrastructure

- `PageReencoder` (tier-aware quality, JPG/PNG) — same path as GMS.
- `OcrRunner` (ML Kit `TextRecognition`) — runs over the captured JPEGs. Latin-script only, as today.
- `DeviceTier.detect(activity).jpegQuality(...)` — same tier policy as v1.1.
- `SupyPermissions` (Dart) is already called by retailer code before `startMultiPage`. The CameraX Activity also defensively checks `Manifest.permission.CAMERA` and finishes with `permission_denied` if missing.

## Threading

- CameraX `Preview` + `ImageCapture` on the main thread (CameraX requirement).
- `ImageCapture.takePicture(...)` callback delivers on `ContextCompat.getMainExecutor(this)`; JPEG write hops to `Dispatchers.IO`.
- OCR remains where it is — `OcrRunner.run(...)` already runs off-main.

## Error mapping

| Condition | `SupyScanError` code |
|---|---|
| User taps cancel / hardware back before tapping Done | (no error — resolves with `[]`, matches D4) |
| `CAMERA` permission missing at Activity start | `permission_denied` |
| CameraX `ProcessCameraProvider` fails to bind | `camera_unavailable` |
| `ImageCapture.OnImageSavedCallback.onError` | `unknown` (logged with cause) |

## Out of scope for v1.2

- **Edge detection / auto-snap.** Shipped in v1.2.x via CXD-AS1 (see "Capture UX" above). Edge detection runs on the analyzer thread through `DocumentFrameAnalyzer`; the classifier itself is the same C++ FSM iOS uses.
- **Perspective correction.** Captured JPEGs are saved as-shot. The v1.1 Sprint 6 `captureAndRectify` path is GMS-only; revisiting non-GMS rectification is a v1.3 conversation.
- **PNG output for the fallback.** PNG is emitted per-page when requested. PDF output (v1.2 P2 / CXD2 PDF parity, 2026-06-16): the CameraX path now assembles a PDF via `PdfAssembler` (Android `PdfDocument`) over the re-encoded JPEG pages — `pdfUri` is populated on both backends. Byte-for-byte parity with the GMS-produced PDF is not a goal; format-level parity (page count + extractable text) is.
- **iOS.** No iOS work — VisionKit is universal on iOS 16+.

## Exit criteria

1. Non-GMS device (Huawei P30 or GMS-stripped Pixel emulator) → `SupyDocumentScanner.startMultiPage(...)` returns a non-empty `pages` list and a non-empty `ocrText` on a clear English receipt.
2. GMS device → no observable change in behavior, latency, or memory profile vs v1.1.
3. `docs/QA.md` D10 (revised) and D12 (new) both pass.
4. Retailer app integrated against the v1.2 pin: no code change needed, no new error surface.
