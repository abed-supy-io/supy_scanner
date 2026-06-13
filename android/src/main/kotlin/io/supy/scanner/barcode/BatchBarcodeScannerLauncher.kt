package io.supy.scanner.barcode

import android.app.Activity
import android.content.Intent
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry

/**
 * Bridges a `scanBarcodesBatch` MethodChannel call to
 * [BatchBarcodeScannerActivity] via `startActivityForResult` and maps the
 * activity result back to the pending Flutter `Result`.
 */
class BatchBarcodeScannerLauncher : PluginRegistry.ActivityResultListener {

    private var pendingResult: Result? = null

    fun launch(activity: Activity?, args: Map<String, Any?>?, result: Result) {
        if (activity == null) {
            result.error("camera_unavailable", "No Activity attached", null)
            return
        }
        if (pendingResult != null) {
            result.error(
                "unknown",
                "A batch barcode scan is already in progress",
                null,
            )
            return
        }

        val formats = (args?.get("formats") as? List<*>)
            ?.filterIsInstance<String>()
            ?: emptyList()
        val maxBatchCount = (args?.get("maxBatchCount") as? Int) ?: 0
        val dedupeWindowMs = ((args?.get("dedupeWindowMs") as? Number)?.toLong())
            ?: DEFAULT_DEDUPE_WINDOW_MS
        val beep = (args?.get("beep") as? Boolean) ?: true
        val vibrate = (args?.get("vibrate") as? Boolean) ?: true

        val intent = Intent(activity, BatchBarcodeScannerActivity::class.java).apply {
            putStringArrayListExtra(
                BatchBarcodeScannerActivity.EXTRA_FORMATS,
                ArrayList(formats),
            )
            putExtra(BatchBarcodeScannerActivity.EXTRA_MAX_BATCH, maxBatchCount)
            putExtra(BatchBarcodeScannerActivity.EXTRA_DEDUPE_MS, dedupeWindowMs)
            putExtra(BatchBarcodeScannerActivity.EXTRA_BEEP, beep)
            putExtra(BatchBarcodeScannerActivity.EXTRA_VIBRATE, vibrate)
        }

        pendingResult = result
        try {
            activity.startActivityForResult(intent, REQUEST_CODE)
        } catch (t: Throwable) {
            pendingResult = null
            result.error("unknown", t.message ?: "Failed to launch batch scanner", null)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_CODE) return false
        val pending = pendingResult ?: return false
        pendingResult = null

        if (resultCode != Activity.RESULT_OK || data == null) {
            pending.error("cancelled", "User cancelled the batch scan", null)
            return true
        }

        val rawValues = data
            .getStringArrayListExtra(BatchBarcodeScannerActivity.EXTRA_RESULT_RAW_VALUES)
            ?: arrayListOf()
        val formats = data
            .getStringArrayListExtra(BatchBarcodeScannerActivity.EXTRA_RESULT_FORMATS)
            ?: arrayListOf()
        val duplicateCount = data
            .getIntExtra(BatchBarcodeScannerActivity.EXTRA_RESULT_DUPLICATES, 0)

        val items = rawValues.mapIndexed { index, raw ->
            mapOf(
                "rawValue" to raw,
                "format" to (formats.getOrNull(index) ?: "all"),
            )
        }

        pending.success(
            mapOf(
                "items" to items,
                "duplicateCount" to duplicateCount,
            ),
        )
        return true
    }

    companion object {
        private const val REQUEST_CODE = 0x5507
        private const val DEFAULT_DEDUPE_WINDOW_MS: Long = 800L
    }
}
