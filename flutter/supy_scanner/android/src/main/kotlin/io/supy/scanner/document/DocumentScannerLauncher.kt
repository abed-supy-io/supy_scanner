package io.supy.scanner.document

import android.app.Activity
import android.content.Intent
import android.net.Uri
import androidx.appcompat.app.AlertDialog
import io.supy.scanner.log.SupyLog
import com.google.android.gms.tasks.Task
import com.google.mlkit.vision.documentscanner.GmsDocumentScannerOptions
import com.google.mlkit.vision.documentscanner.GmsDocumentScanning
import com.google.mlkit.vision.documentscanner.GmsDocumentScanningResult
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry

/**
 * Launches the GMS Document Scanner intent, runs OCR over the captured pages,
 * and routes the activity result back to the pending `scanDocument`
 * MethodChannel call.
 *
 * OCR coverage on Android is Latin-script only — see [OcrRunner].
 */
class DocumentScannerLauncher : PluginRegistry.ActivityResultListener {

    private var pendingResult: Result? = null
    private var pendingActivity: Activity? = null
    private var pendingJpegQuality: Int = DEFAULT_JPEG_QUALITY
    private var pendingOutputFormat: PageReencoder.Format = PageReencoder.Format.JPG
    private var pendingWantPdf: Boolean = false
    private var pendingWantTiff: Boolean = false
    private var pendingWantSearchablePdf: Boolean = false
    private var pendingEnhanceMode: PageReencoder.EnhanceMode = PageReencoder.EnhanceMode.BALANCED
    private var pendingMaxDimension: Int = DocumentProcessingOptions.DEFAULT_MAX_DIMENSION
    private var pendingFilter: DocumentFilter = DocumentFilter.COLOR
    private var pendingResolvedBackend: String = BACKEND_UNKNOWN
    private var pendingMinPageQualityOrdinal: Int = 0
    private var pendingLocale: String = "en"
    private var pendingIntent: String = INTENT_GENERIC
    private val ocrRunner: OcrRunner = OcrRunner()

    /**
     * Delegates the standalone `recognizeText` channel call to the shared
     * [ocrRunner]. Reuses the launcher's single ML Kit recognizer instance
     * rather than spinning up a second Closeable. Errors if no Context is
     * available (activity detached).
     */
    fun recognizeText(
        context: android.content.Context?,
        uri: Uri,
        includeElements: Boolean,
        onComplete: (Map<String, Any?>) -> Unit,
        onError: (code: String, message: String) -> Unit,
    ) {
        if (context == null) {
            onError("model_unavailable", "recognizeText: no Activity context attached")
            return
        }
        ocrRunner.recognizeStructured(context, uri, includeElements, onComplete, onError)
    }

    /**
     * Touches the GMS Document Scanner client to trigger model download
     * (~10 MB on first use) and warms the ML Kit text recognizer. Safe to call
     * multiple times. No-op when no Activity context is available — Flutter
     * consumers should call after the engine attaches.
     */
    fun prewarm(context: android.content.Context?) {
        if (context == null) return
        val options = GmsDocumentScannerOptions.Builder()
            .setScannerMode(GmsDocumentScannerOptions.SCANNER_MODE_FULL)
            .setResultFormats(GmsDocumentScannerOptions.RESULT_FORMAT_JPEG)
            .build()
        // Building the client kicks off the model fetch in the background.
        GmsDocumentScanning.getClient(options)
    }

