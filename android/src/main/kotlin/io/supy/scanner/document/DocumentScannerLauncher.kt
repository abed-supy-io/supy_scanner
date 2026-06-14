package io.supy.scanner.document

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.util.Log
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
    private val ocrRunner: OcrRunner = OcrRunner()

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
        val requestedJpegQuality = (args?.get("jpegQuality") as? Int) ?: DEFAULT_JPEG_QUALITY
        val jpegQuality = io.supy.scanner.perf.DeviceTier.detect(activity)
            .jpegQuality(requestedJpegQuality)
        // useNativeCore is a v1.1 wire field reserved for the C++ pre-processing
        // path. Read it here so the contract is honored end-to-end; the document
        // launcher still routes to GMS in v1.0 regardless.
        val useNativeCore = (args?.get("useNativeCore") as? Boolean) ?: false
        if (useNativeCore) {
            Log.i(
                "SupyScanner",
                "Document scan requested useNativeCore=true; ignored on v1.0 (reserved for v1.1).",
            )
        }

        // V1-S7-03/04: per-page encoding + multi-page PDF.
        //   jpg → JPEG-only (v1.0 behaviour).
        //   png → JPEG from GMS, re-encoded to PNG; `jpegQuality` is ignored.
        //   pdf → JPEG pages AND a GMS-assembled PDF; pdfUri surfaced on result.
        val outputFormatWire = (args?.get("outputFormat") as? String) ?: "jpg"
        val outputFormat = when (outputFormatWire) {
            "png" -> PageReencoder.Format.PNG
            else -> PageReencoder.Format.JPG
        }
        val wantPdf = outputFormatWire == "pdf"

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

        // v1.2 Phase CXD: when GMS is unavailable, bypass the document-scanner
        // client and launch the CameraX-backed manual capture flow. The
        // re-encode + OCR pipeline downstream is shared with the GMS path —
        // result shape stays identical, retailer code is unchanged.
        if (!GmsAvailability.isUsable(activity)) {
            if (wantPdf) {
                Log.i(
                    "SupyScanner",
                    "outputFormat=pdf requested but Play services is unavailable; " +
                        "the CameraX fallback emits JPEG only (v1.2 limitation).",
                )
            }
            val intent = Intent(activity, CameraXDocumentScannerActivity::class.java).apply {
                putExtra(CameraXDocumentScannerActivity.EXTRA_MAX_PAGES, maxPages)
            }
            try {
                activity.startActivityForResult(intent, REQUEST_CODE_CAMX)
            } catch (t: Throwable) {
                finishWithError("camera_unavailable", t.message ?: "Failed to start fallback capture")
            }
            return
        }

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
        val pageUris = if (activity != null && rawUris.isNotEmpty()) {
            PageReencoder.reencode(
                activity.applicationContext,
                rawUris,
                pendingJpegQuality,
                pendingOutputFormat,
            )
        } else {
            rawUris
        }

        if (pageUris.isEmpty() || activity == null) {
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
        // OCR + dimension decode happens off the UI thread inside OcrRunner —
        // ML Kit dispatches its own executors. Reply on the same thread the
        // success listener fires on (main), which is what Flutter expects.
        ocrRunner.run(activity.applicationContext, pageUris) { pages, ocrText ->
            pendingResult = null
            pendingActivity = null
            pending.success(
                buildResponse(
                    pages = pages,
                    ocrText = ocrText,
                    pdfUri = capturedPdfUri,
                ),
            )
        }
        return true
    }

    private fun buildResponse(
        pages: List<Map<String, Any?>>,
        ocrText: String,
        pdfUri: String?,
    ): Map<String, Any?> {
        val payload = mutableMapOf<String, Any?>(
            "pages" to pages,
            "ocrText" to ocrText,
        )
        if (pdfUri != null) payload["pdfUri"] = pdfUri
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

        // PageReencoder + OcrRunner is shared with the GMS path. The CameraX
        // fallback never emits PDF (see launch() log), so pdfUri stays null.
        val pageUris = PageReencoder.reencode(
            activity.applicationContext,
            rawUris,
            pendingJpegQuality,
            pendingOutputFormat,
        )

        ocrRunner.run(activity.applicationContext, pageUris) { pages, ocrText ->
            pendingResult = null
            pendingActivity = null
            pending.success(buildResponse(pages = pages, ocrText = ocrText, pdfUri = null))
        }
        return true
    }

    private fun finishWithError(code: String, message: String) {
        val pending = pendingResult ?: return
        pendingResult = null
        pendingActivity = null
        pending.error(code, message, null)
    }

    companion object {
        private const val REQUEST_CODE = 0x5506
        private const val REQUEST_CODE_CAMX = 0x5507
        private const val DEFAULT_MAX_PAGES = 10
        private const val DEFAULT_JPEG_QUALITY = 85
        private const val MAX_PAGE_CAP = 50
    }
}
