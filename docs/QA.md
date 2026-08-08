# QA — Acceptance Scenarios

Scenarios mirror the current Scanbot UX as it exists in the retailer app. Pass criterion: a tester switching between the Scanbot build and the supy_scanner build does not notice a difference at the same step.

## Test matrix

| Device class | OS | Why it's on the matrix |
|---|---|---|
| Low-end Android | Moto G Power, Android 13 | Worst-case CPU / camera perf. |
| Mid-tier Android | Samsung A54, Android 14 | Most-common retailer field device. |
| Flagship Android | Pixel 8, Android 15 | Best-case parity baseline. |
| Low-end iPhone | iPhone SE 3, iOS 16 | Minimum supported iOS. |
| Mid iPhone | iPhone 13, iOS 17 | |
| Flagship iPhone | iPhone 15 Pro, iOS 18 | |
| Non-GMS Android | Huawei P30 *(if available)* | Verifies the documented GMS-unavailable failure mode. |

## Embedded barcode scanner

### B1 — Open & first detect
1. From the SKU-add page, tap the scan CTA.
2. The embedded camera view appears in the center of the screen with header (page title) and footer (manual-entry CTA) intact.
3. Point at an EAN-13 barcode.
4. Within 1 second, the scan is reported. Header and footer remain visible throughout.

### B2 — Cooldown
1. Continue holding the camera over the same barcode after B1.
2. Verify that the next detection callback fires no sooner than 2 seconds after the first.

### B3 — Pause / resume
1. With the scanner open, call `controller.pause()`.
2. Verify the preview freezes (no detection callbacks).
3. Call `controller.resume()`.
4. Detection resumes.

### B4 — Torch toggle
1. In a dim environment, tap the torch icon.
2. The device flashlight turns on.
3. Tap again; it turns off.
4. On devices without a torch (e.g., iOS simulator), the icon is hidden (driven by `preview_started.flashAvailable`).

### B5 — Code-128 minimum length
1. Print a Code-128 barcode encoding `"AB"` (2 chars, below `minTextLen=5`).
2. Aim at it.
3. **Expected:** no detection callback fires.
4. Print one encoding `"ABCDE"` (5 chars).
5. Detection fires normally.

### B6 — Scan window
1. Configure with `useScanWindow: true` and a specific `scanWindow` rect.
2. Place two barcodes side by side, one inside the window, one outside.
3. Only the in-window barcode is reported.

### B7 — Permission denied
1. Reset the host app's camera permission to "Denied".
2. Open the scanner.
3. An error with code `permission_denied` surfaces; the embedded view shows a "Camera permission required" placeholder.

### B8 — Lifecycle: background & return
1. Open the scanner, then send the app to background.
2. Bring it back.
3. Preview resumes within 500ms; detection works.

### B9 — Open/close cycling
1. Run `example/integration_test/reliability_harness_test.dart` — 100x push/pop of `SupyBarcodeScannerView` + 50x pause/resume on a live controller.
   - Command: `cd example && flutter test integration_test/reliability_harness_test.dart --profile -d <device-id>`
2. No native exception, no leaked AVCaptureSession (iOS Instruments), no leaked CameraX use case (Android Profiler).

### B10 — Flip camera (alternation)
1. Open the embedded scanner on a back-facing lens.
2. Call `controller.flipCamera()` 10 times in a row, alternating back ↔ front.
3. **Expected each flip:**
   - Preview never goes black or freezes; detection callbacks resume on the new lens within 500 ms.
   - `controller.cameraPosition` matches the visible lens after `await`.
   - A fresh `preview_started` event fires per flip — verified indirectly via B4: torch icon visibility refreshes (front lens on most devices = no flash = icon hidden; back lens = icon shown).
4. **Failure mode being guarded:** the iOS path used to commit a zero-input session if the new `AVCaptureDeviceInput` could not be added — preview would go black with no recovery.

### B11 — Zoom clamping
1. On an iPhone SE 3 (max zoom typically ~5x), call `controller.setZoom(100.0)`.
2. **Expected:** `controller.zoom` after `await` equals the device-reported `maxAvailableVideoZoomFactor` (≈ 5.0), not 100.0.
3. Repeat on a Pixel 8; `controller.zoom` reflects the CameraX-clamped value.
4. Call `controller.setZoom(0.001)`; `controller.zoom` reflects the device minimum (≥ 1.0 on cameras without ultrawide).

