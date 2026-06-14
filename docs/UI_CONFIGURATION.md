# UI Configuration — `SupyBarcodeScannerScreen`

Reference for the v1.1 Sprint 1.5 Scanbot-RTU-UI-parity configuration surface. The full-screen `SupyBarcodeScannerScreen` composes a single `MethodChannel`-backed preview (`SupyBarcodeScannerView`) with a stack of configurable UI layers. Every layer is driven by a `@immutable` value type — no `dynamic`, no maps.

This document is the source of truth for **what knobs exist and what they do**. The Scanbot-RTU-UI → `supy_scanner` mapping table lives in `docs/MIGRATION.md`.

## Anatomy

```
┌─────────────────────────────────────────┐
│  SupyTopBar                  (cancel)   │  ← SupyTopBarConfiguration
├─────────────────────────────────────────┤
│                                         │
│      SupyFinderPainter   (corners)      │  ← SupyViewFinderConfiguration
│           ┌─────────┐                   │
│           │         │                   │
│           │ preview │                   │  ← SupyBarcodeScannerView (showFinder: false)
│           │         │                   │
│           └─────────┘                   │
│      SupyArOverlay        (boxes)       │  ← SupyArOverlayConfiguration
│                                         │
│      SupyUserGuidanceCard               │  ← SupyUserGuidanceConfiguration
├─────────────────────────────────────────┤
│  SupyActionBar  (torch/zoom/flip/focus) │  ← SupyActionBarConfiguration
├─────────────────────────────────────────┤
│  Bottom sheet (use-case-driven)         │  ← SupyScanUseCase variant
└─────────────────────────────────────────┘
```

## Top-level screen

| Prop | Type | Default | Purpose |
|---|---|---|---|
| `useCase` | `SupyScanUseCase` (sealed) | — (required) | Drives sheet + result-callback routing. |
| `scanOptions` | `SupyBarcodeScanOptions` | `const ...()` | Formats, scan window, camera config, native-core flag. |
| `palette` | `SupyScannerPalette` | `scanbotDark()` | 16-token color palette (see §Palette). |
| `topBar` | `SupyTopBarConfiguration` | `const ...()` | Cancel button + scrim. |
| `viewFinder` | `SupyViewFinderConfiguration` | `const ...()` | Cornered finder painter. |
| `userGuidance` | `SupyUserGuidanceConfiguration` | `const ...()` | "Point at barcode" card. |
| `actionBar` | `SupyActionBarConfiguration` | `const ...()` | Flash / zoom / flip / close-focus. |
| `arOverlay` | `SupyArOverlayConfiguration` | `const ...()` | Per-barcode bounding boxes + label chips. |
| `controller` | `SupyBarcodeScannerController?` | `null` | Externally-owned controller; screen owns its own when omitted. |
| `onSingleScan` | `ValueChanged<SupyBarcode>?` | — | Fires on confirm (or first detection if confirm sheet disabled). |
| `onMultipleScan` | `ValueChanged<List<SupyMultipleScanItem>>?` | — | Fires when user submits the multi-scan sheet. |
| `onFindAndPick` | `ValueChanged<List<SupyFindAndPickRow>>?` | — | Fires when user submits a complete pick. |
| `onCancel` | `VoidCallback?` | — | Top-bar cancel. |
| `onError` | `ValueChanged<Object>?` | — | Native error surface. |

## Use-case variants

`SupyScanUseCase` is a sealed Dart 3 class. Pick one variant — the screen wires the corresponding sheet and result callback.

### `SupySingleScanUseCase`

Pauses preview on first detection. With `confirmationSheetEnabled: true` (default), shows `SupySingleScanConfirmationSheet`; user taps **Submit** to fire `onSingleScan` or **Retry** to resume the preview. With `confirmationSheetEnabled: false`, the first detection is returned immediately — drop-in behaviour for callers migrating from Scanbot's `SingleScanningMode` with confirmation disabled.

Config (`SupySingleScanUseCaseConfiguration`): `title`, `showBarcodeFormat`, `showRawValue`, `confirmButtonText`, `retryButtonText`, and a set of colors (`sheetBackgroundColor`, `titleColor`, `bodyColor`, `confirmButtonBackgroundColor`, `confirmButtonForegroundColor`, `retryButtonForegroundColor`).

