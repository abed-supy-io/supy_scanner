package io.supy.scanner.barcode

import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.media.AudioManager
import android.media.ToneGenerator
import android.os.Build
import android.os.Bundle
import android.os.SystemClock
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.Button
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import androidx.camera.core.ExperimentalGetImage
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.view.LifecycleCameraController
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import com.google.mlkit.vision.barcode.BarcodeScanner
import com.google.mlkit.vision.barcode.BarcodeScannerOptions
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.common.InputImage
import java.util.ArrayList

/**
 * Full-screen long-lived barcode session.
 *
 * Accumulates unique payloads into an ordered list and exits through three
 * paths:
 *   - the Done button (RESULT_OK with payload),
 *   - `maxBatchCount` cap reached (RESULT_OK with payload, auto-finish),
 *   - back press or cancel (RESULT_CANCELED, plugin maps to `cancelled`).
 *
 * Dedupe: same `rawValue` seen within `dedupeWindowMs` of its previous sighting
 * is suppressed; first appearance always goes into `items`. Counter shows the
 * size of `items`, not raw detection volume.
 */
class BatchBarcodeScannerActivity : AppCompatActivity() {

    private lateinit var previewView: PreviewView
    private lateinit var counterLabel: TextView
    private lateinit var doneButton: Button

    private var cameraController: LifecycleCameraController? = null
    private var barcodeScanner: BarcodeScanner? = null
    private var toneGenerator: ToneGenerator? = null

    private val items: MutableList<Map<String, Any?>> = ArrayList()
    private val seen: MutableSet<String> = HashSet()
    private val lastSeenAt: MutableMap<String, Long> = HashMap()
    private var duplicateCount: Int = 0

    private var maxBatchCount: Int = 0
    private var dedupeWindowMs: Long = DEFAULT_DEDUPE_WINDOW_MS
    private var beepOnAcquire: Boolean = true
    private var vibrateOnAcquire: Boolean = true
    private var finished: Boolean = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

        val wireFormats = intent.getStringArrayListExtra(EXTRA_FORMATS).orEmpty()
        maxBatchCount = intent.getIntExtra(EXTRA_MAX_BATCH, 0)
        dedupeWindowMs = intent.getLongExtra(EXTRA_DEDUPE_MS, DEFAULT_DEDUPE_WINDOW_MS)
        beepOnAcquire = intent.getBooleanExtra(EXTRA_BEEP, true)
        vibrateOnAcquire = intent.getBooleanExtra(EXTRA_VIBRATE, true)

        setContentView(buildUi())

        barcodeScanner = createScanner(wireFormats)
        if (beepOnAcquire) {
            toneGenerator = runCatching {
                ToneGenerator(AudioManager.STREAM_MUSIC, BEEP_VOLUME)
            }.getOrNull()
        }

