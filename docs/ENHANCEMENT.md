# Document Image Enhancement

This document describes the native image-enhancement pipeline applied to captured document pages before they are persisted, OCR'd, or assembled into a PDF.

## Motivation

Raw camera frames are unfit for downstream AI/LLM ingestion, on-device OCR, and human review. Pre-enhancement, captures suffered from:

- **Low contrast** under indoor lighting (shop floors, restaurants).
- **Shadows and vignettes** from oblique handheld angles.
- **Soft focus** from motion or focus hunting.
- **Uneven exposure** between center and corners.

VisionKit on iOS partially mitigates this; CameraX on Android does not. To produce comparable output on both platforms — and avoid taking an OpenCV dependency (forbidden by [CLAUDE.md](../CLAUDE.md)) — we ship a deterministic native pipeline in `supy_scanner_core`.

## Modes

`SupyDocumentEnhanceMode` (Dart) ↔ `supy_enhance_mode_t` (C):

| Mode | Stages run | When to use |
|---|---|---|
| `off` | none (pass-through copy) | iOS default — VisionKit already enhances. |
| `fast` | gate + tone | Preview-grade output or low-end devices. |
| `balanced` | gate + illumination + tone + unsharp | **Android default.** Best general-purpose result. |
| `max` | gate + illumination + specular clamp + top-hat + tone + CLAHE + unsharp | Dim / uneven / glare-prone captures. Heaviest mode (~2–2.5× `balanced`); opt-in. |

A null `enhanceMode` on the wire lets each platform pick its own default — explicit values flow through unchanged.

## Pipeline stages

### 1. Quality gate

Reuses `supy::scanner::document::classify`'s variance-of-Laplacian sharpness score. Verdict:

- `OK` — proceed.
- `MARGINAL` — proceed; surface `quality = 'poor'` to Dart.
- `REJECT` — short-circuit; return a pass-through copy so callers can re-prompt. `applied_stages` will only have `SUPY_ENHANCE_STAGE_GATE` set.

`min_blur_score` on the input lets callers tune the reject threshold.

### 2. Illumination normalization

Separable morphological closing (1D min→max via monotonic deque, O(n) per row/col) with a kernel ≈ 3% of `min(w,h)`. The closed image approximates background illumination; the output is `clamp(in / background * targetMean)`. Flattens shadows and vignettes without smearing text — the single biggest OCR win.

### 3. Tone curve

Precomputed 256-entry LUT combining gamma 1.20 with a gentle S-curve. Optional 0.5% / 99.5% percentile stretch.

### 4. Unsharp mask

Separable 5-tap Gaussian (σ ≈ 1.5), `out = clamp(in + 0.4·(in − blur))`. Recovers microcontrast lost to the previous stages.

## Advanced stages (`max` only)

These run on top of the `balanced` stack to handle dim, uneven, and glare-heavy captures. All are hand-rolled and dependency-free; they reuse the shared separable morphology in `native/enhance/morphology.cpp` (monotonic-deque O(n) min/max, reflect-clamp borders).

### Specular / glare clamp

`suppressSpecular` (in `illumination.cpp`). Estimates the local diffuse background via a morphological **opening** (which strips bright spikes narrower than the structuring element), then caps any pixel whose luma sits well above that diffuse level **and** is itself near-white. Blown-out highlights are pulled back toward the page (clamped to `diffuse + 24`) while genuinely bright paper is left untouched. Same auto-chosen SE radius as illumination. Runs after illumination flatten, before top-hat.

### Top-hat background flatten

`applyTopHatFlatten` (in `tophat.cpp`). A black-top-hat-family flatten for dark-text-on-light-paper: estimates local paper white via a **closing** with an SE larger than the largest glyph (≈5% of the short side, clamped to `[12, 96]`), then lifts each pixel by the local paper deficit (`kPaper − background`, capped) so residual additive shading flattens to a uniform bright page while text contrast is preserved. Complementary to illumination — that stage corrects multiplicative vignetting via division; this corrects the residual additive offset.

### CLAHE

`applyClahe` (in `clahe.cpp`). Contrast-Limited Adaptive Histogram Equalization on the luma plane, applied as a gain to RGB. An 8×8 tile grid (auto-reduced for small images), per-tile clipped histogram with the excess redistributed uniformly, CDF-derived per-tile mapping, and bilinear interpolation of the four nearest tile mappings per pixel to avoid block artefacts. Lifts local contrast on dim, low-contrast captures (faint 6pt line items under kitchen light) where the global tone curve can't.

## Stage bitmask

`supy_core_enhance_applied_stages` returns OR'd flags from `supy_scanner_enhance.h`:

| Bit | Symbol | Stage |
|---|---|---|
| `0x01` | `SUPY_ENHANCE_STAGE_GATE` | Quality gate ran. |
| `0x02` | `SUPY_ENHANCE_STAGE_ILLUMINATION` | Illumination flatten applied. |
| `0x04` | `SUPY_ENHANCE_STAGE_TONE` | Tone curve applied. |
| `0x08` | `SUPY_ENHANCE_STAGE_UNSHARP` | Unsharp mask applied. |
| `0x10` | `SUPY_ENHANCE_STAGE_SPECULAR` | Specular / glare clamp applied (`max`). |
| `0x20` | `SUPY_ENHANCE_STAGE_TOPHAT` | Top-hat background flatten applied (`max`). |
| `0x40` | `SUPY_ENHANCE_STAGE_CLAHE` | CLAHE local-contrast lift applied (`max`). |

Surfaced on `SupyDocumentPage.enhancedStages` for diagnostics. Future stages will append new bits — never reuse old ones.

## C ABI contract

