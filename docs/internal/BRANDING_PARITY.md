# Branding Parity — Batch Barcode Scanner

Audit + implementation notes for visual parity between the iOS and Android full-screen batch barcode UIs. These two surfaces are the only native chrome we hand-roll — the embedded `SupyBarcodeScannerView` (PlatformView with Flutter overlay) and the document scanner (OS-owned `VNDocumentCameraViewController` / `GmsDocumentScanner`) are out of scope.

Files:
- iOS: `ios/Classes/barcode/BatchBarcodeScannerPresenter.swift`
- Android: `android/src/main/kotlin/io/supy/scanner/barcode/BatchBarcodeScannerActivity.kt`

---

## Brand tokens (single source of truth: `SupyScannerPalette.scanbotDark`)

| Token | Value | iOS literal | Android literal |
|---|---|---|---|
| `primary` (Done bg) | `#1AC0E5` | `UIColor(red: 0x1A/255, green: 0xC0/255, blue: 0xE5/255, alpha: 1)` | `0xFF1AC0E5.toInt()` (`SUPY_PRIMARY`) |
| `onPrimary` / `onSurface` (text) | `#FFFFFF` | `.white` | `Color.WHITE` |
| scrim (counter + Cancel bg) | `#000000` @ alpha 0.55 (140/255) | `UIColor.black.withAlphaComponent(0.55)` | `0x8C000000.toInt()` (`SCRIM_BLACK_055`) |
| `surface` (root bg) | `#000000` | `.black` | `Color.BLACK` |

