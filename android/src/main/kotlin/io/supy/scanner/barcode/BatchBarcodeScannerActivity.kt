package io.supy.scanner.barcode

import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
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
import android.widget.FrameLayout
import android.widget.TextView
import androidx.annotation.MainThread
import androidx.annotation.WorkerThread
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
import io.supy.scanner.nativecore.NativeBarcode
import io.supy.scanner.nativecore.SupyNativeCore
import java.nio.ByteBuffer
import java.util.ArrayList
import java.util.concurrent.Executor
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

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
    private lateinit var doneButton: TextView

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

    private var nativeCoreEnabled: Boolean = false
    private var nativeDmLocateEnabled: Boolean = false
    private var nativeFormatMask: Int = -1
    private var analyzerExecutorImpl: ExecutorService? = null

    @MainThread
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

        val wireFormats = intent.getStringArrayListExtra(EXTRA_FORMATS).orEmpty()
        maxBatchCount = intent.getIntExtra(EXTRA_MAX_BATCH, 0)
        dedupeWindowMs = intent.getLongExtra(EXTRA_DEDUPE_MS, DEFAULT_DEDUPE_WINDOW_MS)
        beepOnAcquire = intent.getBooleanExtra(EXTRA_BEEP, true)
        vibrateOnAcquire = intent.getBooleanExtra(EXTRA_VIBRATE, true)
        val useNativeCoreRequested = intent.getBooleanExtra(EXTRA_USE_NATIVE_CORE, false)
        nativeCoreEnabled = useNativeCoreRequested && SupyNativeCore.hasZxing()
        nativeDmLocateEnabled = nativeCoreEnabled && SupyNativeCore.hasLibdmtx()
        nativeFormatMask = FormatMapper.toSupyFormatMask(wireFormats)

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
        runCatching { analyzerExecutorImpl?.shutdown() }
        analyzerExecutorImpl = null
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
            background = pillBackground(SCRIM_BLACK_055, dp(14))
            setPadding(dp(16), dp(8), dp(16), dp(8))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 17f)
            typeface = Typeface.create(typeface, Typeface.BOLD)
            gravity = Gravity.CENTER
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
            ).apply {
                gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
                topMargin = dp(16) + statusBarInset()
                minimumWidth = dp(120)
            }
        }
        root.addView(counterLabel)

        val cancelButton = TextView(this).apply {
            text = "Cancel"
            setTextColor(Color.WHITE)
            background = pillBackground(SCRIM_BLACK_055, dp(22))
            setPadding(dp(22), dp(10), dp(22), dp(10))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 17f)
            gravity = Gravity.CENTER
            isClickable = true
            isFocusable = true
            setOnClickListener { finishCancelled() }
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
            ).apply {
                gravity = Gravity.BOTTOM or Gravity.START
                bottomMargin = dp(24)
                leftMargin = dp(20)
            }
        }
        root.addView(cancelButton)

        doneButton = TextView(this).apply {
            text = "Done"
            setTextColor(Color.WHITE)
            background = pillBackground(SUPY_PRIMARY, dp(22))
            setPadding(dp(28), dp(10), dp(28), dp(10))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 17f)
            typeface = Typeface.create(typeface, Typeface.BOLD)
            gravity = Gravity.CENTER
            isClickable = true
            isFocusable = true
            setOnClickListener { finishOk() }
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
            ).apply {
                gravity = Gravity.BOTTOM or Gravity.END
                bottomMargin = dp(24)
                rightMargin = dp(20)
            }
        }
        root.addView(doneButton)

        return root
    }

    private fun pillBackground(color: Int, radius: Int): GradientDrawable =
        GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = radius.toFloat()
            setColor(color)
        }

    private fun statusBarInset(): Int {
        val id = resources.getIdentifier("status_bar_height", "dimen", "android")
        return if (id > 0) resources.getDimensionPixelSize(id) else 0
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
        // Native decode is CPU-bound and must not run on the main thread.
        // ML Kit's process() is async — its callbacks land back on main via the
        // default Task executor — so running the analyzer on a background thread
        // doesn't change the existing UI-callback contract.
        val executor: Executor = if (nativeCoreEnabled) {
            val ex = Executors.newSingleThreadExecutor { r ->
                Thread(r, "supy-batch-analyzer").apply { isDaemon = true }
            }
            analyzerExecutorImpl = ex
            ex
        } else {
            ContextCompat.getMainExecutor(this@BatchBarcodeScannerActivity)
        }
        val controller = LifecycleCameraController(this).apply {
            setImageAnalysisBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
            setImageAnalysisAnalyzer(executor, AnalyzerImpl())
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
        @WorkerThread
        override fun analyze(image: ImageProxy) {
            if (nativeCoreEnabled && tryNativeDecode(image)) {
                return
            }
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

        /**
         * Attempts a native-core decode of [image]'s Y plane. Returns true when
         * the native path took ownership of the frame (image closed here); false
         * when the caller should fall through to ML Kit on the same frame.
         */
        private fun tryNativeDecode(image: ImageProxy): Boolean {
            val planes = image.planes
            if (planes.isEmpty()) return false
            val yPlane = planes[0]
            if (yPlane.pixelStride != 1) return false
            val buf = yPlane.buffer
            if (!buf.isDirect) return false
            val w = image.width
            val h = image.height
            val rowStride = yPlane.rowStride
            if (w <= 0 || h <= 0 || rowStride < w) return false

            val mask = nativeFormatMask
            val dmHits: List<NativeBarcode> = if (
                nativeDmLocateEnabled && FormatMapper.maskIncludesDataMatrix(mask)
            ) {
                tryDatamatrixRoiAssist(buf, w, h, rowStride)
            } else {
                emptyList()
            }

            val fullMask = if (dmHits.isNotEmpty() || nativeDmLocateEnabled) {
                FormatMapper.maskWithoutDataMatrix(mask)
            } else {
                mask
            }

            val full: List<NativeBarcode>? = if (fullMask != 0) {
                try {
                    SupyNativeCore.decodeBarcodes(
                        buf, w, h, rowStride,
                        fullMask,
                        tryHarder = false,
                        tryRotate = true,
                    )
                } catch (_: Throwable) {
                    null
                }
            } else {
                emptyList()
            }
            if (full == null && dmHits.isEmpty()) {
                // Nothing ran successfully — fall back to ML Kit.
                return false
            }
            val merged: List<NativeBarcode> = if (full == null || full.isEmpty()) {
                dmHits
            } else if (dmHits.isEmpty()) {
                full
            } else {
                ArrayList<NativeBarcode>(dmHits.size + full.size).also {
                    it.addAll(dmHits); it.addAll(full)
                }
            }
            image.close()
            if (merged.isNotEmpty()) {
                runOnUiThread { handleNativeDetections(merged) }
            }
            return true
        }

        // V1-S2-06.2: ring of the last two locator-hit frames used for
        // temporal median-of-3 luma fusion. Owned by the analyzer; never
        // touched off-thread.
        private val temporalRing = DatamatrixTemporalRing()

        // Runs the libdmtx locator on the luma plane, then re-feeds each region's
        // axis-aligned bbox crop into the native decode with a DM-only mask.
        // Returns an empty list on miss / locator failure — callers treat empty
        // and "locator off" identically and continue to the full-frame decode.
        private fun tryDatamatrixRoiAssist(
            buf: ByteBuffer,
            w: Int,
            h: Int,
            rowStride: Int,
        ): List<NativeBarcode> {
            val regions = try {
                SupyNativeCore.locateDatamatrix(buf, w, h, rowStride)
            } catch (_: Throwable) {
                null
            } ?: return emptyList()
            if (regions.isEmpty()) return emptyList()

            val hits = ArrayList<NativeBarcode>(regions.size)
            val frameBoxes = ArrayList<DatamatrixTemporalRing.Box>(regions.size)
            for (q in regions) {
                if (q.size != 8) continue
                var minX = q[0]; var maxX = q[0]
                var minY = q[1]; var maxY = q[1]
                var i = 2
                while (i < 8) {
                    val x = q[i]; val y = q[i + 1]
                    if (x < minX) minX = x; if (x > maxX) maxX = x
                    if (y < minY) minY = y; if (y > maxY) maxY = y
                    i += 2
                }
                val padX = ((maxX - minX) * 0.06f).coerceAtLeast(2f)
                val padY = ((maxY - minY) * 0.06f).coerceAtLeast(2f)
                val rx0 = (minX - padX).toInt().coerceAtLeast(0)
                val ry0 = (minY - padY).toInt().coerceAtLeast(0)
                val rx1 = (maxX + padX).toInt().coerceAtMost(w - 1)
                val ry1 = (maxY + padY).toInt().coerceAtMost(h - 1)
                if (rx1 - rx0 + 1 < 12 || ry1 - ry0 + 1 < 12) continue
                val box = DatamatrixTemporalRing.Box(rx0, ry0, rx1, ry1)
                frameBoxes.add(box)

                // V1-S2-06.2: prefer the temporal-median fusion when this
                // region IoU-matched bboxes in BOTH prior frames. Otherwise
                // fall back to the raw current-frame luma — the same path
                // V1-S2-05.1 shipped with.
                val fused = temporalRing.tryFuse(buf, w, h, rowStride, box)
                val cropBuf: ByteBuffer
                val cw: Int
                val ch: Int
                val srcX0: Int
                val srcY0: Int
                if (fused != null) {
                    cropBuf = fused.luma
                    cw = fused.width
                    ch = fused.height
                    srcX0 = fused.srcX0
                    srcY0 = fused.srcY0
                } else {
                    cw = rx1 - rx0 + 1
                    ch = ry1 - ry0 + 1
                    srcX0 = rx0
                    srcY0 = ry0
                    val raw = ensureCropCapacity(cw * ch)
                    copyLumaCrop(buf, rowStride, srcX0, srcY0, cw, ch, raw)
                    cropBuf = raw
                }
                // V1-S2-05.1: Sauvola adaptive binarization on the DM crop
                // before zxing-cpp sees it. Soft fallback on failure.
                try {
                    SupyNativeCore.binarizeLumaCrop(
                        y = cropBuf,
                        w = cw,
                        h = ch,
                        rowStride = cw,
                        mode = SupyNativeCore.BinarizeMode.Sauvola2D,
                    )
                } catch (_: Throwable) {
                    // ignore — proceed with raw luma
                }
                val dm = try {
                    SupyNativeCore.decodeBarcodes(
                        y = cropBuf,
                        w = cw,
                        h = ch,
                        rowStride = cw,
                        formatMask = FormatMapper.SUPY_FORMAT_DATA_MATRIX_BIT,
                        tryHarder = true,
                        tryRotate = true,
                    )
                } catch (_: Throwable) {
                    null
                } ?: continue
                if (dm.isEmpty()) continue
                for (b in dm) {
                    val translated = FloatArray(8)
                    var j = 0
                    while (j < 8) {
                        translated[j]     = b.corners[j] + srcX0
                        translated[j + 1] = b.corners[j + 1] + srcY0
                        j += 2
                    }
                    hits.add(NativeBarcode(b.rawValue, b.formatBit, translated))
                }
            }

            // Push this frame into the ring AFTER per-region fusion attempts
            // so the next frame can match against today's located bboxes.
            if (frameBoxes.isNotEmpty()) {
                temporalRing.push(buf, w, h, rowStride, frameBoxes)
            }
            return hits
        }

        // Reusable packed luma crop buffer — direct, grown lazily.
        private var cropBuffer: ByteBuffer? = null

        private fun ensureCropCapacity(needed: Int): ByteBuffer {
            val cur = cropBuffer
            if (cur != null && cur.capacity() >= needed) {
                cur.clear()
                return cur
            }
            val grown = ByteBuffer.allocateDirect(needed + (needed shr 1))
            cropBuffer = grown
            return grown
        }

        private fun copyLumaCrop(
            src: ByteBuffer,
            srcStride: Int,
            x0: Int,
            y0: Int,
            cw: Int,
            ch: Int,
            dst: ByteBuffer,
        ) {
            val srcView = src.duplicate()
            dst.position(0).limit(dst.capacity())
            val row = ByteArray(cw)
            for (yy in 0 until ch) {
                val srcOff = (y0 + yy) * srcStride + x0
                srcView.position(srcOff)
                srcView.get(row, 0, cw)
                dst.put(row, 0, cw)
            }
            dst.flip()
        }
    }

    private fun handleNativeDetections(barcodes: List<NativeBarcode>) {
        if (finished) return
        val now = SystemClock.elapsedRealtime()
        var added = false
        for (b in barcodes) {
            val raw = b.rawValue
            if (raw.isEmpty()) continue
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
                    "format" to FormatMapper.supyBitToWire(b.formatBit),
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
        const val EXTRA_USE_NATIVE_CORE = "io.supy.scanner.batch.useNativeCore"

        const val EXTRA_RESULT_RAW_VALUES = "io.supy.scanner.batch.result.rawValues"
        const val EXTRA_RESULT_FORMATS = "io.supy.scanner.batch.result.formats"
        const val EXTRA_RESULT_DUPLICATES = "io.supy.scanner.batch.result.duplicates"

        private const val DEFAULT_DEDUPE_WINDOW_MS: Long = 800L
        private const val BEEP_VOLUME = 80
        private const val BEEP_DURATION_MS = 120
        private const val VIBRATE_DURATION_MS: Long = 40L

        // Supy brand primary (matches `SupyScannerPalette.scanbotDark.primary`
        // = 0xFF1AC0E5). Mirrored on iOS in BatchBarcodeScannerPresenter.swift.
        private const val SUPY_PRIMARY: Int = 0xFF1AC0E5.toInt()
        // Translucent black scrim used for the counter chip and Cancel chip.
        // alpha 140/255 ≈ 0.55, matching iOS UIColor.black.withAlphaComponent(0.55).
        private const val SCRIM_BLACK_055: Int = 0x8C000000.toInt()
    }
}
