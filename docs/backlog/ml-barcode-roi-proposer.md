# ml-barcode-roi-proposer

**Status:** planned · **Target:** v1.4.0 · **Effort:** L · **Trace:** augments core-libdmtx-android-roi, core-libdmtx-ios-bridge

## Problem
libdmtx's locator is a hand-tuned heuristic that misses small / damaged / partially occluded DataMatrix codes and degraded 1D codes at retail scanning distance. A small learned detector trained on the retailer fixture set can propose ROIs the heuristic misses.

## Scope
- **Detector** — quantized MobileNet-SSD-lite, ~2 MB, single-shot, detects DM + degraded 1D regions. Output: ROI list with confidence.
- **Super-resolution pass** — ESPCN-tiny (~500 KB), applied only when ROI pixel-count is below a learned threshold, before handing to the decoder.
- Feeds the same ROI dedup contract that `core-libdmtx-android-roi` defined — fused with the libdmtx ROIs and full-frame results.
- Tier-aware: detector runs on tier-mid+; SR runs only on tier-high or when the user explicitly opts in (high-stakes scan flows).
- Budget: ~2.5 MB bundled.

## Out of scope
- Replacing the decoder. The detector proposes; existing decoders (ML Kit / Vision / zxing-cpp) still decode.
- Training pipeline — that lives in a separate internal tooling repo.

## Acceptance
- [ ] DM read rate on the small/damaged fixture set improves ≥ 15% on top of the libdmtx ROI gain.
- [ ] Per-frame detector cost ≤ 10 ms on tier-mid; SR ≤ 8 ms on tier-high.
- [ ] No DM duplicates in the fused output stream.

## Dependencies
- [ml-runtime-and-loader](ml-runtime-and-loader.md), [core-libdmtx-android-roi](core-libdmtx-android-roi.md), [core-libdmtx-ios-bridge](core-libdmtx-ios-bridge.md).

## Source
- This conversation's ML roadmap.