    @Suppress("UNCHECKED_CAST")
    fun launch(activity: Activity?, args: Map<String, Any?>?, result: Result) {
        if (activity == null) {
            result.error("camera_unavailable", "No Activity attached", null)
            return
        }
        if (pendingResult != null) {
            result.error(
                "unknown",
                "A document scan is already in progress",
                null,
            )
            return
        }

        val maxPages = (args?.get("maxPages") as? Int) ?: DEFAULT_MAX_PAGES
        // Phase DPX: resolve the nested `processing` map (with the legacy
        // top-level `filter`/`enhanceMode`/`jpegQuality` as fallbacks) into one
        // options struct shared with the embedded paths. The effective JPEG
        // quality — nested `quality` override or the top-level request — is then
        // tier-clamped exactly as before.
        val requestedJpegQuality = (args?.get("jpegQuality") as? Int) ?: DEFAULT_JPEG_QUALITY
        val processing = DocumentProcessingOptions.parse(args, fallbackQuality = requestedJpegQuality)
        val jpegQuality = io.supy.scanner.perf.DeviceTier.detect(activity)
            .jpegQuality(processing.quality)
        // useNativeCore is a v1.1 wire field reserved for the C++ pre-processing
        // path. Read it here so the contract is honored end-to-end; the document
        // launcher still routes to GMS in v1.0 regardless.
        val useNativeCore = (args?.get("useNativeCore") as? Boolean) ?: false
        if (useNativeCore) {
            SupyLog.i(
                message = "Document scan requested useNativeCore=true; ignored on v1.0 (reserved for v1.1).",
            )
        }

        // V1-S7-03/04: per-page encoding + multi-page PDF.
        //   jpg → JPEG-only (v1.0 behaviour).
        //   png → JPEG from GMS, re-encoded to PNG; `jpegQuality` is ignored.
        //   pdf → JPEG pages AND a GMS-assembled PDF; pdfUri surfaced on result.
        // v1.2 Phase DC8:
        //   tiff → JPEG pages AND a self-assembled multi-page TIFF; tiffUri.
        //   searchablePdf → JPEG pages AND a self-assembled PDF carrying an
        //     invisible OCR text layer; pdfUri (GMS's native PDF has no text
        //     layer, so we always build our own from the page URIs + word boxes).
        val outputFormatWire = (args?.get("outputFormat") as? String) ?: "jpg"
        val outputFormat = when (outputFormatWire) {
            "png" -> PageReencoder.Format.PNG
            else -> PageReencoder.Format.JPG
        }
        val wantPdf = outputFormatWire == "pdf"
        val wantTiff = outputFormatWire == "tiff"
        val wantSearchablePdf = outputFormatWire == "searchablePdf"

        // v1.2: optional native enhancement pass on the captured pages.
        // Default = balanced on Android (VisionKit handles iOS internally).
        // DPX: the effective mode also folds in the `processing` stage toggles /
        // filter (original bypass or all-stages-off downgrade to OFF).
        val enhanceMode = processing.enhanceMode

        val resultFormats = if (wantPdf) {
            GmsDocumentScannerOptions.RESULT_FORMAT_JPEG or
                GmsDocumentScannerOptions.RESULT_FORMAT_PDF
        } else {
            GmsDocumentScannerOptions.RESULT_FORMAT_JPEG
        }

        val options = GmsDocumentScannerOptions.Builder()
            .setGalleryImportAllowed(false)
            .setScannerMode(GmsDocumentScannerOptions.SCANNER_MODE_FULL)
            .setResultFormats(resultFormats)
            // 0 = unlimited on our wire contract; map to a reasonable cap.
            .setPageLimit(if (maxPages <= 0) MAX_PAGE_CAP else maxPages)
            .build()

        pendingResult = result
        pendingActivity = activity
        pendingJpegQuality = jpegQuality
        pendingOutputFormat = outputFormat
        pendingWantPdf = wantPdf
        pendingWantTiff = wantTiff
        pendingWantSearchablePdf = wantSearchablePdf
        pendingEnhanceMode = enhanceMode
        pendingMaxDimension = processing.maxDimension
        pendingFilter = processing.filter
        pendingLocale = (args?.get("locale") as? String) ?: "en"
        pendingIntent = (args?.get("intent") as? String) ?: INTENT_GENERIC
        // Wire string from `SupyDocumentPageQuality.name`. The Dart layer
        // resolves caller > intent-preset > defaults, so we trust whatever
        // arrives. Default "veryPoor" admits every page — non-breaking.
        pendingMinPageQualityOrdinal =
            wireToQualityOrdinal((args?.get("minPageQuality") as? String) ?: "veryPoor")

        // v1.2 Phase CXD1: honor `preferredBackend` if the Dart layer set it.
        // `cameraX` forces the fallback even when GMS is usable (tests,
        // dogfood); `gms` only works if GMS is actually usable, else we fall
        // through to the natural availability gate below. `unknown` / null /
        // anything else = auto.
        val preferredBackend = args?.get("preferredBackend") as? String
        val gmsUsable = GmsAvailability.isUsable(activity)
        val useCameraX = shouldUseCameraX(preferredBackend, gmsUsable)

        // v1.2 Phase CXD: when GMS is unavailable, bypass the document-scanner
        // client and launch the CameraX-backed manual capture flow. The
        // re-encode + OCR pipeline downstream is shared with the GMS path —
        // result shape stays identical, retailer code is unchanged.
        if (useCameraX) {
            pendingResolvedBackend = BACKEND_CAMERAX
            val autoCaptureDelayMs = (args?.get("autoCaptureDelayMs") as? Number)?.toInt() ?: 0
            val locale = (args?.get("locale") as? String) ?: "en"
            val intent = Intent(activity, CameraXDocumentScannerActivity::class.java).apply {
                putExtra(CameraXDocumentScannerActivity.EXTRA_MAX_PAGES, maxPages)
                putExtra(CameraXDocumentScannerActivity.EXTRA_AUTO_CAPTURE_DELAY_MS, autoCaptureDelayMs)
                putExtra(CameraXDocumentScannerActivity.EXTRA_LOCALE, locale)
                putExtra(
                    CameraXDocumentScannerActivity.EXTRA_MIN_PAGE_QUALITY,
                    qualityOrdinalToWire(pendingMinPageQualityOrdinal),
                )
            }
            try {
                activity.startActivityForResult(intent, REQUEST_CODE_CAMX)
            } catch (t: Throwable) {
                finishWithError("camera_unavailable", t.message ?: "Failed to start fallback capture")
            }
            return
        }

        pendingResolvedBackend = BACKEND_GMS
        val client = GmsDocumentScanning.getClient(options)
        val task: Task<android.content.IntentSender> = client.getStartScanIntent(activity)
        task
            .addOnSuccessListener { intentSender ->
                try {
                    activity.startIntentSenderForResult(
                        intentSender,
                        REQUEST_CODE,
                        null,
                        0,
                        0,
                        0,
                    )
                } catch (t: Throwable) {
                    finishWithError("unknown", t.message ?: "Failed to start scanner intent")
                }
            }
            .addOnFailureListener { t ->
                finishWithError("model_unavailable", t.message ?: "Scanner unavailable")
            }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode == REQUEST_CODE_CAMX) return onCameraXResult(resultCode, data)
        if (requestCode != REQUEST_CODE) return false
        val pending = pendingResult ?: return false
        val activity = pendingActivity