```c
typedef struct {
  const uint8_t* rgba;           // packed RGBA8888, non-null
  int32_t width;                 // > 0
  int32_t height;                // > 0
  int32_t row_stride;            // >= width * 4
  supy_enhance_mode_t mode;
  float min_blur_score;          // 0 = use built-in default
} supy_enhance_input_t;

supy_enhance_result_t* supy_core_enhance(const supy_enhance_input_t*);
void                   supy_core_enhance_free(supy_enhance_result_t*);
```

Reentrant, no globals. NULL input or invalid dimensions return `NULL`. All accessors are NULL-safe and return zeroed values on a NULL handle.

`row_stride` is honored on both input and output — callers (Android `Bitmap`, iOS `CGContext`) may pass padded rows.

## Platform integration

| Platform | Insertion point | Buffer marshalling |
|---|---|---|
| Android | `PageReencoder.reencodeOne()` — between JPEG decode and tier-aware re-encode. | `Bitmap.copyPixelsToBuffer` / `copyPixelsFromBuffer` via JNI direct ByteBuffer. |
| iOS | `DocumentScannerPresenter` — between `UIImage` delivery and `jpegData(...)`. | `CGImage` → `CGContext` (`kCGImageAlphaPremultipliedLast \| kCGBitmapByteOrder32Big`). |

Both run on a background worker — never the main thread.

## Performance budget

Target ≤ **250 ms** per page at **2400 px** long edge on a 2020-era mid-tier device (`SUPY_ENHANCE_BALANCED`). Validated by the host micro-benchmark `native/enhance/bench_enhance.cpp`:

```bash
cmake -S native -B build -DSUPY_BUILD_TOOLS=ON
cmake --build build --target bench_enhance
./build/bench_enhance                       # default: 2400 px long edge, 20 iterations
./build/bench_enhance --mode balanced --iter 50
```

Reports min / p50 / p95 / max ms and megapixels-per-second per mode. Host numbers are an upper bound — on-device validation on representative Android + iPhone hardware is still required (see manual QA below). `fast` should be ~1.5× faster than `balanced` at the cost of contrast/sharpness.

### Perfgate integration (DIE6)

The same binary feeds perfgate via `tools/perfgate/enhance/run_enhance_bench.dart`:

```bash
dart tools/perfgate/enhance/run_enhance_bench.dart --tier low --iter 50 --log enhance.log
dart tools/perfgate/run.dart --log enhance.log --tier low
```

The driver builds `bench_enhance` with `-DSUPY_BUILD_TOOLS=ON` and runs it with `--json --tier <low|mid|high>` so stdout matches the `BENCH_TIER` / `BENCH_RESULT` protocol consumed by `tools/perfgate/lib/baseline_compare.dart`. CI runs the LOW tier on every PR via the `enhance-bench-low` job (`.github/workflows/ci.yml`); MID and HIGH are deferred until `infra-device-runner-matrix` (P3) lands real-device runners — `ubuntu-latest` numbers for those tiers would bake in CI hardware noise as the gate.

#### Tier → long-edge profile

| Tier | Long edge | Notes |
|---|---|---|
| `low`  | 1280 px | Matches PageReencoder's low-tier downscale target. |
| `mid`  | 1920 px | Deferred to P3 device matrix. |
| `high` | 2400 px | Deferred to P3 device matrix; matches the acceptance target above. |

#### Published budgets

Baselines live under `tools/perfgate/baselines/<tier>/enhance_<mode>_ms.json` and are regenerated via `tools/perfgate/regen-baselines.dart`. The regression gate trips at +15% on p95 (`kP95RegressionTolerance`). The LOW tier table is populated from the first green `enhance-bench-low` CI run — see that job's `perfgate-enhance-low` artifact for the initial numbers.

## Roadmap (v2)

Deferred — tracked in [`TODO.md`](../TODO.md):

- Bilateral / guided denoise (would slot into `SUPY_ENHANCE_MAX` ahead of unsharp).
- HED int8 segmentation detector (no model infra exists yet — separate follow-on sprint).
- Sauvola adaptive binarization (B&W output mode).
- Grayscale variant.
- Multi-output URIs per page (color + B&W from a single capture).

Rationale for v1 deferral: denoise softens text, and the AI/OCR use case responds better to unsharp than to smoothing. The hand-rolled CV stays OpenCV-free — `SUPY_ENHANCE_MAX` now layers specular clamp + top-hat + CLAHE on top of `BALANCED`; denoise/binarize remain behind explicit opt-in.

## Testing

Host-side GoogleTest suite — `native/enhance/enhance_test.cpp`:

```bash
cmake -S native -B build -DSUPY_BUILD_TESTS=ON
cmake --build build
ctest --test-dir build -R enhance
```

Coverage:

- NULL input / invalid dimensions return `NULL`.
- `OFF` is a pure pass-through (zero stages applied, bytes unchanged).
- `BALANCED` on a clean image runs gate + illumination + tone + unsharp.
- `FAST` skips illumination and unsharp.
- `MAX` additionally sets the SPECULAR, TOPHAT, and CLAHE stage bits.
- Uniform input trips `REJECT` and skips downstream stages.
- Synthetic vignette is flattened (corner-vs-center luma gap drops ≥50%).
- Step-edge contrast widens after `applyUnsharpMask` (isolated stage test).
- CLAHE lifts local contrast on a low-contrast checkerboard.
- Top-hat lifts a dim uniform background toward paper white.
- Specular clamp pulls a near-white hotspot down while leaving diffuse pixels unchanged.
- All accessors are NULL-safe.

Synthetic RGBA buffers are generated programmatically — no PNG fixture dependency. Manual QA scenarios live in [`docs/QA.md`](./QA.md).
