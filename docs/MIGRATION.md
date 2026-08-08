# Migration — Scanbot → supy_scanner

The migration reference for the retailer app. The non-negotiable constraint is
**drop-in API compatibility**: every call site keeps its signature and return
type; end users see no difference. If a change here would force the retailer to
rename a prop, add a required argument, or change a return type, it is a bug in
this library, not a migration step.

> **One logged exception (Phase PAID — see `../TODO.md` decisions log).**
> `supy_scanner` is now a paid, Supy-licensed library. The app must call
> `SupyScanner.activate(<license token>)` once at startup before any scan; scan
> APIs throw until it succeeds. This is a bootstrap-time addition, not a
> per-call-site change — individual call-site signatures and return types are
> unchanged. Enforcement is an on-device signed-token check; **no network call
> is added to the scanning path.**

> Scope note: the per-field Scanbot RTU-config → `Supy*Configuration` mapping
> table is tracked separately as **D6-2** and is not yet in this doc. What is
> documented below is the set of entry points the retailer calls and the
> **fallback contract** — when an unbranded/native surface can still appear.

## Entry points

| Retailer call site | supy_scanner entry point | Returns |
|---|---|---|
| Single barcode scan | embedded `SupyBarcodeScannerView` / `SupyBarcodeScanner` single-scan | `SupyBarcode?` |
| Batch / multiple barcode | `SupyBarcodeScanner.startMultiple(context, …)` | `SupyBatchBarcodeResult?` |
| Document multi-page (`InvoiceScannerService.scanWithCamera`) | `SupyDocumentScanner.startMultiPage(context, …)` | `SupyDocumentData?` |

`null` on any of these means the user cancelled without keeping anything —
identical to the native scanner's "cancelled" terminal outcome.

## Document export formats (DC8)

`SupyDocumentScanOptions.outputFormat` is an **additive** enum —
`SupyDocumentData`'s existing fields are unchanged, so no retailer call site
moves. `jpg` (default), `png`, and `pdf` behave exactly as before; DC8 adds two
values:

| `outputFormat` | Where the result lands | Notes |
|---|---|---|
| `tiff` | new `SupyDocumentData.tiffUri` | Multi-page, uncompressed baseline RGB. `pdfUri` stays `null`. |
| `searchablePdf` | existing `SupyDocumentData.pdfUri` | A normal PDF with an **invisible but selectable** OCR text layer. Same field as a plain `pdf`, so retailers that already read `pdfUri` need no change. |

`tiffUri` is a new nullable field: it is `null` unless `outputFormat: tiff` was
requested, so existing consumers that never touch it are unaffected. The wire
encoding is the enum's `.name` (`tiff` / `searchablePdf`); older payloads that
omit the field decode to `null`.

**Platform parity.** Both formats are produced fully on-device with **no new
native dependency** and **no channel-version bump** (`io.supy.scanner/v1`
stays):

- iOS assembles TIFF via ImageIO (`CGImageDestination`) and the searchable PDF
  via `UIGraphicsPDFRenderer`, drawing each OCR word in `UIColor.clear`.
- Android assembles TIFF with a pure-Kotlin `TiffAssembler` and the searchable
  PDF with `PdfDocument`, drawing the OCR text layer at `alpha=0`.

The searchable PDF is **always self-assembled** from the page images plus the
OCR word boxes (a single OCR pass) — the platform's native PDF export is not
used for `searchablePdf`, because it carries no selectable text layer. The
invisible-text geometry inherits the same Arabic-OCR gap noted below: on
Android, Arabic word boxes are absent, so an Arabic document's searchable PDF
has selectable text only for Latin runs.

## Document enhancement tuning (Phase DPX)

`SupyDocumentScanOptions` gains one **additive**, nullable field —
`processing`, of the new public type `SupyDocumentProcessingOptions`. It is
`null` by default, and when null the field is **omitted from the wire entirely**,
so every existing Scanbot-compat call site is byte-for-byte unchanged and keeps
its current behaviour. No retailer call site moves; this is not a compat break.

`SupyDocumentProcessingOptions` is an `@immutable` value type (full `==` /
`hashCode` / `toString`) exposing the shared native pipeline's stage toggles:

| Field | Default | Effect |
|---|---|---|
| `detectDocument` | `true` | Document detection. |
| `perspectiveCorrection` | `true` | Warp from the detected quad. |
| `autoCrop` | `true` | Crop to the document plus `cropMargin`. |
| `cropMargin` | `0.02` | Fractional margin kept around the crop. |
| `deskew` | `true` | Small-angle straighten. |
| `shadowRemoval` | `true` | Illumination flatten. |
| `backgroundWhitening` | `true` | Color-safe paper whitening. |
| `denoise` | `true` | Edge-preserving denoise. |
| `sharpen` | `true` | Halo-safe unsharp mask. |
| `maxDimension` | `2200` | Longest-edge export cap in px (`0` = no resize). |
| `enhancement` | `null` | `SupyDocumentFilter` override; when null falls back to the outer `filter`. |
| `quality` | `null` | JPEG quality override; when null falls back to the outer `jpegQuality`. |

Leaving `processing` null means native applies its `DocumentProcessingOptions.default`
(the full pipeline) with the caller's top-level `filter`/`jpegQuality` — so
existing callers automatically inherit the improved enhancement without any code
change. The field is serialized under a nested `processing` key
(see `docs/ARCHITECTURE.md`). No channel-version bump (`io.supy.scanner/v1` stays).

### Platform ownership of the stages

The `processing` map is one wire contract, but the two platforms divide the
work differently:

- **iOS** owns every stage in the shared Swift `DocumentProcessor`, so all
  toggles (`detectDocument` … `sharpen`) are independently honoured.
- **Android** performs detection, perspective correction and cropping
  **upstream** in the GMS document scanner (or the `CameraX*` fallback), then
  runs the shared pure-Kotlin tail (`PageReencoder`): **smart resize
  (`maxDimension`) → native enhance → output `filter`**. The native enhance is
  a single bundled `EnhanceMode` rather than per-stage filters, so
  `shadowRemoval`/`backgroundWhitening`/`denoise`/`sharpen` are collapsed onto
  it — turning **all** of them off (or selecting the `original` filter) skips
  the enhance pass; otherwise the bundled pass runs. The upstream
  `detectDocument`/`perspectiveCorrection`/`autoCrop`/`cropMargin`/`deskew`
  fields are parsed for wire parity but are owned by GMS and not individually
  toggleable on Android.

Both platforms apply the same `maxDimension` export cap, `quality`, and the
`color`/`grayscale`/`blackAndWhite`/`original` filter, so a given `processing`
map yields the same *kind* of output on both. Known Android gap: the embedded
`captureFullFrame` fast path returns the raw frame without the `processing`
tail (documented in `docs/ARCHITECTURE.md`); use the rectified capture path for
enhanced output.

## Fallback contract (Track D / D1)

As of Track D **D1**, all four use-cases (single, find-and-pick, document,
batch) are drawn by the **Supy-branded Flutter session** composited over the
native camera preview **by default on Android and iOS**. The native full-screen
surfaces (VisionKit / GMS / `CameraX*Activity`; the batch
`*Presenter`/`*Activity`) are demoted to explicit, documented fallbacks — never
the surface the retailer sees by default.

A native / unbranded surface can still appear in exactly these cases:

- **Non-mobile platform** — `kIsWeb` or desktop. There is no embedded
  PlatformView there, so both `SupyBarcodeScanner.startMultiple` and
  `SupyDocumentScanner.startMultiPage` fall back to the native channel methods
  (`scanBarcodesBatch` / `scanDocument`). This is the common case in practice,
  since the retailer app is mobile-only.
- **Document `invoice` intent** — `SupyDocumentScanner.startMultiPage(intent:
  SupyDocumentScanIntent.invoice)` needs native OCR + PDF assembly, which are
  native-only, so it stays on the native `scanDocument` path. The default
  `generic` intent (what `InvoiceScannerService.scanWithCamera` uses) is
  branded.
- **Capability failure** — camera permission denied, no Play Services for the
  GMS document path, or a device-tier gate. Selection is internal; no new
  required args.

Fallback selection is **internal** — no public signature changed and the
channel stays additive on `io.supy.scanner/v1` (no `v2` bump). The branded path
is pure Dart over the existing per-view channels; the native methods are
untouched.

### Palette & locale on the branded path

The embedded branded session **honors `palette` and `locale`**, superseding the
earlier S3-04 note that these were no-ops on the launcher path. A palette swap
re-skins the branded screens; guidance/label copy resolves for the ambient
locale (`en` / `ar`).

### Batch specifics

`SupyBarcodeScanner.startMultiple` adapts the branded accumulator to the native
`SupyBatchBarcodeResult` shape:

- `items` — the distinct payloads (one per accumulator row, first-seen order).
- `duplicateCount` — every detection beyond the first, i.e.
  `sum(counts) − uniqueRows`. The branded session runs in
  `SupyMultipleScanMode.counting` so repeat detections are tracked; in `unique`
  mode `duplicateCount` would always be `0`. `options.dedupeWindowMs` maps onto
  the counting debounce.
- **Known gap:** `SupyBatchBarcodeScanOptions.maxBatchCount` is **not enforced
  on the branded path** — the multi-scan accumulator has no hard cap. It is
  still honored on the native fallback. If a hard cap on the branded path is
  required, it is a follow-up item, not a silent behavior.

## Data Capture platform parity (DC track)

The Data Capture parity track (DC0–DC8) is additive to the public surface — no
retailer call site changed — but a few capabilities differ by platform. None of
these is a signature change; they are behavioral notes for whoever consumes the
new APIs.

### Barcode symbologies (DC1)

Five formats — `dataBar`, `dataBarExpanded`, `microQr`, `rMQR`, `maxiCode` —
decode **only on the native-core path** (`useNativeCore: true`, the zxing-cpp
decoder). On the platform-default ML Kit (Android) / Vision (iOS) path they are
reported `format_unsupported`. Retailers that need them must opt into the native
core for that scan.

Four Scanbot symbologies remain **infeasible** on every engine in the stack
(zxing-cpp / ML Kit / Vision) and are **not** implemented: Code 11, MSI Plessey,
Pharmacode, and postal codes. They stay documented `format_unsupported` gaps
(see `SYMBOLOGIES.md`), not buildable formats.

### OCR / text recognition (DC3–DC8)

OCR is on-device — Apple Vision on iOS, Google ML Kit on Android — and the two
engines do not cover the same scripts:

- **Latin** (incl. OCR-B): both platforms. So **MRZ** (DC4) and **VIN** (DC5)
  parse on iOS and Android alike, since both alphabets are Latin.
- **Arabic:** iOS Vision only. Android ML Kit is **Latin-only** and returns no
  Arabic text/word boxes. Consequences:
  - **ID front-side fields** (DC6): Arabic front-of-card fields come back empty
    on Android; the check-digit-validated MRZ back side still works on both.
  - **Live text-pattern scanner** (DC7): the frame OCR stream carries no Arabic
    on Android, so Arabic patterns never match there.
  - **Searchable PDF** (DC8): the invisible text layer is built from the same
    word boxes, so an Arabic document's searchable PDF has selectable text only
    for Latin runs on Android (full coverage on iOS).

## Compat shim (`supy_scanner_scanbot_compat`)

The compat package preserves the retailer's Scanbot call shapes verbatim while
routing to the branded Supy paths:

- **Barcode / counting** (`BarcodeScanbotView`, `BarcodeScannerController`) —
  renders the embedded branded `SupyBarcodeScannerView`; already branded.
- **Document** (`InvoiceScannerService.scanWithCamera`) — routes through
  `SupyDocumentScanner.startMultiPage`, so the retailer's document call site
  gets the branded embedded session on mobile (native scanner as the internal
  fallback per the contract above). The optional `channel` constructor argument
  is a **test-only seam**: injecting a `SupyScannerChannel` keeps the direct
  native call for deterministic mocked tests; the production no-arg form is
  branded.

No compat public signature changed — the API snapshot
(`test/api_snapshot.txt`) and retailer call-site suites stay green.

### Out-of-shim retailer references

A few retailer files touch Scanbot surfaces the Supy backend does not
reproduce, so they are **not** part of this shim:

- `scanbot_sdk_manager.dart` — Scanbot license init / SDK bootstrap. Supy has
  its **own** license concept (Phase PAID): replace Scanbot's init with a
  one-time `SupyScanner.activate(<license token>)` at app startup. It is not a
  drop-in for Scanbot's `ScanbotSdk.initScanbotSdk(...)` signature — wire it in
  the retailer's bootstrap directly. Verification is on-device (offline
  signed-token check); the token is fetched once from the licensing backend.
- `scanning_bot.dart` — Scanbot document-UI v2 types
  (`DocumentScanningFlow`, `ScanbotSdkUiV2`, `ScanbotColor`). The Supy document
  flow is driven by `SupyDocumentScanner` / `SupyDocumentScannerScreen` and its
  `Supy*Configuration` models instead; the RTU-config → `Supy*Configuration`
  field mapping is tracked as D6-2.

These are removed at the retailer call site during migration, not adapted here.