        if (resultCode != Activity.RESULT_OK || data == null) {
            pendingResult = null
            pendingActivity = null
            pending.error("cancelled", "User cancelled the document scan", null)
            return true
        }

        val scanResult = GmsDocumentScanningResult.fromActivityResultIntent(data)
        val rawUris = scanResult?.pages?.mapNotNull { it.imageUri } ?: emptyList()
        val pdfUri: String? = if (pendingWantPdf) scanResult?.pdf?.uri?.toString() else null
        val pages: List<PageReencoder.ReencodedPage> = if (activity != null && rawUris.isNotEmpty()) {
            PageReencoder.reencode(
                activity.applicationContext,
                rawUris,
                pendingJpegQuality,
                pendingOutputFormat,
                pendingEnhanceMode,
                pendingMaxDimension,
                pendingFilter,
            )
        } else {
            rawUris.map { PageReencoder.ReencodedPage(it, quality = null, qualityScore = null) }
        }

        if (pages.isEmpty() || activity == null) {
            pendingResult = null
            pendingActivity = null
            pending.success(
                buildResponse(
                    pages = emptyList(),
                    ocrText = "",
                    pdfUri = pdfUri,
                ),
            )
            return true
        }

        val capturedPdfUri = pdfUri
        gateLowQualityPages(activity, pages) { acceptedPages ->
            // OCR + dimension decode happens off the UI thread inside OcrRunner —
            // ML Kit dispatches its own executors. Reply on the same thread the
            // success listener fires on (main), which is what Flutter expects.
            // For searchablePdf/tiff we ignore GMS's native PDF (capturedPdfUri
            // is null there anyway) and assemble our own artifact.
            finishWithPages(activity.applicationContext, acceptedPages, capturedPdfUri)
        }
        return true
    }

    /**
     * Shared tail for both backends: runs OCR over [pages], assembles the
     * format-specific export artifact (searchable PDF / TIFF / plain PDF), and
     * resolves the pending channel call exactly once. [plainPdfUri] is the
     * already-resolved `pdf` output (GMS-native or CameraX-assembled) used only
     * when `outputFormat == pdf`. v1.2 Phase DC8.
     */
    private fun finishWithPages(
        context: android.content.Context,
        pages: List<PageReencoder.ReencodedPage>,
        plainPdfUri: String?,
    ) {
        when {
            pendingWantSearchablePdf -> {
                ocrRunner.runWithWords(context, pages) { resultPages, ocrText, wordsPerPage ->
                    val searchable = pages.mapIndexed { i, page ->
                        PdfAssembler.SearchablePage(page.uri, wordsPerPage.getOrElse(i) { emptyList() })
                    }
                    val pdfUri = runCatching {
                        PdfAssembler.assembleSearchable(context, searchable)
                    }.onFailure {
                        SupyLog.i(message = "assembleSearchable failed: ${it.message}")
                    }.getOrNull()?.let { Uri.fromFile(it).toString() }
                    respondSuccess(buildResponse(resultPages, ocrText, pdfUri = pdfUri))
                }
            }
            pendingWantTiff -> {
                ocrRunner.run(context, pages) { resultPages, ocrText ->
                    val tiffUri = runCatching {
                        TiffAssembler.assemble(context, pages.map { it.uri })
                    }.onFailure {
                        SupyLog.i(message = "TiffAssembler failed: ${it.message}")
                    }.getOrNull()?.let { Uri.fromFile(it).toString() }
                    respondSuccess(buildResponse(resultPages, ocrText, pdfUri = null, tiffUri = tiffUri))
                }
            }
            else -> {
                ocrRunner.run(context, pages) { resultPages, ocrText ->
                    respondSuccess(buildResponse(resultPages, ocrText, pdfUri = plainPdfUri))
                }
            }
        }
    }

    /** Resolves the pending `scanDocument` call with [payload] and clears state. */
    private fun respondSuccess(payload: Map<String, Any?>) {
        val pending = pendingResult ?: return
        pendingResult = null
        pendingActivity = null
        pending.success(payload)
    }

    /**
     * Asymmetric quality-gate for the GMS path. GMS owns its own UI, so we
     * can only check pages at flow exit. If any fall below
     * [pendingMinPageQualityOrdinal], surface a single summary dialog with
     * Keep-all / Discard-low choices. The CameraX path gates each page
     * in-flow inside the activity itself — see
     * [CameraXDocumentScannerActivity.shouldGatePage]. Documented in
     * `docs/ARCHITECTURE.md`.
     */
    private fun gateLowQualityPages(
        activity: Activity,
        pages: List<PageReencoder.ReencodedPage>,
        onContinue: (List<PageReencoder.ReencodedPage>) -> Unit,
    ) {
        if (pendingMinPageQualityOrdinal <= 0) {
            onContinue(pages)
            return
        }
        val accepted = pages.filter { page ->
            val ordinal = wireToQualityOrdinal(page.quality ?: return@filter true)
            ordinal >= pendingMinPageQualityOrdinal
        }
        val rejected = pages.size - accepted.size
        if (rejected == 0) {
            onContinue(pages)
            return
        }
        val ar = pendingLocale.startsWith("ar", ignoreCase = true)
        AlertDialog.Builder(activity)
            .setTitle(if (ar) "جودة بعض الصفحات منخفضة" else "Some pages have low quality")
            .setMessage(
                if (ar) "${rejected} من ${pages.size} صفحة دون الحد المطلوب."
                else "$rejected of ${pages.size} pages are below the requested quality.",
            )
            .setPositiveButton(if (ar) "احتفظ بها" else "Keep all") { d, _ ->
                d.dismiss(); onContinue(pages)
            }
            .setNegativeButton(if (ar) "تجاهل المنخفضة" else "Discard low") { d, _ ->
                d.dismiss(); onContinue(accepted)
            }
            .setCancelable(false)
            .show()
    }

    private fun buildResponse(
        pages: List<Map<String, Any?>>,
        ocrText: String,
        pdfUri: String?,
        tiffUri: String? = null,
    ): Map<String, Any?> {
        val payload = mutableMapOf<String, Any?>(
            "pages" to pages,
            "ocrText" to ocrText,
            "resolvedBackend" to pendingResolvedBackend,
        )
        if (pdfUri != null) payload["pdfUri"] = pdfUri
        if (tiffUri != null) payload["tiffUri"] = tiffUri
        return payload
    }

    private fun onCameraXResult(resultCode: Int, data: Intent?): Boolean {
        val pending = pendingResult ?: return false
        val activity = pendingActivity

        when (resultCode) {
            CameraXDocumentScannerActivity.RESULT_PERMISSION_DENIED -> {
                finishWithError("permission_denied", "Camera permission was not granted")
                return true
            }
            CameraXDocumentScannerActivity.RESULT_CAMERA_UNAVAILABLE -> {
                finishWithError("camera_unavailable", "Camera could not be opened")
                return true
            }
        }

        if (resultCode != Activity.RESULT_OK || data == null || activity == null) {
            // Cancel / back resolves with an empty page list to match D4 — the
            // GMS path surfaces `cancelled` via PlatformException, the
            // CameraX path resolves with [] so retailer code sees the same
            // "user cancelled" semantic as iOS VisionKit cancel.
            pendingResult = null
            pendingActivity = null
            pending.success(buildResponse(pages = emptyList(), ocrText = "", pdfUri = null))
            return true
        }

        val rawUris = data
            .getStringArrayListExtra(CameraXDocumentScannerActivity.EXTRA_RESULT_URIS)
            ?.mapNotNull { runCatching { Uri.parse(it) }.getOrNull() }
            ?: emptyList()

        if (rawUris.isEmpty()) {
            pendingResult = null
            pendingActivity = null
            pending.success(buildResponse(pages = emptyList(), ocrText = "", pdfUri = null))
            return true
        }

        // PageReencoder + OcrRunner is shared with the GMS path. v1.2 CXD2:
        // PdfAssembler closes the PDF-output parity gap so `outputFormat=pdf`
        // works on non-GMS devices too — the source pages are the same
        // re-encoded JPEGs OCR runs against.
        val pages = PageReencoder.reencode(
            activity.applicationContext,
            rawUris,
            pendingJpegQuality,
            pendingOutputFormat,
            pendingEnhanceMode,
            pendingMaxDimension,
            pendingFilter,
        )

        val plainPdfUri = if (pendingWantPdf) {
            runCatching {
                PdfAssembler.assemble(activity.applicationContext, pages.map { it.uri })
            }.onFailure {
                SupyLog.i(message = "PdfAssembler failed on CameraX path: ${it.message}")
            }.getOrNull()?.let { Uri.fromFile(it).toString() }
        } else null

        finishWithPages(activity.applicationContext, pages, plainPdfUri)
        return true
    }

    private fun finishWithError(code: String, message: String) {
        val pending = pendingResult ?: return
        pendingResult = null
        pendingActivity = null
        pending.error(code, message, null)
    }

    /**
     * Releases the held [OcrRunner]'s ML Kit `TextRecognizer`. Called from
     * `SupyScannerPlugin.onDetachedFromEngine` — the recognizer is a
     * `Closeable` whose native resources leak if the JVM exits without it.
     */
    fun close() {
        runCatching { ocrRunner.close() }
    }

    companion object {
        private const val REQUEST_CODE = 0x5506
        private const val REQUEST_CODE_CAMX = 0x5507
        private const val DEFAULT_MAX_PAGES = 10
        private const val DEFAULT_JPEG_QUALITY = 85
        private const val MAX_PAGE_CAP = 50
        internal const val BACKEND_GMS = "gms"
        internal const val BACKEND_CAMERAX = "cameraX"
        internal const val BACKEND_UNKNOWN = "unknown"

        internal const val INTENT_GENERIC = "generic"
        internal const val INTENT_INVOICE = "invoice"

        internal fun wireToQualityOrdinal(wire: String?): Int = when (wire) {
            "veryPoor" -> 0
            "poor" -> 1
            "ok" -> 2
            "good" -> 3
            "excellent" -> 4
            else -> 0
        }

        internal fun qualityOrdinalToWire(ordinal: Int): String = when (ordinal) {
            1 -> "poor"
            2 -> "ok"
            3 -> "good"
            4 -> "excellent"
            else -> "veryPoor"
        }

        /// v1.2 Phase CXD1: backend resolution. `cameraX` forces the
        /// fallback even when GMS is usable (tests, dogfood); `gms` only
        /// works if GMS is actually usable, else we fall through to the
        /// natural availability gate. Any other value (null, `unknown`) is
        /// auto.
        internal fun shouldUseCameraX(
            preferredBackend: String?,
            gmsUsable: Boolean,
        ): Boolean = when (preferredBackend) {
            BACKEND_CAMERAX -> true
            BACKEND_GMS -> !gmsUsable
            else -> !gmsUsable
        }
    }
}
