# ml-on-device-ocr-fallback

**Status:** planned · **Target:** v1.4.0 · **Effort:** XL · **Trace:** pairs with core-ocr-languages-expansion

## Problem
ML Kit Text Recognition and Vision do most of the work, but both produce low-confidence regions on stylized fonts, dense receipts, and some non-Latin scripts. A second-pass on-device OCR model would lift accuracy on the hard tail without a network call.

## Scope
- **Detection model** — PaddleOCR-mobile det quantized, ~3 MB.
- **Recognition model** — PaddleOCR-mobile rec quantized, ~5 MB per language. English bundled; other languages downloadable at install / `prewarm` time.
- Trigger: only when the primary OCR's region confidence falls below threshold, or when the consumer opts in for a specific call.
- Download path uses signature-verified bundles fetched at install or prewarm — **never in the scan path**, preserving CLAUDE.md's "no cloud OCR" rule (the *scan* never touches the network; model bytes are infrastructure, not data).
- Budget: ~8 MB bundled with English, others downloadable.

## Out of scope
- TrOCR-tiny — bigger and slower for the same accuracy on our fixtures.
- Handwriting and table-structure extraction (separate future tickets).

## Acceptance
- [ ] Hard-tail OCR accuracy on the QA fixture set improves ≥ 10% on top of ML Kit/Vision baseline.
- [ ] Per-region fallback latency ≤ 60 ms on tier-mid.
- [ ] Download path verifies model signature; fails closed on mismatch.

## Dependencies
- [ml-runtime-and-loader](ml-runtime-and-loader.md), [ml-model-lifecycle](ml-model-lifecycle.md), [core-ocr-languages-expansion](core-ocr-languages-expansion.md).

## Source
- This conversation's ML roadmap.
