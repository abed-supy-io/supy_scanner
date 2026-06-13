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

### D9 — Palette parity
1. Verify the document scanner UI on Android uses `#6448C3` for primary buttons and `#FFFFFF` for on-primary text (matches the Scanbot palette).
2. iOS uses system UI (palette not configurable) — documented.

### D10 — GMS unavailable
1. Run on a Huawei device without Play Services.
2. Calling `SupyDocumentScanner.startMultiPage(...)` rejects with `model_unavailable`.
3. The retailer-side handler surfaces a localized "Document scanning is not available on this device" message.

### D11 — Cold-start model download
1. Fresh install, no GMS Document Scanner model cached.
2. First call: progress indicator visible during model download (< 30s on 4G).
3. Second call: opens immediately (< 1s).

## Batch barcode

### Bt1 — 20 unique scans in 30s
1. Open the batch scanner.
2. Sweep across 20 distinct printed barcodes in under 30s.
3. The counter reaches 20 with zero duplicates.
4. Final list returned is in scan order.

### Bt2 — Duplicate debouncing
1. Hold over a single barcode for 5 seconds.
2. It is counted exactly once.

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

The mobile lead walks scenarios **B1–B9, D1–D11, Bt1–Bt2** end-to-end on at least one Android device and one iPhone before `v1.0.0` is tagged. Results recorded in this file under a `## Sign-off (vX.Y.Z)` heading per release.