### `SupyMultipleScanUseCase`

Keeps scanning until the user submits. Two modes:

- **`counting`** — same `rawValue` increments a count; subsequent detections of the same value within `countingRepeatDelay` (default 1s) are debounced.
- **`unique`** — same `rawValue` is recorded once and de-duplicated.

Backed by a headless `SupyMultipleScanAccumulator` (`ChangeNotifier`) that the sheet observes via `AnimatedBuilder`.

### `SupyFindAndPickUseCase`

Scan against a known pick-list (`List<SupyExpectedBarcode>`). Each row tracks progress (`pickedCount` capped at `expectedCount`); the sheet's **Submit** button is gated on every row being complete (`SupyFindAndPickAccumulator.isComplete`). Set `allowUnexpected: true` to surface non-pick-list scans as warnings instead of ignoring them.

## Layer configs

### `SupyTopBarConfiguration`

Top scrim + close button. Style: `solid` or `gradient`. Knobs: `visible`, `style`, `backgroundColor`, `gradientColors`, `cancelIconColor`, `cancelTooltip`, `height`.

### `SupyViewFinderConfiguration`

Cornered finder painted via `SupyFinderPainter` (a `CustomPainter`). Knobs: `visible`, `width`, `height` (or `aspectRatio`), `cornerLength`, `cornerStrokeWidth`, `cornerColor`, `overlayColor` (dim outside the finder).

### `SupyUserGuidanceConfiguration`

Pill-shaped guidance card. Knobs: `visible`, `text`, `backgroundColor`, `foregroundColor`, `padding`.

### `SupyActionBarConfiguration`

Bottom action row wired to the controller. Knobs: `visible`, `flashEnabled`, `zoomEnabled`, `flipCameraEnabled`, `closeFocusEnabled`, `buttonColor`, `activeButtonColor`. Each button is a `SupyActionButtonSpec` so callers can override individual icons / tooltips.

### `SupyArOverlayConfiguration`

Painted RRect bounding boxes + label chips over each detected barcode (normalized `[0..1]` coordinates from native). Knobs: `enabled`, `strokeColor`, `fillColor`, `strokeWidth`, `cornerRadius`, `showLabel`, `labelStyle`, `labelBackgroundColor`. Label chips auto-flip inside the box when there's no room above.

### `SupyCameraConfiguration`

Set on `SupyBarcodeScanOptions.camera`. Knobs: `initialZoom`, `minFocusDistanceLock` (iOS `AVCaptureDevice.AutoFocusRangeRestriction = .near`), `scanRange` (`normal` / `extended` — wired to the v1.1 native core when `useNativeCore: true`).

## Palette

`SupyScannerPalette` is a frozen value type with **16 named color tokens**. Two const factories — `SupyScannerPalette.scanbotDark()` and `SupyScannerPalette.scanbotLight()` — match Scanbot's RTU defaults. Tokens: `primary`, `primaryDisabled`, `onPrimary`, `secondary`, `secondaryDisabled`, `onSecondary`, `surface`, `surfaceLow`, `surfaceHigh`, `onSurface`, `onSurfaceVariant`, `outline`, `negative`, `positive`, `warning`, `modalOverlay`. Use `copyWith(...)` to override individual tokens on top of a preset. Pass to `SupyBarcodeScannerScreen.palette` to theme top-bar / sheets / overlays from one place.

## Quick recipes

### Single scan, no confirmation sheet (drop-in fast path)

```dart
SupyBarcodeScannerScreen(
  useCase: const SupySingleScanUseCase(
    config: SupySingleScanUseCaseConfiguration(
      confirmationSheetEnabled: false,
    ),
  ),
  onSingleScan: (b) => Navigator.pop(context, b.rawValue),
  onCancel: () => Navigator.pop(context),
)
```

### Multi-scan counting with a high-contrast palette

```dart
SupyBarcodeScannerScreen(
  useCase: const SupyMultipleScanUseCase(
    config: SupyMultipleScanUseCaseConfiguration(
      mode: SupyMultipleScanMode.counting,
    ),
  ),
  palette: const SupyScannerPalette.scanbotLight(),
  onMultipleScan: (items) => Navigator.pop(context, items),
)
```

