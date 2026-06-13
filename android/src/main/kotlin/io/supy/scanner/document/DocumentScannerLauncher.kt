package io.supy.scanner.document

import android.app.Activity
import android.content.Intent
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
        val jpegQuality = (args?.get("jpegQuality") as? Int) ?: DEFAULT_JPEG_QUALITY

        val options = GmsDocumentScannerOptions.Builder()
            .setGalleryImportAllowed(false)
            .setScannerMode(GmsDocumentScannerOptions.SCANNER_MODE_FULL)
            .setResultFormats(GmsDocumentScannerOptions.RESULT_FORMAT_JPEG)
            // 0 = unlimited on our wire contract; map to a reasonable cap.
            .setPageLimit(if (maxPages <= 0) MAX_PAGE_CAP else maxPages)
            .build()

        pendingResult = result
        pendingActivity = activity
        pendingJpegQuality = jpegQuality
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
        val pageUris = if (activity != null && rawUris.isNotEmpty()) {
            JpegReencoder.reencode(activity.applicationContext, rawUris, pendingJpegQuality)
        } else {
            rawUris
        }

        if (pageUris.isEmpty() || activity == null) {
            pendingResult = null
            pendingActivity = null
            pending.success(
                mapOf(
                    "pages" to emptyList<Map<String, Any?>>(),
                    "ocrText" to "",
                ),
            )
            return true
        }

        // OCR + dimension decode happens off the UI thread inside OcrRunner —
        // ML Kit dispatches its own executors. Reply on the same thread the
        // success listener fires on (main), which is what Flutter expects.
        ocrRunner.run(activity.applicationContext, pageUris) { pages, ocrText ->
            pendingResult = null
            pendingActivity = null
            pending.success(
                mapOf(
                    "pages" to pages,
                    "ocrText" to ocrText,
                ),
            )
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
        private const val DEFAULT_MAX_PAGES = 10
        private const val DEFAULT_JPEG_QUALITY = 85
        private const val MAX_PAGE_CAP = 50
    }
}
