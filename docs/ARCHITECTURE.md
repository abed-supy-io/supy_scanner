# Architecture

## Layering

```
┌───────────────────────────────────────────────┐
│  Retailer app (supy-mobile)                   │
│  - feature pages call SupyBarcodeScannerView  │
│  - feature pages call SupyInvoiceScannerService│
└──────────────────┬────────────────────────────┘
                   │
┌──────────────────▼────────────────────────────┐
│  supy_scanner_scanbot_compat (optional shim)  │
│  - BarcodeScanbotView = SupyBarcodeScannerView│
│  - BarcodeItem        = SupyBarcode           │
│  - InvoiceScannerService(impl with SupyScanner)│
└──────────────────┬────────────────────────────┘
                   │
┌──────────────────▼────────────────────────────┐
│  supy_scanner (Dart)                          │
│  ┌────────────────┐  ┌─────────────────────┐ │
│  │ widgets/        │  │ services/           │ │
│  │  BarcodeView    │  │  DocumentScanner    │ │
│  │  Controller     │  │  InvoiceScannerSvc  │ │
│  └────────┬───────┘  └─────────┬───────────┘ │
│           │                    │              │
│  ┌────────▼────────────────────▼───────────┐ │
│  │ channel/                                │ │
│  │  MethodChannel('io.supy.scanner/v1')    │ │
│  │  EventChannel('.../barcode/<viewId>')   │ │
│  └────────┬────────────────────────────────┘ │
└───────────┼──────────────────────────────────┘
            │
┌───────────▼────────────────┐  ┌──────────────────────────────┐
│  Android (Kotlin)           │  │  iOS (Swift)                 │
│  ├ CameraX preview          │  │  ├ AVCaptureSession          │
│  ├ ML Kit Barcode           │  │  ├ Vision VNDetectBarcodes   │
│  ├ GMS Document Scanner     │  │  ├ VisionKit VNDocumentCamera│
│  └ ML Kit Text Recognition  │  │  └ Vision VNRecognizeText    │
└─────────────────────────────┘  └──────────────────────────────┘
```

## Module responsibilities

### Dart layer

| Module | Responsibility |
|---|---|
| `models/` | Frozen value types — `SupyBarcode`, `SupyBarcodeFormat`, `SupyDocumentData`, `SupyDocumentPage`, `SupyScanOptions`, `SupyScanError`. |
| `channel/method_channel.dart` | Single point of `MethodChannel('io.supy.scanner/v1')` access. All native calls go through here. |
| `channel/event_channel.dart` | Per-view EventChannel for barcode detections. |
| `widgets/supy_barcode_scanner_view.dart` | The `StatefulWidget` that composes an `AndroidView`/`UiKitView`, a finder overlay, and slot Stack for header/footer. |
| `widgets/supy_barcode_scanner_controller.dart` | Holds pause/torch state, talks to the per-view MethodChannel. |
| `services/supy_document_scanner.dart` | Static entrypoint `startMultiPage(...)` and `prewarm()`. |
| `services/supy_permissions.dart` | Thin wrapper over `permission_handler` for camera permission. |

### Android layer

| File | Responsibility |
|---|---|
| `SupyScannerPlugin.kt` | `FlutterPlugin` lifecycle, registers `BarcodeScannerViewFactory`, hosts the document MethodCallHandler. |
| `barcode/BarcodeScannerView.kt` | Implements `PlatformView`, builds a `PreviewView` + `LifecycleCameraController`, attaches an `ImageAnalysis` analyzer wired to `BarcodeScanning.getClient(...)`. Streams to EventChannel. |
| `barcode/BarcodeScannerViewFactory.kt` | `PlatformViewFactory` — wires creation params (formats, finder, etc.). |
| `barcode/FormatMapper.kt` | `SupyBarcodeFormat` ↔ ML Kit `Barcode.FORMAT_*` mapping. |
| `document/DocumentScannerLauncher.kt` | Calls `GmsDocumentScanning.getClient(...)` and `startScanIntent(...)`, awaits result via `ActivityResultLauncher`. |
| `document/OcrRunner.kt` | Loops `TextRecognition.getClient(...)` over JPEGs, concatenates results. |

