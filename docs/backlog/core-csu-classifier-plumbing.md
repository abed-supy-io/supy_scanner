# core-csu-classifier-plumbing

**Status:** planned · **Target:** v1.3.0 · **Effort:** M · **Trace:** PLAN.md Phase CSU3

## Problem
Phase CSU needs the live classifier (document vs. not-a-document, glare, blur) plumbed from the C++ core to the new capture UIs on both platforms so the hint overlay reacts in real time.

## Scope
- Stream classifier verdicts from `supy_core_score_page` over a per-view EventChannel.
- Throttle to ≤ 15 Hz; collapse identical consecutive verdicts.
- Render-side: provide a Dart-typed `SupyCaptureHint` sealed class.

## Out of scope
- Custom UI rendering (consumers theme it).
- Adding new score axes — start with what `supy_core_score_page` already returns.

## Acceptance
- [ ] EventChannel verified by integration test (mock frames → expected verdicts).
- [ ] No event-storm under steady scene (≤ 2 events/s).

## Dependencies
- [core-csu-ios-avcapture](core-csu-ios-avcapture.md), [core-csu-android-camerax-default](core-csu-android-camerax-default.md).

## Source
- `docs/PLAN.md` — Phase CSU3.
