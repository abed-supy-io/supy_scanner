# ml-capture-classifiers

**Status:** planned · **Target:** v1.3.0 · **Effort:** L · **Trace:** extends core-csu-classifier-plumbing, core-cxd-auto-snap

## Problem
The guidance state machine's auto-snap and capture hints rely on hand-tuned heuristics for glare, blur, doc-presence, and corner detection. Each retailer scene (cold rooms, fluorescent shelves, glossy invoices) requires a new threshold tweak. Small learned classifiers replace the thresholds with models that generalize across scenes.

## Scope
- **Glare classifier** — binary, ~200 KB, runs on the downscaled luma frame. Output blocks auto-snap when over threshold.
- **Blur classifier** — regression head, ~200 KB. Replaces variance-of-Laplacian gate.
- **Doc-vs-not-doc classifier** — binary, ~500 KB. Suppresses spurious captures (hand, table without document).
- **Corner regression network** — 4-point regression, ~1 MB. Augments / replaces heuristic Hough-based corner finder when confidence beats heuristic.
- All four emit through the existing CSU classifier EventChannel; verdicts collapse identically to the heuristic ones, so consumers see the same `SupyCaptureHint` types.
- Budget: ~2 MB bundled.

## Out of scope
- New `SupyCaptureHint` variants — reuse the existing sealed class.
- Replacing the guidance state machine itself — only its inputs change.

## Acceptance
- [ ] Auto-snap false-positive rate on the QA fixture set drops ≥ 30% vs. heuristic baseline.
- [ ] Per-frame ML cost ≤ 6 ms on tier-mid; bypassed on tier-low.
- [ ] Heuristic path remains as fallback when governor disables ML or model unload fails.

## Dependencies
- [ml-runtime-and-loader](ml-runtime-and-loader.md), [core-csu-classifier-plumbing](core-csu-classifier-plumbing.md).

## Source
- This conversation's ML roadmap; commit c4e4650 (guidance state machine port).