### iOS layer

| File | Responsibility |
|---|---|
| `SupyScannerPlugin.swift` | `FlutterPlugin` registration; registers `BarcodeScannerViewFactory`; hosts document MethodCallHandler. |
| `barcode/BarcodeScannerPlatformView.swift` | `FlutterPlatformView` wrapping a `UIView` with `AVCaptureVideoPreviewLayer`. Runs `VNDetectBarcodesRequest` from a video output. |
| `barcode/BarcodeScannerViewFactory.swift` | Creation params bridge. |
| `barcode/SymbologyMapper.swift` | `SupyBarcodeFormat` ↔ `VNBarcodeSymbology`. |
| `document/DocumentScannerPresenter.swift` | Presents `VNDocumentCameraViewController` over the Flutter root VC. Writes JPEGs to `NSTemporaryDirectory()`. |
| `document/OcrRunner.swift` | `VNRecognizeTextRequest` with `recognitionLevel = .accurate`. |

## Platform channel contract

### `io.supy.scanner/v1` (global MethodChannel)

| Method | Args | Returns | Errors |
|---|---|---|---|
| `scanDocument` | `{ maxPages: int, ocrLanguages: [string], jpegQuality: int (0-100), locale: 'en' \| 'ar', palettePrimary: '#RRGGBB', paletteOnPrimary: '#RRGGBB' }` | `{ pages: [{ uri: string, width: int, height: int }], ocrText: string }` | `cancelled`, `permission_denied`, `model_unavailable`, `unknown` |
| `scanBarcodesBatch` | `{ formats: [string], maxBatchCount: int (0=unlimited), dedupeWindowMs: int, beep: bool, vibrate: bool }` | `{ items: [{ rawValue: string, format: string }], duplicateCount: int }` | `cancelled`, `permission_denied`, `camera_unavailable`, `unknown` |
| `prewarm` | `{}` | `{}` | `unknown` |
| `requestCameraPermission` | `{}` | `{ status: 'granted' \| 'denied' \| 'permanentlyDenied' }` | — |

### `io.supy.scanner/v1/barcode/<viewId>` (per-view MethodChannel)

| Method | Args | Returns |
|---|---|---|
| `pause` | — | `{}` |
| `resume` | — | `{}` |
| `setTorch` | `{ on: bool }` | `{}` |
| `setFormats` | `{ formats: [string] }` | `{}` |

### `io.supy.scanner/v1/barcode/<viewId>/events` (EventChannel)

Stream of:
- `{ type: 'detection', items: [{ rawValue, format, boundingBox: { left, top, width, height } | null }] }`
- `{ type: 'preview_started', flashAvailable: bool }`
- `{ type: 'error', code, message }`

## Threading

- **Barcode detection** runs on a background thread on both platforms. Detection callbacks are marshalled to Flutter via EventChannel (which already hops to the main thread before delivery).
- **OCR** runs on a background dispatch queue (iOS) / coroutine (Android).
- **Document JPEG writes** happen off the main thread; the channel callback fires after all writes complete.

## Permissions

- **Camera (iOS):** `NSCameraUsageDescription` required in host app's `Info.plist`. Documented in `docs/MIGRATION.md`.
- **Camera (Android):** `android.permission.CAMERA` declared in plugin's `AndroidManifest.xml`. Runtime request handled in Dart via the existing `permission_handler` integration the retailer already uses.

## Error model

All native errors surface as `PlatformException` and are caught in `channel/method_channel.dart`, then wrapped into `SupyScanError` with a stable `code`:

| Code | Meaning |
|---|---|
| `cancelled` | User cancelled the scan (back button, swipe down). |
| `permission_denied` | Camera permission not granted. |
| `camera_unavailable` | No usable camera (simulator with no host camera). |
| `model_unavailable` | ML Kit Document Scanner model not downloaded and no network. |
| `format_unsupported` | Requested barcode format not supported on this platform. |
| `unknown` | Anything else — `message` carries the platform's description. |