### B12 — Min-focus-distance lock cross-platform
1. **iPhone 15 Pro:** call `controller.setMinFocusDistanceLock(on: true)`. The future resolves; `controller.minFocusDistanceLock` is `true`; close-focus on small barcodes improves visibly.
2. **Pixel 8 (Android):** call `controller.setMinFocusDistanceLock(on: true)`. The future resolves **without throwing**; `controller.minFocusDistanceLock` remains `false` (the native side returns `unsupported_operation`; the controller swallows it and leaves state untouched).
3. **Failure mode being guarded:** the controller used to cache `_minFocusDistanceLock = true` on Android even though CameraX never applied it — `minFocusDistanceLock` getter lied to callers.

### B13 — Idle pause + torch-idle advisory (v1.1)
1. On a **MID** or **LOW** tier device (HIGH opts out — see `docs/PERFORMANCE.md` for tier mapping), open the barcode scanner.
2. Tap the torch icon to turn it on. Then point the camera at a still, uniform surface (e.g., a desk) and hold steady.
3. **Expected:** within ~700 ms (the tier's `idlePauseThresholdMs` dwell) the EventChannel emits `{type: 'idle_pause'}` immediately followed by `{type: 'torch_idle_suggested'}`. Move the camera — `{type: 'idle_resume'}` fires.
4. Repeat with the torch **off**: only `idle_pause` / `idle_resume` should fire — `torch_idle_suggested` must NOT be emitted.
5. **HIGH-tier device (Pixel 8 / iPhone 15 Pro):** neither `idle_pause` nor `torch_idle_suggested` ever fire — flagship opts out of idle gating entirely.

## Native core probe

### NC1 — Probe on a healthy build
1. From the example app, call `SupyScannerChannel.instance.nativeCoreProbe()`.
2. **Expected:** the returned `SupyNativeCoreProbe` has a non-empty `version` and `abiVersion ≥ 1` on both Android and iOS.

### NC2 — Probe on a broken build (negative test)
1. Temporarily patch `SupyNativeCore.version()` (iOS) / `SupyNativeCore.version()` (Android JNI) to return `""` and an `abiVersion` of `0`.
2. Rebuild and call `nativeCoreProbe()`.
3. **Expected — iOS:** Dart catches a `PlatformException(code: "native_core_unavailable")` and surfaces it as `SupyScanError`. **Android:** same code path (already in place pre-fix).
4. **Expected — Dart channel wrapper:** if the response map is missing `version` or `abiVersion` entirely, Dart throws `SupyScanError(code: unknown, message: 'nativeCoreProbe response is missing key "version" | "abiVersion"')` — not a silent fallback to `''` / `0`.
5. Revert the patch before committing.

## Document scanner + OCR

### D1 — Single-page receipt
1. From the invoice flow, tap "Scan with camera".
2. Camera UI appears (VisionKit on iOS, GMS on Android).
3. Capture one page (auto-snap on Android, manual on iOS by default).
4. Review/crop/rotate UI appears.
5. Tap "Done."
6. `List<File>` returned has 1 element; the file exists on disk and opens as a valid JPEG.

### D2 — Multi-page receipt (5 pages)
1. Scan 5 pages in sequence.
2. Reorder one page in the review screen.
3. Delete one page.
4. Tap Done.
5. Returned `List<File>` has 4 elements in the new order; OCR text is non-empty.

### D3 — Unlimited pages
1. Scan 12 pages in sequence.
2. The flow does not cut off (matches Scanbot `pagesScanLimit=0`).

### D4 — Cancel mid-scan
1. Open the scanner, capture 2 pages, tap the back button.
2. Returned `List<File>` is empty (`scanWithCamera` resolves with `[]`, not an error).

### D5 — Arabic UI
1. Set device locale to Arabic.
2. Open the scanner.
3. Guidance strings render in Arabic (Android: from `ScanbotStrings`; iOS: from system).
4. Review screen labels are RTL-correct.

### D6 — OCR English receipt
1. Scan a clear English receipt.
2. `ocrText` contains the visible total, vendor name, and at least 5 line items.

### D7 — OCR Arabic receipt
1. Scan an Arabic invoice.
2. `ocrText` contains visible Arabic strings (manual eyeball — full accuracy is out of scope; we only verify it isn't garbage / empty).

### D8 — JPEG quality
1. Set `jpegQuality: 70`.
2. Scanned files are < 500KB per page on a typical 8.5x11" receipt at iPhone-camera resolution.

### D8b — Default JPEG sharpness (Scanbot parity)
1. Leave `jpegQuality` at its default (95) on both Android (GMS) and iOS (VisionKit).
2. Scan a printed A4 page with small (8–10 pt) body text — e.g. a lab report or contract.
3. Pull `pages[0].uri` off-device and inspect at 100 %: letterforms must be sharp, with no visible "mosquito noise" around glyphs or hairlines around table rules.
4. iOS: file size for a single A4 page should be in the ~400–900 KB range. A materially smaller file (~150–250 KB) means the native fallback default in `DocumentScannerPresenter.swift` was not picked up.
5. Android: with GMS the file should be passed through untouched (no re-encode); `enhancedStages` is `0` and `enhanceMs` is `0` when `enhanceMode == off`.

### D8c — Paper-preserving color filter (iOS, v1.2)
Tests the new `SupyDocumentFilter.color` default that re-processes VisionKit's bleached output. Run on iOS only.
1. **Warm-light lab report** — Scan a printed lab report under warm (~3000K) indoor light with `filter` left at default. The page must read as cream / off-white, not pure paper-white; body text must be visibly darker and crisper than VisionKit's raw output (compare against `filter: SupyDocumentFilter.original` on the same page).
2. **Shadow gradient** — Place an A4 sheet so one half is in shadow. Scan with default filter. The output must show roughly uniform paper tone across both halves (illumination flattening); text on the shadowed side must be legible without the bright side blowing out.
3. **Thin text on cream paper** — Scan a thermal receipt or beige-paper memo with 6–8 pt body text. Letterforms remain crisp without halos, ringing, or visible over-sharpening around glyph edges.
4. **B&W filter** — Repeat scenario 1 with `filter: SupyDocumentFilter.blackAndWhite`. Output is pure black-on-white with no visible color cast; text edges are clean (no isolated speckles).
5. **Original (bypass)** — Repeat scenario 1 with `filter: SupyDocumentFilter.original`. Output should match the pre-v1.2 VisionKit-raw look (bleached toward white). Confirms the bypass path works.

### D8d — Full enhancement pipeline & `processing` tuning (iOS, Phase DPX)
Tests the shared `DocumentProcessor` pipeline and the new
`SupyDocumentScanOptions.processing` (`SupyDocumentProcessingOptions`) overrides.
Run on iOS (both the VisionKit and embedded document paths).
1. **Default (drop-in) parity** — Scan an A4 document with `processing` left `null`. Output must be tightly cropped to the page (no finger, table, or letterbox bars), perspective-corrected, crisp, and resolution-capped near the 2200 px longest edge. This is the baseline improvement over the pre-DPX washed/soft output; existing callers get it with no code change.
2. **High-resolution source** — Confirm the embedded capture is full-resolution: the pre-resize source honors `.photo` preset + `maxPhotoDimensions` (a single A4 page down-sampled to ~2200 px should look sharp, not upscaled). A materially soft result means the preview-grade frame was captured instead of the photo output.
3. **`maxDimension` override** — Scan the same page with `processing: SupyDocumentProcessingOptions(maxDimension: 1500)`. Longest edge of the exported JPEG ≈ 1500 px; with `maxDimension: 0` the export is not down-sampled (full source resolution).
4. **Stage toggles** — Scan with `autoCrop: false` (full frame retained, no crop), then `deskew: false` (a deliberately tilted page stays tilted), then `backgroundWhitening: false` (paper keeps its native tone). Each toggle must visibly change only its stage.
5. **`enhancement` / `quality` override** — Scan with `processing: SupyDocumentProcessingOptions(enhancement: SupyDocumentFilter.blackAndWhite, quality: 80)`. Output is B&W at the lower JPEG quality even though the top-level `filter` is left at default — the nested override wins; when `enhancement`/`quality` are null the top-level `filter`/`jpegQuality` are used.
6. **Colored stamp / signature preservation** — Scan a document bearing a colored stamp or ink signature with default `processing`. Background whitens to clean paper while the colored stamp/signature retains its hue (color-safe whitening).
7. **Embedded rectify quad authority** — On the embedded path, `captureAndRectify` output stays warped by the pipeline's own quad (enhancement runs via `enhanceOnly`, not a second detect); reported `width`/`height`/`widthPx`/`heightPx` match the enhanced image's actual pixels.

### D8e — Android `processing` parity (Phase DPX)
Android runs the shared tail (`PageReencoder`: smart resize → native enhance →
output filter) after GMS/CameraX own detect+crop+warp upstream. Run on **one
low-end + one modern Android** across `scanDocument` (GMS) and the embedded
`captureAndRectify` path.
1. **Default (drop-in) parity** — Scan an A4 document with `processing` left `null`. Output is cropped+perspective-corrected (by GMS/CameraX), crisp, and capped near the 2200 px longest edge. Existing callers get this with no code change.
2. **`maxDimension` override** — Scan with `processing: SupyDocumentProcessingOptions(maxDimension: 1500)`. Longest edge of the exported JPEG ≈ 1500 px; `maxDimension: 0` exports at the full rectified resolution.
3. **`enhancement` filter** — Scan the same page three ways: `grayscale` (neutral gray, no color cast), `blackAndWhite` (clean black-on-white via Otsu, no color speckles), `original` (native enhance bypassed — raw GMS/warp look). `color` (default) keeps the enhanced pixels.
4. **Enhance collapse** — With `shadowRemoval`/`backgroundWhitening`/`denoise`/`sharpen` **all** `false` (or `enhancement: original`), the native enhance pass is skipped (`EnhanceMode.OFF`); with any of them `true`, the bundled enhance runs. Individual sub-toggles are not independently observable on Android (single bundled mode) — verify only the all-off vs any-on boundary.
5. **`quality` override** — `processing: SupyDocumentProcessingOptions(quality: 80)` lowers JPEG quality (subject to device-tier clamp); null falls back to the top-level `jpegQuality`.
6. **`captureFullFrame` raw gap** — On the embedded path, `captureFullFrame` returns the raw frame with **no** resize/enhance/filter (documented fallback). Enhanced output requires `captureAndRectify`.

### D9 — Palette parity
1. Verify the document scanner UI on Android uses `#6448C3` for primary buttons and `#FFFFFF` for on-primary text (matches the Scanbot palette).
2. iOS uses system UI (palette not configurable) — documented.

### D10 — GMS unavailable (v1.2 revision — fallback path)
1. Run on a Huawei device without Play Services (or a GMS-stripped Pixel emulator).
2. Calling `SupyDocumentScanner.startMultiPage(...)` **no longer rejects** with `model_unavailable` — `DocumentScannerLauncher` pre-flights `GmsAvailability.isUsable(activity)` and launches `CameraXDocumentScannerActivity` instead. See D12 for the exit criteria of the fallback flow itself.
3. Retailer code is unchanged — no new error surface, no new branch.
4. `model_unavailable` is now reserved for the edge case where GMS *is* available but the model download itself fails (rare; surfaces from the `addOnFailureListener` on `getStartScanIntent`).

### D11 — Cold-start model download
1. Fresh install, no GMS Document Scanner model cached.
2. First call: progress indicator visible during model download (< 30s on 4G).
3. Second call: opens immediately (< 1s).

### D12 — CameraX fallback (non-GMS Android, v1.2)
1. Run on a Huawei device without Play Services (or a GMS-stripped emulator).
2. Call `SupyDocumentScanner.startMultiPage(maxPages: 3)`.
3. Native CameraX preview opens (portrait, full-bleed). Tap-to-capture FAB writes one JPEG per tap; thumbnails appear in the bottom strip.
4. Tap a thumbnail → AlertDialog offers Delete; the thumbnail and underlying file disappear.
5. Capture 2 pages, tap Done. Result: `pages.length == 2`, each with non-zero `width` / `height`, `ocrText` non-empty on a clear English receipt.
6. `pdfUri` is `null` even if `outputFormat: pdf` was requested (logged at `launch()`; documented limitation).
7. Repeat with hardware back / Cancel before tapping Done — `startMultiPage` resolves with `pages == []` (matches D4 / iOS VisionKit cancel semantics). **Not** `cancelled` error.
8. Revoke camera permission, retry → `startMultiPage` rejects with `permission_denied`.
9. Force a CameraX bind failure (e.g. emulator with no camera) → `camera_unavailable`.
10. Retailer app integrated against v1.2: no code change, no new error branch needed.

### D13 — CameraX fallback auto-snap (v1.2.x)

Runs on the same non-GMS surface as D12; uses the C++ guidance state machine ported in commit `c4e4650`. Auto-snap is Android-only — iOS continues to use VisionKit's native cue.

1. Force the CameraX path (`preferredBackend: SupyDocumentScannerBackend.cameraX`) on a GMS-available emulator, OR run on a non-GMS device. Call `SupyDocumentScanner.startMultiPage(maxPages: 2, autoCaptureDelayMs: 800)`.
2. Frame a printed invoice flat on a contrasty surface. Hold steady — within ~1.5 s the activity auto-captures one page (no FAB tap). The on-screen hint reads "Ready" (or "جاهز" when `locale=ar`).
3. Tilt the device > 8° while still framing the same document. No auto-snap fires. The hint switches to "Reduce tilt" / "قلّل الميل".
4. Drop one corner off-frame. The hint switches to "Move closer" / "Center the document" depending on what failed; no auto-snap.
5. Cover the lens / point at a blank wall. Hint reads "Searching for document" / "ابحث عن مستند"; no auto-snap.
6. Call `startMultiPage(..., autoCaptureDelayMs: 0)`. Auto-snap is disabled; manual FAB still captures. Hint label is hidden.
7. Tier check: on a low-tier device (RAM ≤ 3 GB / API ≤ 28) the ready-dwell takes visibly longer (≈18 frames vs 9 on high) — auto-snap still fires once steady. No spurious snaps during repositioning.
8. Backgrounding the activity mid-dwell (recent apps → return) does not crash and resumes detection cleanly; no auto-snap fires during the resume frame burst.

### D14 — Embedded capture: on-still quad refinement (iOS)

Covers Phase CSU Sprint 1: `captureAndRectify` aspect mapping + on-still refinement.

1. Open the example app → "Smart Document" on an iPhone (not simulator).
2. Frame an A4/receipt on a contrasting background; wait for the ready state.
3. Trigger capture. Verify the rectified output's edges hug the document —
   no sliver of background band on the left/right (the pre-fix symptom of the
   16:9→4:3 mis-crop) and no clipped document edge.
4. Repeat with the document deliberately ~15° tilted and slightly off-center:
   the output must still be a clean top-down crop.
5. Repeat with the document half out of frame at capture time: capture must
   still succeed (never error because refinement failed) and return a usable
   crop of the visible region.
6. Debug-verify `SupyDocumentCapture.quadSource`: mostly `refined` in
   scenarios 3–4; `preview` is acceptable in scenario 5.

### Document Scanner Smart Guidance (2026-06-14)

Run on Pixel 6a + iPhone 13:

- [ ] Invoice on dark desk → quad detected within 1s, ring countdown fires.
- [ ] Invoice held in hand (motion) → `holdSteady` shows, never auto-snaps until stable.
- [ ] Invoice on a laptop screen showing the same scan → must NOT trigger ready (interior-variance gate).
- [ ] Invoice partially off-frame → `tooClose` with `clipsEdge`.
- [ ] Low-light desk → `tooDark`.
- [ ] Tilted 30° → `tooSkewed`.
- [ ] Auto-snap: ring countdown visible, cancellable by tilting, fires capture; manual button still works while countdown not active.
- [ ] Capture JPEG: open the file from the example app's surfaced path; verify the page is rectified (dewarped) on **both** iOS and Android (Android via the Sprint 4 native warp — see Phase A scenarios below).

> **Note:** All boxes above are intentionally unchecked. This QA pass is human-only and must be run on real Pixel 6a + iPhone 13 hardware post-merge against the published example app.

### Sprint 4 Phase A — Perspective warp + Android `captureAndRectify` (2026-06-26)

Verifies the hand-rolled OpenCV-free native warp (`core/document/perspective_warp.cpp` → `supy_core_warp`) and the now-implemented Android `captureAndRectify`. Run on **one low-end Android (Moto G Power class) + one iPhone (SE2/12)**:

- [ ] Invoice shot at ~30° tilt on the low-end Android → captured page is **flat and rectangular** (not a skewed phone-photo), geometry visually matching the iOS output for the same shot.
- [ ] Page edges in the rectified output align with the detected quad — no black wedges, no doubled/torn edges from a degenerate homography.
- [ ] `captureAndRectify` with **no document in frame** → falls back to `captureFullFrame` (full-frame still saved), no crash, no dead button.
- [ ] Rapid double-tap capture → second call returns `captureFailed` ("capture already in progress"), first capture still completes.
- [ ] Output long side is bounded (no multi-thousand-px memory blowup) and the temp still is cleaned up (cache dir doesn't accumulate `supy-doc-*.jpg`).
- [ ] iOS unchanged: `captureAndRectify` still rectifies via `CIPerspectiveCorrection` (divergence is intentional and geometry-equivalent — see `docs/ARCHITECTURE.md`).

> **Note:** Unchecked — human-only QA on real hardware. Native warp correctness is pinned by the host gtest `PerspectiveWarp` suite (8 cases, green); these scenarios verify the on-device capture→warp→encode path the unit tests can't reach.

### Sprint 4 Phase B — `MAX` enhancement mode (2026-06-26)

Verifies the now-real `SUPY_ENHANCE_MAX` stack (specular clamp + top-hat flatten + CLAHE on top of `balanced`). For each scenario, scan the same page twice — once with `enhanceMode: SupyDocumentEnhanceMode.balanced`, once with `.max` — and compare the two output JPEGs side by side. Run on **one low-end Android + one iPhone**:

- [ ] **Dim kitchen light (~50 lux), small line items** — A printed restaurant invoice with 6–8 pt line items under dim warm light. `max` output: faint line items are visibly more legible than `balanced` (CLAHE local-contrast lift), without crushing midtones to mud or introducing tile-boundary banding.
- [ ] **Glare hotspot** — A glossy/laminated menu or receipt angled so a ceiling light leaves a blown-out specular hotspot. `max` output: the hotspot is pulled back toward paper tone (text under/near it recoverable) while genuinely bright paper elsewhere is **not** dimmed; no dark halo ringing the former hotspot.
- [ ] **Uneven / gradient background** — A page lit brighter on one side. `max` output: background flattens to a more uniform bright paper than `balanced` (top-hat), text contrast preserved on both sides; no posterization of the gradient.
- [ ] **Clean, evenly-lit A4 (regression guard)** — A clean head-on A4 page. `max` output is at worst neutral vs `balanced` — no over-sharpening halos, no blown highlights, no visible CLAHE blocking. Confirms the heavy stack doesn't degrade already-good captures.
- [ ] **Stage bitmask** — On any `max` scan, `pages[0].enhancedStages` has the SPECULAR (`0x10`), TOPHAT (`0x20`), and CLAHE (`0x40`) bits set in addition to the balanced bits; `enhanceMs` is non-zero and (qualitatively) the heaviest of the modes.
- [ ] **OCR parity** — `ocrText` on a `max` scan is at least as complete as the `balanced` scan for the same page (OCR receives grayscale, never binarized — `max` must not regress recognition).

> **Note:** Unchecked — human-only QA on real hardware. Stage wiring + per-stage behavior are pinned by the host gtest `EnhanceStage.*` / `EnhancePipeline.MaxAppliesAdvancedStages` cases (green); these scenarios verify perceptual legibility and OCR impact the unit tests can't judge. Device timing comes from the `enhance-bench` perfgate job, not fabricated here.

### Phase FQS — Frame Quality Score (2026-06-17)

Verifies the Swift Laplacian → C++ scorer port (`core/quality/frame_scorer.cpp`). Behavior must match the pre-FQS build — these scenarios pin the guidance classifier transitions, not the raw numbers (which are now identical to Android by construction).

Run on iPhone 13 (iOS half is what landed; Android FQS4 is a follow-up):

- [ ] Invoice on bright desk, head-on, still → reaches `ready`, auto-snap fires (sharp + bright path).
- [ ] Invoice held with deliberate motion blur → never reaches `ready`; `holdSteady` / `tooBlurry` cycles correctly.
- [ ] Invoice in low light → `tooDark` shown; raising brightness recovers within a frame or two.
- [ ] Letterboxed preview (pillarbox black bars) → mean luma not biased by the bars (center-60% crop excludes them); auto-snap still fires on a clean page.
- [ ] Cold-start cycle: open → scan → close → reopen 10× → no leaks, no crash, classifier still transitions cleanly (pure-C++ scorer has no heap state of its own).

> **Note:** Unchecked — human-only QA on real iPhone 13 hardware. Android JNI parity (FQS4) has its own QA pass once it lands.

## Batch barcode

### Bt1 — 20 unique scans in 30s
1. Open the batch scanner.
2. Sweep across 20 distinct printed barcodes in under 30s.
3. The counter reaches 20 with zero duplicates.
4. Final list returned is in scan order.

### Bt2 — Duplicate debouncing
1. Hold over a single barcode for 5 seconds.
2. It is counted exactly once.

## Data Capture parity (DC track)

Scenarios for the Scanbot Data Capture parity track (DC0–DC8). All are additive
APIs — no retailer call site changed. Each carries a documented platform-parity
note; `docs/MIGRATION.md` "Data Capture platform parity" is the source of truth
for the gaps referenced below.

### DC1 — Native-core symbologies
1. With `useNativeCore: false`, aim at a DataBar and a MicroQR fixture.
2. **Expected:** no match / `format_unsupported` on both Android and iOS — never
   a crash.
3. Set `useNativeCore: true` and re-scan the same fixtures.
4. **Expected:** `dataBar` / `dataBarExpanded` / `microQr` / `rMQR` / `maxiCode`
   decode with correct `rawValue` and `format` on both platforms.
5. Spot-check that the 13 pre-existing formats still decode on the default
   (`useNativeCore: false`) path — no regression.

### DC3 — Standalone OCR (`recognizeText`)
1. Call `SupyScannerChannel.recognizeText` on a printed Latin sample doc.
2. **Expected (Android + iOS):** a non-empty block → line → element tree; boxes
   normalized `[0..1]`, top-left origin, visually aligned with the words when
   overlaid.
3. Repeat with an Arabic sample and `languages: ['ar']`.
4. **Expected — iOS:** Arabic text and boxes returned. **Android:** empty tree
   (ML Kit is Latin-only — documented gap); fails soft, never a crash.

### DC7 — Live text-pattern scanner
1. Open `SupyTextPatternScannerView` with a pattern (e.g. an email or `\d{6}`).
2. Point at matching text. **Expected (Android + iOS):** a
   `SupyTextPatternMatch` emits, the finder overlay highlights it, and the
   per-value cooldown suppresses duplicate spam.
3. `pause()` stops emissions; `resume()` restarts them; `setTorch(true/false)`
   toggles the light.
4. **iOS:** an Arabic pattern matches Arabic text in-frame. **Android:** the
   same Arabic pattern never matches (Latin-only OCR — documented gap); Latin
   patterns still match; no crash.
5. Navigate away to dispose the view: camera session and analyzer stop; no
   leaked frames; no crash on rapid open/close.

### DC8 — TIFF + searchable-PDF export
1. Scan a 2+ page document with `outputFormat: SupyDocumentOutputFormat.tiff`.
2. **Expected (Android + iOS):** `SupyDocumentData.tiffUri` is set, `pdfUri` is
   `null`; the file is a valid multi-page TIFF with every page present and
   correctly oriented (verify on-device and in a desktop viewer).
3. Re-scan with `outputFormat: SupyDocumentOutputFormat.searchablePdf`.
4. **Expected:** result lands on `pdfUri` (`tiffUri` `null`); in a PDF viewer the
   pages render and the OCR text is **selectable/searchable but visually
   invisible** (text over image, no visible glyphs).
5. Re-scan with `outputFormat: pdf` (plain): normal PDF on `pdfUri`, no text
   layer — no regression.
6. **iOS:** searchable PDF of an Arabic document has selectable Arabic text.
   **Android:** selectable text only for Latin runs (Arabic word boxes absent —
   documented gap); the PDF still opens and pages render.

## Performance targets

| Metric | Target | Procedure | v1.0.0 result |
|---|---|---|---|
| QR scan latency, Moto G Power | p50 < 300 ms, p95 < 800 ms | Run `perf_bench_test.dart` → "QR cold-detect" scenario over 50 paper-printed QR presentations. | _pending device run_ |
| 10-page OCR end-to-end, iPhone SE 3 | < 12 s | Run `perf_bench_test.dart` → "Document OCR" scenario with the 10-page receipt fixture in `example/assets/test/receipt_10p.pdf`. | _pending device run_ |
| Batch 20-barcode session | < 30 s | Run `perf_bench_test.dart` → "Batch 20" scenario with the 20-barcode torture sheet. | _pending device run_ |
| Embedded preview start, Pixel 8 | < 400 ms | Run `perf_bench_test.dart` → "Preview cold start" scenario; reads `SupyBarcodeScannerView.onPreviewStarted` timestamp. | _pending device run_ |
| Heap delta after 100 open/close cycles | < 5 MB | `reliability_harness_test.dart` under Android Profiler / Instruments allocations. | _pending device run_ |

### Bench run command

```
cd example
flutter test integration_test/perf_bench_test.dart --profile -d <device-id>
```

The harness prints a JSON line per metric to stdout (`BENCH_RESULT {"metric":"...","p50":...,"p95":...,"runs":50}`) for easy capture into this table.

## Sign-off

The mobile lead walks the **release-scoped scenario set** end-to-end on at least one Android device and one iPhone before each `vX.Y.Z` tag is pushed. Results are recorded in this file under a `## Sign-off (vX.Y.Z)` heading per release.

Scenario scope per release line:

| Release line | In-scope scenarios | Out-of-scope (why) |
|---|---|---|
| **v1.0.x** (drop-in Scanbot replacement) | B1–B12, NC1–NC2, D1–D11, Bt1–Bt2 | B13 (v1.1 idle/torch-idle), D12 (v1.2 CameraX fallback) |
| **v1.1.x** (perf workstream) | v1.0.x set **+** B13 | D12 (v1.2) |
| **v1.2.x** (CameraX fallback) | v1.1.x set **+** D12 | — |

For a **patch release** (e.g. v1.0.1 over v1.0.0) the walk is **regression-only**: the public Dart, MethodChannel, and native error-code surface are byte-compatible with the prior tag, so the criterion is "tester noticing no behavioral change from the prior tag." If a scenario diverges, that's a release blocker — investigate before tagging.

The Performance table (above) is **not** part of the per-release sign-off — those metrics are tracked separately and only block the first release that closes the S3-09 "real-device perf numbers" debt from `CHANGELOG.md` v1.0.0 pending items.

### Sign-off template

Copy this block under a fresh `## Sign-off (vX.Y.Z)` heading. Fill in device + tester. Tick each scenario; if any fail, link the issue + decide tag-block vs. defer.

```markdown
## Sign-off (v1.0.1)

- Tag candidate commit: <sha>
- Walker: <name> (<role>)
- Date: YYYY-MM-DD
- Android device: <model + OS>
- iPhone: <model + iOS>
- Walk basis: regression-only vs. v1.0.0 (no public API changes)

### Results

| Scenario | Android | iPhone | Notes |
|---|---|---|---|
| B1  | [ ] | [ ] | |
| B2  | [ ] | [ ] | |
| B3  | [ ] | [ ] | |
| B4  | [ ] | [ ] | |
| B5  | [ ] | [ ] | |
| B6  | [ ] | [ ] | |
| B7  | [ ] | [ ] | |
| B8  | [ ] | [ ] | |
| B9  | [ ] | [ ] | |
| B10 | [ ] | [ ] | |
| B11 | [ ] | [ ] | |
| B12 | [ ] | [ ] | |
| NC1 | [ ] | [ ] | |
| NC2 | [ ] | [ ] | |
| D1  | [ ] | [ ] | |
| D2  | [ ] | [ ] | |
| D3  | [ ] | [ ] | |
| D4  | [ ] | [ ] | |
| D5  | [ ] | [ ] | |
| D6  | [ ] | [ ] | |
| D7  | [ ] | [ ] | |
| D8  | [ ] | [ ] | |
| D9  | [ ] | [ ] | |
| D10 | [ ] | [ ] | |
| D11 | [ ] | [ ] | |
| Bt1 | [ ] | [ ] | |
| Bt2 | [ ] | [ ] | |

### Decision
- [ ] All scenarios pass — clear to tag v1.0.1 via `tools/release.sh 1.0.1`.
- [ ] Failures listed above — tag blocked pending fix.
```