        startCamera()
    }

    override fun onDestroy() {
        cameraController?.clearImageAnalysisAnalyzer()
        cameraController?.unbind()
        cameraController = null
        runCatching { barcodeScanner?.close() }
        barcodeScanner = null
        toneGenerator?.release()
        toneGenerator = null
        super.onDestroy()
    }

    // ───────── UI ─────────

    @SuppressLint("SetTextI18n")
    private fun buildUi(): View {
        val root = FrameLayout(this).apply {
            setBackgroundColor(Color.BLACK)
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            )
        }

        previewView = PreviewView(this).apply {
            scaleType = PreviewView.ScaleType.FILL_CENTER
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            )
        }
        root.addView(previewView)

        val padding = dp(16)

        counterLabel = TextView(this).apply {
            text = formatCounter()
            setTextColor(Color.WHITE)
            setBackgroundColor(Color.argb(160, 0, 0, 0))
            setPadding(padding, padding, padding, padding)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
            ).apply {
                gravity = Gravity.TOP or Gravity.START
                topMargin = dp(48)
                leftMargin = padding
            }
        }
        root.addView(counterLabel)

        doneButton = Button(this).apply {
            text = "Done"
            setOnClickListener { finishOk() }
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
            ).apply {
                gravity = Gravity.BOTTOM or Gravity.END
                bottomMargin = dp(32)
                rightMargin = padding
            }
        }
        root.addView(doneButton)

        val controlsRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
            ).apply {
                gravity = Gravity.BOTTOM or Gravity.START
                bottomMargin = dp(32)
                leftMargin = padding
            }
        }
        val cancelButton = Button(this).apply {
            text = "Cancel"
            setOnClickListener { finishCancelled() }
        }
        controlsRow.addView(cancelButton)
        root.addView(controlsRow)

        return root
    }

    private fun dp(value: Int): Int =
        (value * resources.displayMetrics.density).toInt()

    @SuppressLint("SetTextI18n")
    private fun formatCounter(): String {
        return if (maxBatchCount > 0) {
            "${items.size} / $maxBatchCount"
        } else {
            "${items.size}"
        }
    }

    // ───────── Camera ─────────

    private fun startCamera() {
        val controller = LifecycleCameraController(this).apply {
            setImageAnalysisBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
            setImageAnalysisAnalyzer(
                ContextCompat.getMainExecutor(this@BatchBarcodeScannerActivity),
                AnalyzerImpl(),
            )
            bindToLifecycle(this@BatchBarcodeScannerActivity)
        }
        previewView.controller = controller
        cameraController = controller
    }

    private fun createScanner(wireFormats: List<String>): BarcodeScanner {
        val formats = FormatMapper.toMlKitFormats(wireFormats)
        return if (formats == null) {
            BarcodeScanning.getClient()
        } else {
            val head = formats.first()
            val tail = formats.drop(1).toIntArray()
            val options = BarcodeScannerOptions.Builder()
                .setBarcodeFormats(head, *tail)
                .build()
            BarcodeScanning.getClient(options)
        }
    }

    // ───────── Analyzer ─────────

    private inner class AnalyzerImpl : ImageAnalysis.Analyzer {

        @SuppressLint("UnsafeOptInUsageError")
        @OptIn(ExperimentalGetImage::class)
        override fun analyze(image: ImageProxy) {
            val mediaImage = image.image
            val scanner = barcodeScanner
            if (mediaImage == null || scanner == null) {
                image.close()
                return
            }
            val input = InputImage.fromMediaImage(
                mediaImage,
                image.imageInfo.rotationDegrees,
            )
            scanner.process(input)
                .addOnSuccessListener { barcodes ->
                    if (barcodes.isNotEmpty()) {
                        handleDetections(barcodes)
                    }
                }
                .addOnCompleteListener { image.close() }
        }
    }

    private fun handleDetections(barcodes: List<Barcode>) {
        if (finished) return
        val now = SystemClock.elapsedRealtime()
        var added = false
        for (b in barcodes) {
            val raw = b.rawValue ?: continue
            val lastAt = lastSeenAt[raw]
            if (lastAt != null && now - lastAt < dedupeWindowMs) {
                duplicateCount += 1
                lastSeenAt[raw] = now
                continue
            }
            lastSeenAt[raw] = now
            if (seen.contains(raw)) {
                duplicateCount += 1
                continue
            }
            seen.add(raw)
            items.add(
                mapOf(
                    "rawValue" to raw,
                    "format" to FormatMapper.mlKitToWire(b.format),
                )
            )
            added = true
            if (maxBatchCount in 1..items.size) break
        }
        if (added) {
            counterLabel.text = formatCounter()
            fireFeedback()
            if (maxBatchCount in 1..items.size) {
                finishOk()
            }
        }
    }

    private fun fireFeedback() {
        if (beepOnAcquire) {
            runCatching {
                toneGenerator?.startTone(ToneGenerator.TONE_PROP_BEEP, BEEP_DURATION_MS)
            }
        }
        if (vibrateOnAcquire) {
            triggerVibration()
        }
    }

    @Suppress("DEPRECATION")
    private fun triggerVibration() {
        val vibrator: Vibrator? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val manager = getSystemService(Context.VIBRATOR_MANAGER_SERVICE)
                as? VibratorManager
            manager?.defaultVibrator
        } else {
            getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        }
        if (vibrator == null || !vibrator.hasVibrator()) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator.vibrate(
                VibrationEffect.createOneShot(
                    VIBRATE_DURATION_MS,
                    VibrationEffect.DEFAULT_AMPLITUDE,
                )
            )
        } else {
            vibrator.vibrate(VIBRATE_DURATION_MS)
        }
    }

    // ───────── Lifecycle exits ─────────

    override fun onBackPressed() {
        finishCancelled()
    }

    private fun finishOk() {
        if (finished) return
        finished = true
        // Two parallel string arrays keep the wire payload Parcelable-free.
        val data = Intent().apply {
            putExtra(EXTRA_RESULT_DUPLICATES, duplicateCount)
            putStringArrayListExtra(
                EXTRA_RESULT_RAW_VALUES,
                ArrayList(items.mapNotNull { it["rawValue"] as? String }),
            )
            putStringArrayListExtra(
                EXTRA_RESULT_FORMATS,
                ArrayList(items.mapNotNull { it["format"] as? String }),
            )
        }
        setResult(RESULT_OK, data)
        finish()
    }

    private fun finishCancelled() {
        if (finished) return
        finished = true
        setResult(RESULT_CANCELED)
        finish()
    }

    companion object {
        const val EXTRA_FORMATS = "io.supy.scanner.batch.formats"
        const val EXTRA_MAX_BATCH = "io.supy.scanner.batch.maxCount"
        const val EXTRA_DEDUPE_MS = "io.supy.scanner.batch.dedupeMs"
        const val EXTRA_BEEP = "io.supy.scanner.batch.beep"
        const val EXTRA_VIBRATE = "io.supy.scanner.batch.vibrate"

        const val EXTRA_RESULT_RAW_VALUES = "io.supy.scanner.batch.result.rawValues"
        const val EXTRA_RESULT_FORMATS = "io.supy.scanner.batch.result.formats"
        const val EXTRA_RESULT_DUPLICATES = "io.supy.scanner.batch.result.duplicates"

        private const val DEFAULT_DEDUPE_WINDOW_MS: Long = 800L
        private const val BEEP_VOLUME = 80
        private const val BEEP_DURATION_MS = 120
        private const val VIBRATE_DURATION_MS: Long = 40L
    }
}