### Find-and-pick against a 2-item pick list

```dart
SupyBarcodeScannerScreen(
  useCase: const SupyFindAndPickUseCase(
    config: SupyFindAndPickUseCaseConfiguration(
      expected: [
        SupyExpectedBarcode(rawValue: '1234567890123', expectedCount: 2, label: 'Item A'),
        SupyExpectedBarcode(rawValue: '9876543210',    expectedCount: 1, label: 'Item B'),
      ],
    ),
  ),
  onFindAndPick: (rows) => Navigator.pop(context, rows),
)
```

### Embedded document scanner with auto-capture (v1.1, Sprint 6)

`SupyDocumentScannerView` streams the FSM-driven guidance overlay
(`searching → aligning → ready`). When the host wants Scanbot-parity
auto-capture, drive `SupyDocumentScannerController.capture()` after the
view has held `ready` for `SupyDocumentScanOptions.autoCaptureDelayMs`
(default `800ms`; set to `0` to disable auto-capture and trigger captures
manually from a button).

```dart
final controller = SupyDocumentScannerController();

SupyDocumentScannerView(
  controller: controller,
  onGuidanceFrame: (frame) async {
    if (frame.state != SupyDocumentFrameState.ready) return;
    final page = await controller.capture();        // capturing → captured
    if (page == null) return;
    pages.add(page);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    controller.clearCapturePhase();                  // back to idle
  },
)
```

`capture()` is re-entrancy-safe (a second concurrent call returns `null`)
and resets `capturePhase` to `idle` on native error before rethrowing.
The view observes `controller.capturePhase` and overlays the `capturing`
/ `captured` hint copy + ready-color outline on top of FSM output for
the duration — the FSM itself stays stateless w.r.t. the capture
lifecycle.

See `example/lib/main.dart` → "Gallery" tab for runnable variants of each recipe.

---

## Supy Brand Demo (example app)

The example app ships a Supy-branded showcase tab (the first "Supy Demo" tab)
that demonstrates how to compose a `SupyScannerPalette` from product-level
brand tokens. The palette lives in `example/lib/branding/supy_brand.dart` —
**not** promoted to the library, since real brand tokens still wait on
design sign-off.

```dart
// example/lib/branding/supy_brand.dart
class SupyBrand {
  static const Color navy        = Color(0xFF0F1E3A); // top bar / headers
  static const Color accent      = Color(0xFF2F6BFF); // CTAs, focus ring
  static const Color accentSoft  = Color(0xFFE8EFFF); // soft tints
  static const Color surface     = Color(0xFFFFFFFF);
  static const Color surfaceAlt  = Color(0xFFF4F6FB); // page background
  static const Color success     = Color(0xFF1FB57A);
  static const Color warning     = Color(0xFFF0A91B);
  static const Color critical    = Color(0xFFE5484D);

  static const SupyScannerPalette palette = SupyScannerPalette(
    primary:           accent,
    primaryDisabled:   Color(0x802F6BFF),
    onPrimary:         Color(0xFFFFFFFF),
    secondary:         navy,
    secondaryDisabled: Color(0x800F1E3A),
    onSecondary:       Color(0xFFFFFFFF),
    surface:           surface,
    surfaceLow:        Color(0xCC0F1E3A),
    surfaceHigh:       surfaceAlt,
    onSurface:         Color(0xFF0F1E3A),
    onSurfaceVariant:  Color(0xB30F1E3A),
    outline:           Color(0x330F1E3A),
    negative:          critical,
    positive:          success,
    warning:           warning,
    modalOverlay:      Color(0x99000000),
  );
}
```

Pass `palette: SupyBrand.palette` to `SupyBarcodeScannerScreen` /
`SupyDocumentScannerView` — they paint the focus ring, hint pills, sheet
chrome, and capture overlay from those 16 slots.

Runnable flows under the "Supy Demo" tab:

| Flow | File |
|---|---|
| Single barcode | `example/lib/demo/supy_demo_single_barcode.dart` |
| Batch barcode | `example/lib/demo/supy_demo_batch_barcode.dart` |
| Embedded live view | `example/lib/demo/supy_demo_embedded_barcode.dart` |
| Document scan + OCR | `example/lib/demo/supy_demo_document.dart` |