The two native files hardcode these literals — they cannot reach the Dart `SupyScannerPalette` from native batch context (the batch flow doesn't carry palette args over the channel today). Keep them in sync via the constant blocks at the top of each file. If the palette ever ships over the channel for batch, swap these constants for the wire-supplied values and delete the hardcodes.

## Layout parity

| Surface | iOS | Android | Status |
|---|---|---|---|
| Root background | `.black` | `Color.BLACK` | ✅ |
| Counter position | top-center, safe-area + 16pt | top-center, status-bar inset + 16dp | ✅ aligned |
| Counter shape | pill, corner radius 14 | pill (`GradientDrawable`), corner radius 14dp | ✅ aligned |
| Counter bg | `black @ 0.55` | `0x8C000000` (≈0.55) | ✅ aligned |
| Counter text | white, semibold 17pt | white, BOLD 17sp | ✅ aligned |
| Counter min width | 120pt | 120dp `minimumWidth` | ✅ aligned |
| Counter padding | leading/trailing space chars inside text | real 16dp horizontal padding | OK — visually equivalent; iOS pads in text because UILabel has no horizontal padding API |
| Cancel chip | pill (radius 22), `black @ 0.55`, white regular 17pt, leading-bottom safe-area + 20pt / -24pt | pill (radius 22dp), `0x8C000000`, white 17sp, start-bottom 20dp / 24dp | ✅ aligned |
| Done chip | pill (radius 22), Supy teal bg, white semibold 17pt, trailing-bottom safe-area + 20pt / -24pt | pill (radius 22dp), Supy teal bg, white BOLD 17sp, end-bottom 20dp / 24dp | ✅ aligned |
| Status bar | hidden (`prefersStatusBarHidden = true`) | not hidden — counter offset by status-bar inset instead | Behavioral diff retained: Android keeps system status bar visible by design (gestures, time) |

## Feedback parity

| Channel | iOS | Android | Status |
|---|---|---|---|
| Beep | `AudioServicesPlaySystemSound(1057)` ("Tink") | `ToneGenerator.TONE_PROP_BEEP` vol 80, 120ms | Different waveform, equivalent UX |
| Haptic | `UIImpactFeedbackGenerator(.medium)` | `VibrationEffect.createOneShot(40ms, DEFAULT_AMPLITUDE)` | Equivalent |

## Counter text format

| Mode | iOS | Android |
|---|---|---|
| Capped | `  N / M  ` (space-padded inside UILabel) | `N / M` (padding via view) |
| Uncapped | `  N  ` | `N` |

Visually equivalent — UILabel has no horizontal padding API on iOS, so space characters carry the same intent the `setPadding(...)` call serves on Android.

## What was changed in this pass

iOS (`BatchBarcodeScannerPresenter.swift`):
- Done button background: `view.tintColor` (system blue) → Supy teal `#1AC0E5`.

Android (`BatchBarcodeScannerActivity.kt`):
- Replaced stock Material `Button` widgets with `TextView`-based pill chips so the corner radius, fill color, padding, and typography match the iOS treatment.
- Counter moved from top-start to top-center; min width 120dp added.
- Counter background alpha changed from `0x A0 (160/255 ≈ 0.63)` to `0x 8C (140/255 ≈ 0.55)` to match iOS.
- Counter text bumped from 16sp default-weight to 17sp BOLD.
- Counter top margin switched from a fixed 48dp to `16dp + statusBarInset()` so it sits below the status bar at the same visible offset iOS uses against the safe-area.
- Brand color + scrim added as named constants in the companion object.
- Removed the `LinearLayout` controls row + `Button` + `LinearLayout` imports (cancel chip now positions itself directly).

## What was intentionally NOT changed

- Document scanner UIs (iOS VisionKit, Android GMS) — vendor-owned chrome, cannot be reskinned without losing the system flow.
- Embedded `SupyBarcodeScannerView` — already palette-driven via Flutter overlay; parity is structural.

---

## Document Scanner (embedded `SupyDocumentScannerView`)

As of the 2026-06-14 smart-guidance branch, the embedded document overlay is
**in parity scope**. Unlike the batch barcode surfaces above, the document
overlay is pure Dart (`lib/src/widgets/supy_document_scanner_view.dart`) — it
reads color tokens directly from `SupyScannerPalette` via
`SupyDocumentGuidanceConfiguration`. There are **no hardcoded color literals
in the library** for this surface; the example-app `#6448C3` purple is a
consumer theme override in `example/` and must never migrate into library
defaults.

| Element | Literal | Source |
|---|---|---|
| Corner reticles (no-document state) | `palette.warning` — `#FF4D4D` | `SupyScannerPalette.warning` |
| Corner brackets (failure / holdSteady states) | `palette.warning` — `#FF4D4D` | `SupyScannerPalette.warning` |
| Corner brackets (ready state) | `palette.primary` — `#1AC0E5` | `SupyScannerPalette.primary` |
| Ring countdown stroke | `palette.primary` — `#1AC0E5` | `SupyScannerPalette.primary` |
| Capture flash | `Colors.white`, 80 ms fade-in + 80 ms fade-out | Hardcoded — flash is always white (system convention) |
| Hint pill scrim | `black @ 0.55` | Mirrors batch barcode counter (`SCRIM_BLACK_055`) |

**Note:** Document overlay literals route through `SupyScannerPalette` via
the Dart `SupyDocumentGuidanceConfiguration` parameter, rather than through
native-side constant duplication. This is possible because the entire overlay
is a Flutter `CustomPainter` — no native chrome is involved. Consumers who
supply a custom `SupyScannerPalette` to `SupyDocumentGuidanceConfiguration`
get full rebranding without forking the library.

The `warning` color (`#FF4D4D`) is a new token added to `SupyScannerPalette`
(field `final Color warning`, default `const Color(0xFFFF4D4D)`). Both
`scanbotDark` and `scanbotLight` named constructors set it to `#FF4D4D`.
- String localization — "Cancel" / "Done" remain hardcoded English on both sides. Retailer consumer does not localize these strings today; tracked as a follow-up if a non-English locale enters scope.
- Channel surface — no wire-format changes; `BatchBarcodeScannerLauncher.kt` and the iOS presenter args are untouched.

## Verification

Walk `docs/QA.md` § batch barcode on both a physical iPhone and a physical Android. Confirm side-by-side:
1. Counter appears top-center on both.
2. Cancel chip is rounded, dark translucent, white text — not a Material raised button.
3. Done chip is rounded, Supy teal (`#1AC0E5`), white bold text — not system blue, not Material.
4. Tapping each behaves identically (Cancel → `cancelled`; Done → success payload).
